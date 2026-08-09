;;; livelove.el --- Live coding bridge for LÖVE 2D  -*- lexical-binding: t; -*-

;; Author: Lucas
;; Version: 0.1.0
;; Package-Requires: ((emacs "31.0"))
;; Keywords: games, tools

;;; Commentary:
;;
;; Usage:
;; (global-livelove-mode 1) ; auto-enable in Lua buffers of LÖVE projects
;; or, per buffer: M-x livelove-mode
;; then run the game with M-x livelove-run.
;;
;; The game connects to the server once, without retrying, so the server must
;; be listening before the game starts, `livelove-run' takes care of that order.
;; Other commands: `livelove-status', `livelove-show-log', `livelove-stop'.
;;
;; A project needs only its own `main.lua' with the livelove boilerplate (see
;; the game side): require livelove, then call `livelove.instantupdate' and
;; `livelove.postdraw'.  `livelove-run' links the Lua support files the game
;; needs into the project from `livelove-support-dir'; set
;; `livelove-link-support-files' to nil to manage them yourself.
;;
;;; Code:

(defgroup livelove nil
  "Live coding and live feedback for LÖVE 2D games."
  :group 'tools
  :prefix "livelove-")

(defcustom livelove-host "127.0.0.1"
  "Address the livelove TCP server listens on.
Keep this loopback-only unless you understand the exposure."
  :type 'string)

(defcustom livelove-port 12345
  "TCP port the livelove server listens on.
The LÖVE client hard-codes 12345; change it only if you patch the game too."
  :type 'natnum)

(defcustom livelove-log-level 'info
  "Minimum severity recorded in the livelove log buffer.
Set to nil to disable logging entirely."
  :type '(choice (const :tag "Debug"    debug)
                 (const :tag "Info"     info)
                 (const :tag "Warning"  warning)
                 (const :tag "Error"    error)
                 (const :tag "Disabled" nil)))

;; ===============================================================
;;; Protocol constants and state

(defconst livelove--frame-terminator "\n---END---\n"
  "Delimiter that terminates every livelove protocol frame.")

(defconst livelove--log-buffer-name "*livelove-log*"
  "Name of the buffer holding livelove log output.")

(defconst livelove--log-severity '(debug 0 info 1 warning 2 error 3)
  "Plist mapping each log level to its numeric severity.")

(defvar livelove--server nil
  "The livelove server process, or nil when stopped.")

(defvar livelove--clients nil
  "List of live client processes (connected LÖVE games).")

(defvar livelove--managed-buffers nil
  "List of buffers currently tracked for live coding.")

(defvar livelove--dirty-buffers nil
  "Tracked buffers whose source changed and await a FILE_UPDATE.")

(defvar livelove--flush-timer nil
  "Debounce timer coalescing pending FILE_UPDATE sends.")

(defvar livelove-connect-functions nil
  "Abnormal hook run when a game connects, called with the client process.")

(defvar livelove-frame-functions nil
  "Abnormal hook run for each received frame, with (HEADER PAYLOAD CLIENT).
HEADER is the frame's first line, PAYLOAD the rest (or nil), CLIENT the process.")

(defvar-local livelove--values nil
  "Hash table mapping a variable name to its latest value string.")

(defvar-local livelove--overlays nil
  "Hash table mapping a variable name to its list of value overlays.")

(defvar-local livelove--dirty-positions t
  "Non-nil when overlay positions may be stale after a buffer change.")

(defvar-local livelove--label-widths nil
  "Hash table mapping a variable name to the (MAX-LEFT . MAX-RIGHT)
value widths seen, used to keep numeric overlays from jittering.")

;; ===============================================================
;;; Logging

(defun livelove--log-buffer ()
  "Return the livelove log buffer, creating it in `special-mode' if needed."
  (or (get-buffer livelove--log-buffer-name)
      (with-current-buffer (get-buffer-create livelove--log-buffer-name)
        (special-mode)
        (current-buffer))))

(defun livelove--log-enabled-p (level)
  "Return non-nil when a message at LEVEL should be recorded."
  (and livelove-log-level
       (>= (plist-get livelove--log-severity level)
           (plist-get livelove--log-severity livelove-log-level))))

(defun livelove--log (level format &rest args)
  "Record a livelove log entry at LEVEL, formatting FORMAT with ARGS."
  (when (livelove--log-enabled-p level)
    (let ((line (format "[%s] %-7s %s\n"
                        (format-time-string "%H:%M:%S")
                        (upcase (symbol-name level))
                        (apply #'format format args))))
      (with-current-buffer (livelove--log-buffer)
        (let ((inhibit-read-only t))
          (goto-char (point-max))
          (insert line))))))

(defun livelove-show-log ()
  "Display the livelove log buffer."
  (interactive)
  (display-buffer (livelove--log-buffer)))

;; ===============================================================
;;; Incoming frames

(defun livelove--dispatch-frame (raw client)
  "Dispatch a single protocol frame RAW received from CLIENT.
RAW still has its surrounding newlines; they are trimmed here."
  (let* ((frame (string-trim raw))
         (newline (string-search "\n" frame))
         (header (if newline (substring frame 0 newline) frame))
         (payload (and newline (substring frame (1+ newline)))))
    (livelove--log 'debug "Recv %s from %s" header (process-name client))
    (run-hook-with-args 'livelove-frame-functions header payload client)))

(defun livelove--client-filter (client chunk)
  "Accumulate CHUNK from CLIENT and dispatch every complete frame."
  (let ((data (concat (process-get client 'livelove--buffer) chunk))
        (start 0))
    (while-let ((end (string-search livelove--frame-terminator data start)))
      (livelove--dispatch-frame (substring data start end) client)
      (setq start (+ end (length livelove--frame-terminator))))
    (process-put client 'livelove--buffer (substring data start))))

;; ===============================================================
;;; Outgoing frames

(defun livelove--frame (header &optional payload)
  "Return a protocol frame carrying HEADER and optional PAYLOAD."
  (if payload
      (concat "\n" header "\n" payload livelove--frame-terminator)
    (concat "\n" header livelove--frame-terminator)))

(defun livelove--send (client frame)
  "Send FRAME to CLIENT, dropping the client on failure."
  (if (process-live-p client)
      (condition-case err
          (process-send-string client frame)
        (error
         (livelove--log 'warning "Send to %s failed: %s"
                        (process-name client) (error-message-string err))
         (setq livelove--clients (delq client livelove--clients))))
    (setq livelove--clients (delq client livelove--clients))))

(defun livelove--prune-clients ()
  "Drop client processes that are no longer live."
  (setq livelove--clients (seq-filter #'process-live-p livelove--clients)))

(defun livelove--broadcast (frame)
  "Send FRAME to every live client."
  (livelove--prune-clients)
  (dolist (client livelove--clients)
    (livelove--send client frame)))

;; ===============================================================
;;; Connection lifecycle

(defun livelove--on-connect (_server client _message)
  "Register CLIENT when the server accepts a new connection."
  (process-put client 'livelove--buffer "")
  (set-process-query-on-exit-flag client nil)
  (push client livelove--clients)
  (livelove--log 'info "Client connected: %s" (process-name client))
  (run-hook-with-args 'livelove-connect-functions client))

(defun livelove--sentinel (proc _event)
  "Keep client and server state consistent as PROC changes state."
  (when (memq (process-status proc) '(closed failed exit signal))
    (if (eq proc livelove--server)
        (progn
          (setq livelove--server nil)
          (livelove--prune-clients)
          (livelove--log 'warning "Server stopped unexpectedly"))
      (setq livelove--clients (delq proc livelove--clients))
      (livelove--log 'info "Client disconnected: %s" (process-name proc)))))

;; ===============================================================
;;; Server lifecycle

(defun livelove--make-server ()
  "Create and return the livelove server process.
Client connections inherit the filter, sentinel and coding system."
  (make-network-process
   :name "livelove-server"
   :server t
   :host livelove-host
   :service livelove-port
   :family 'ipv4
   :coding 'utf-8-unix
   :noquery t
   :filter #'livelove--client-filter
   :sentinel #'livelove--sentinel
   :log #'livelove--on-connect))

;;;###autoload
(defun livelove-start-server ()
  "Start the livelove TCP server unless it is already running."
  (interactive)
  (if (process-live-p livelove--server)
      (livelove--log 'info "Server already running on %s:%d"
                     livelove-host livelove-port)
    (condition-case err
        (progn
          (setq livelove--clients nil
                livelove--server (livelove--make-server))
          (add-hook 'kill-emacs-hook #'livelove-stop-server)
          (livelove--log 'info "Server listening on %s:%d"
                         livelove-host livelove-port))
      (file-error
       (setq livelove--server nil)
       (livelove--log 'error "Cannot start server: %s"
                      (error-message-string err))
       (user-error
        "livelove: Cannot bind %s:%d (another instance already listening?)"
        livelove-host livelove-port)))))

(defun livelove-stop-server ()
  "Stop the livelove server and disconnect all clients."
  (interactive)
  (remove-hook 'kill-emacs-hook #'livelove-stop-server)
  (dolist (client livelove--clients)
    (when (process-live-p client)
      (delete-process client)))
  (setq livelove--clients nil)
  (when (process-live-p livelove--server)
    (set-process-sentinel livelove--server #'ignore)
    (delete-process livelove--server))
  (setq livelove--server nil)
  (livelove--log 'info "Server stopped"))

(defun livelove-status ()
  "Report the server state, connected clients and tracked buffers."
  (interactive)
  (livelove--prune-clients)
  (if (process-live-p livelove--server)
      (message "livelove: listening on %s:%d, %d client(s), %d buffer(s) tracked"
               livelove-host livelove-port
               (length livelove--clients) (length livelove--managed-buffers))
    (message "livelove: server not running (%d buffer(s) tracked)"
             (length livelove--managed-buffers))))

;; ===============================================================
;;; Live coding: push source for hot reload

(defcustom livelove-update-delay 0.05
  "Seconds to wait after an edit before pushing source to the game.
Edits arriving within this window are coalesced into one FILE_UPDATE."
  :type 'number)

(defun livelove--buffer-uri (buffer)
  "Return the livelove identifier for BUFFER, or nil if it has no file.
The game echoes this string back verbatim, so it must be stable."
  (buffer-file-name buffer))

(defun livelove--buffer-text (buffer)
  "Return the entire contents of BUFFER without text properties."
  (with-current-buffer buffer
    (buffer-substring-no-properties (point-min) (point-max))))

(defun livelove--file-update-frame (buffer)
  "Return the FILE_UPDATE frame for BUFFER, or nil when it has no file."
  (when-let* ((uri (livelove--buffer-uri buffer)))
    (livelove--frame (concat "FILE_UPDATE:" uri)
                     (livelove--buffer-text buffer))))

(defun livelove--send-file-update (buffer)
  "Broadcast BUFFER's current source to every connected game."
  (when (and livelove--clients (buffer-live-p buffer))
    (when-let* ((frame (livelove--file-update-frame buffer)))
      (livelove--broadcast frame)
      (livelove--log 'debug "Sent FILE_UPDATE for %s" (livelove--buffer-uri buffer)))))

(defun livelove--send-all-files (client)
  "Send every managed buffer's source to CLIENT."
  (dolist (buffer livelove--managed-buffers)
    (when (buffer-live-p buffer)
      (when-let* ((frame (livelove--file-update-frame buffer)))
        (livelove--send client frame)))))

(defun livelove--flush-dirty ()
  "Send a FILE_UPDATE for every dirty managed buffer and refresh overlays."
  (setq livelove--flush-timer nil)
  (let ((buffers livelove--dirty-buffers))
    (setq livelove--dirty-buffers nil)
    (dolist (buffer buffers)
      (when (memq buffer livelove--managed-buffers)
        (livelove--send-file-update buffer)
        (livelove--render buffer)))))

(defun livelove--schedule-flush (buffer)
  "Mark BUFFER dirty and re-arm the debounce timer."
  (unless (memq buffer livelove--dirty-buffers)
    (push buffer livelove--dirty-buffers))
  (when (timerp livelove--flush-timer)
    (cancel-timer livelove--flush-timer))
  (setq livelove--flush-timer
        (run-with-timer livelove-update-delay nil #'livelove--flush-dirty)))

(defun livelove--after-change (_beg _end _len)
  "Buffer-local `after-change-functions' entry.
Mark overlay positions stale and schedule a source push."
  (setq livelove--dirty-positions t)
  (when livelove--clients
    (livelove--schedule-flush (current-buffer))))

(defun livelove--register (buffer)
  "Start tracking BUFFER: install the change hook and push its source."
  (with-current-buffer buffer
    (unless (memq buffer livelove--managed-buffers)
      (push buffer livelove--managed-buffers)
      (add-hook 'after-change-functions #'livelove--after-change nil t)
      (add-hook 'kill-buffer-hook #'livelove--on-kill-buffer nil t)
      (livelove--log 'info "Tracking %s" (buffer-file-name))))
  (livelove--send-file-update buffer))

(defun livelove--deregister (buffer)
  "Stop tracking BUFFER and clear its overlays and cached values."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (remove-hook 'after-change-functions #'livelove--after-change t)
      (remove-hook 'kill-buffer-hook #'livelove--on-kill-buffer t)
      (livelove--clear-overlays)
      (setq livelove--values nil
            livelove--label-widths nil
            livelove--dirty-positions t)))
  (setq livelove--managed-buffers (delq buffer livelove--managed-buffers)
        livelove--dirty-buffers (delq buffer livelove--dirty-buffers))
  (livelove--log 'info "Untracking %s" (buffer-name buffer)))

(add-hook 'livelove-connect-functions #'livelove--send-all-files)

;; ===============================================================
;;; Live feedback: render reported values as overlays

(defface livelove-value-face '((t :inherit shadow))
  "Face for live variable values shown next to their names.")

(defcustom livelove-align-values 'decimal
  "How to pad live value overlays to reduce width jitter.
nil shows each value as reported.  `decimal' aligns numeric values on the
decimal point, padding to the widest integer and fractional parts seen and
leaving non-numeric values unpadded."
  :type '(choice (const :tag "Off" nil)
                 (const :tag "Align on the decimal point" decimal)))

(defcustom livelove-align-max-width nil
  "Maximum columns reserved per side when aligning values, or nil for no cap.
Caps padding so a one-off huge value cannot inflate every later value's width;
values wider than the cap are still shown in full."
  :type '(choice (const :tag "No cap" nil) natnum))

(defconst livelove--number-regexp "\\`-?[0-9]+\\(\\.[0-9]+\\)?\\'"
  "Values matching this (integers and fixed-point decimals) are aligned.")

(defun livelove--clear-overlays ()
  "Delete every livelove value overlay in the current buffer."
  (when (hash-table-p livelove--overlays)
    (maphash (lambda (_name overlays) (mapc #'delete-overlay overlays))
             livelove--overlays)
    (clrhash livelove--overlays)))

(defun livelove--align-decimal (name value)
  "Pad numeric VALUE of variable NAME to the widest width seen for NAME.
Integers reserve the fractional columns with spaces so the decimal column
stays aligned; `livelove-align-max-width' caps the reserved columns."
  (unless (hash-table-p livelove--label-widths)
    (setq livelove--label-widths (make-hash-table :test 'equal)))
  (let* ((dot (string-search "." value))
         (left (if dot (substring value 0 dot) value))
         (right (if dot (substring value (1+ dot)) ""))
         (seen (gethash name livelove--label-widths '(0 . 0)))
         (max-left (max (car seen) (length left)))
         (max-right (max (cdr seen) (length right)))
         (cap livelove-align-max-width)
         (pad-left (if cap (min max-left cap) max-left))
         (pad-right (if cap (min max-right cap) max-right)))
    (puthash name (cons max-left max-right) livelove--label-widths)
    (if (> max-right 0)
        (concat (string-pad left pad-left nil t)
                (if dot "." " ")
                (string-pad right pad-right))
      (string-pad left pad-left nil t))))

(defun livelove--display-value (name value)
  "Return the string to display for VALUE of variable NAME."
  (if (and (eq livelove-align-values 'decimal)
           (string-match-p livelove--number-regexp value))
      (livelove--align-decimal name value)
    value))

(defun livelove--set-label (overlay label)
  "Set OVERLAY's displayed text to LABEL, padded on the left."
  (let ((text (propertize (concat " " label) 'face 'livelove-value-face)))
    (put-text-property 0 1 'cursor 1 text)
    (overlay-put overlay 'after-string text)))

(defun livelove--make-overlay (pos label)
  "Return a value overlay showing LABEL just after POS.
The overlay is anchored to the character before POS so it evaporates
automatically when that text is deleted."
  (let ((overlay (make-overlay (1- pos) pos)))
    (overlay-put overlay 'evaporate t)
    (overlay-put overlay 'livelove t)
    (livelove--set-label overlay label)
    overlay))

(defun livelove--scan-name (name value)
  "Create and return overlays for every occurrence of NAME showing VALUE."
  (let ((label (livelove--display-value name value))
        (regexp (concat "\\_<" (regexp-quote name) "\\_>"))
        (overlays nil))
    (goto-char (point-min))
    (while (re-search-forward regexp nil t)
      (push (livelove--make-overlay (match-end 0) label) overlays))
    overlays))

(defun livelove--render-full ()
  "Rebuild every overlay by scanning the buffer for known variables."
  (livelove--clear-overlays)
  (maphash (lambda (name value)
             (puthash name (livelove--scan-name name value) livelove--overlays))
           livelove--values)
  (setq livelove--dirty-positions nil))

(defun livelove--render-values ()
  "Update existing overlays in place; scan only newly seen variables."
  (maphash (lambda (name value)
             (if-let* ((overlays (gethash name livelove--overlays)))
                 (let ((label (livelove--display-value name value)))
                   (dolist (overlay overlays)
                     (livelove--set-label overlay label)))
               (puthash name (livelove--scan-name name value) livelove--overlays)))
           livelove--values))

(defun livelove--render (buffer)
  "Refresh value overlays for BUFFER.
Rescan positions only when the text changed; otherwise update the
existing overlays' labels in place."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (unless (hash-table-p livelove--overlays)
        (setq livelove--overlays (make-hash-table :test 'equal)))
      (when (hash-table-p livelove--values)
        (save-excursion
          (without-restriction
            (if livelove--dirty-positions
                (livelove--render-full)
              (livelove--render-values))))))))

(defun livelove--buffer-for-uri (uri)
  "Return the managed buffer whose identifier is URI, or nil."
  (seq-find (lambda (buffer)
              (and (buffer-live-p buffer)
                   (equal (livelove--buffer-uri buffer) uri)))
            livelove--managed-buffers))

(defun livelove--merge-values (buffer updates)
  "Merge the variables carried by UPDATES into BUFFER's value table."
  (with-current-buffer buffer
    (unless (hash-table-p livelove--values)
      (setq livelove--values (make-hash-table :test 'equal)))
    (dolist (update updates)
      (pcase-dolist (`(,name . ,value) (alist-get 'variables update))
        (puthash (symbol-name name) value livelove--values)))))

(defun livelove--handle-vars-update (payload)
  "Merge the VARS_UPDATE PAYLOAD and refresh the target buffer's overlays."
  (when payload
    (condition-case err
        (let* ((data (json-parse-string payload
                                        :object-type 'alist :array-type 'list))
               (buffer (livelove--buffer-for-uri (alist-get 'uri data))))
          (when buffer
            (livelove--merge-values buffer (alist-get 'updates data))
            (livelove--render buffer)))
      (error
       (livelove--log 'warning "Bad VARS_UPDATE: %s" (error-message-string err))))))

(defun livelove--on-frame (header payload _client)
  "Render a VARS_UPDATE frame's PAYLOAD; ignore frames with any other HEADER."
  (when (equal header "VARS_UPDATE")
    (livelove--handle-vars-update payload)))

(add-hook 'livelove-frame-functions #'livelove--on-frame)

;; ===============================================================
;;; Live eval (REPL)

(defvar livelove--eval-history nil
  "Minibuffer history for `livelove-eval-expression'.")

(defun livelove--send-eval (code)
  "Send CODE to the running game for evaluation."
  (livelove--prune-clients)
  (unless livelove--clients
    (user-error "livelove: No game connected"))
  (livelove--broadcast (livelove--frame "EVAL" code))
  (livelove--log 'debug "Sent EVAL: %s" code))

;;;###autoload
(defun livelove-eval-expression (code)
  "Evaluate the Lua CODE in the running game.
CODE is a Lua expression or statement, read from the minibuffer; the
result appears in the echo area once the game replies."
  (interactive (list (read-string "LÖVE eval: " nil 'livelove--eval-history)))
  (unless (string-blank-p code)
    (livelove--send-eval code)))

;;;###autoload
(defun livelove-eval-region (beg end)
  "Evaluate the region between BEG and END in the running game."
  (interactive "r")
  (livelove--send-eval (buffer-substring-no-properties beg end)))

;;;###autoload
(defun livelove-eval-line ()
  "Evaluate the current line in the running game."
  (interactive)
  (let ((code (string-trim (thing-at-point 'line t))))
    (unless (string-blank-p code)
      (livelove--send-eval code))))

(defun livelove--handle-eval-result (payload)
  "Show the EVAL_RESULT carried by PAYLOAD in the echo area."
  (when payload
    (condition-case err
        (let ((data (json-parse-string payload :object-type 'alist)))
          (if-let* ((errmsg (alist-get 'error data)))
              (message "livelove eval error: %s" errmsg)
            (message "livelove → %s" (alist-get 'value data))))
      (error
       (livelove--log 'warning "Bad EVAL_RESULT: %s" (error-message-string err))))))

(defun livelove--on-eval-result (header payload _client)
  "Show an EVAL_RESULT frame's PAYLOAD; ignore frames with any other HEADER."
  (when (equal header "EVAL_RESULT")
    (livelove--handle-eval-result payload)))

(add-hook 'livelove-frame-functions #'livelove--on-eval-result)

;; ===============================================================
;;; Minor mode and project integration

(defcustom livelove-auto-start-server t
  "When non-nil, `livelove-mode' starts and stops the server automatically.
The server starts on first enable and stops when the last buffer is untracked."
  :type 'boolean)

(defcustom livelove-lua-modes '(lua-ts-mode lua-mode)
  "Major modes treated as Lua buffers by `global-livelove-mode'."
  :type '(repeat symbol))

(defcustom livelove-project-marker "main.lua"
  "File whose presence marks the root of a LÖVE project.
Used by `global-livelove-mode' to decide where to enable."
  :type 'string)

(define-minor-mode livelove-mode
  "Live coding for a LÖVE 2D buffer.
Push this buffer's source to the running game for hot reload, and show the
values it reports as overlays.  See `global-livelove-mode' to enable this
across a project automatically."
  :lighter " LL"
  (if livelove-mode
      (if (buffer-file-name)
          (progn
            (when (and livelove-auto-start-server
                       (not (process-live-p livelove--server)))
              (livelove-start-server))
            (livelove--register (current-buffer)))
        (setq livelove-mode nil)
        (user-error "livelove: Buffer has no file"))
    (livelove--deregister (current-buffer))
    (when (and livelove-auto-start-server
               (null livelove--managed-buffers)
               (process-live-p livelove--server))
      (livelove-stop-server))))

(defun livelove--on-kill-buffer ()
  "Turn off `livelove-mode' when a tracked buffer is killed."
  (when livelove-mode
    (livelove-mode -1)))

(defun livelove--love-project-root (&optional dir)
  "Return the LÖVE project root at or above DIR, or nil."
  (locate-dominating-file (or dir default-directory) livelove-project-marker))

(defun livelove--maybe-enable ()
  "Enable `livelove-mode' in a Lua buffer that belongs to a LÖVE project."
  (when (and buffer-file-name
             (derived-mode-p livelove-lua-modes)
             (livelove--love-project-root))
    (livelove-mode 1)))

;;;###autoload
(define-globalized-minor-mode global-livelove-mode
  livelove-mode livelove--maybe-enable
  :group 'livelove)

;;;###autoload
(defun livelove-track-buffer ()
  "Turn on `livelove-mode' in the current buffer."
  (interactive)
  (livelove-mode 1))

(defun livelove-untrack-buffer ()
  "Turn off `livelove-mode' in the current buffer."
  (interactive)
  (livelove-mode -1))

;; ===============================================================
;;; Running the game

(defcustom livelove-love-command "love"
  "Executable used to launch the LÖVE runtime."
  :type 'string)

(defcustom livelove-link-support-files t
  "When non-nil, `livelove-run' links the Lua support files into the project.
The canonical files ship in `livelove-support-dir', symlinks are placed in the
project root so the game can `require' them."
  :type 'boolean)

(defcustom livelove-support-dir
  (expand-file-name "lua/"
                    (file-name-directory
                     (or load-file-name buffer-file-name default-directory)))
  "Directory holding the Lua files the game needs at runtime.
Defaults to the `lua/' directory shipped alongside this package."
  :type 'directory)

(defconst livelove--support-files
  '("livelove.lua" "MessageProcessor.lua" "instrumenter.lua")
  "Lua support files linked into a project by `livelove-run'.")

(defun livelove--ensure-support-files (project-dir)
  "Link the Lua support files into PROJECT-DIR from `livelove-support-dir'.
A real file or a good symlink already there is left alone; only a broken
symlink is replaced.  Falls back to copying when a symlink cannot be made."
  (dolist (file livelove--support-files)
    (let ((target (expand-file-name file livelove-support-dir))
          (link (expand-file-name file project-dir)))
      (cond
       ((not (file-exists-p target))
        (livelove--log 'warning "Support file missing from package: %s" target))
       ((file-exists-p link) nil) ; real file or working link: leave it
       (t
        (when (file-symlink-p link) ; dangling link: clear it first
          (delete-file link))
        (condition-case err
            (make-symbolic-link target link)
          (error
           (livelove--log 'warning "Symlink failed (%s); copying instead"
                          (error-message-string err))
           (copy-file target link)))
        (livelove--log 'info "Linked support file %s" file))))))

(defvar livelove--game-process nil
  "The LÖVE process launched by `livelove-run', or nil.")

(defun livelove--game-sentinel (proc _event)
  "Clear `livelove--game-process' once PROC has exited."
  (unless (process-live-p proc)
    (setq livelove--game-process nil)
    (livelove--log 'info "Game exited")))

;;;###autoload
(defun livelove-run ()
  "Launch the LÖVE game for the current project.
Starts the livelove server first so the game can connect, then runs
the runtime in the project root with output in the *love* buffer."
  (interactive)
  (when (process-live-p livelove--game-process)
    (user-error "livelove: a game is already running (use `livelove-stop')"))
  (unless (executable-find livelove-love-command)
    (user-error "livelove: %s not found in PATH" livelove-love-command))
  (let ((default-directory (or (livelove--love-project-root)
                               (user-error "livelove: Not inside a LÖVE project"))))
    (when livelove-link-support-files
      (livelove--ensure-support-files default-directory))
    (unless (process-live-p livelove--server)
      (livelove-start-server))
    (setq livelove--game-process
          (make-process :name "love"
                        :buffer "*love*"
                        :command (list livelove-love-command ".")
                        :noquery t
                        :sentinel #'livelove--game-sentinel))
    (livelove--log 'info "Launched %s in %s" livelove-love-command default-directory)))

;;;###autoload
(defun livelove-stop ()
  "Stop the LÖVE game started by `livelove-run'."
  (interactive)
  (if (process-live-p livelove--game-process)
      (progn
        (delete-process livelove--game-process)
        (livelove--log 'info "Stopped the game"))
    (message "livelove: no game running"))
  (setq livelove--game-process nil))

(provide 'livelove)
;;; livelove.el ends here
