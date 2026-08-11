;;; livelove.el --- Live coding bridge for LÖVE 2D  -*- lexical-binding: t; -*-

;; Author: Lucas
;; Version: 0.1
;; Package-Requires: ((emacs "30.1"))
;; Keywords: games, tools

;;; Commentary:
;;
;; Live-coding bridge for LÖVE.  It runs a small TCP server that a running
;; game connects to, and over that link it offers:
;;
;; - Hot reload: editing a tracked Lua buffer pushes its source to the game,
;;   which swaps it in without a restart.
;; - Live feedback: the latest value of each variable is shown inline next to
;;   the variable, and gathered in the `*livelove-values*' panel.
;; - A REPL: evaluate a Lua expression, the region, or the current line in the
;;   running game and read the result in the echo area.
;; - Asset hot reload: text assets such as shaders are watched on disk and
;;   pushed to the game as they change.
;; - Game control: reset the graphics state, restart the game, or toggle the
;;   live-feedback instrumentation on the fly.
;;
;; Setup:
;;
;; Turn on `global-livelove-mode' to enable livelove automatically in the Lua
;; buffers of a LÖVE project (any directory holding a `main.lua'), or enable it
;; with `M-x livelove-mode'. Launch the game with `M-x livelove-run', which
;; starts the server first so the game can connect. `livelove-run' symlinks
;; the Lua support files into the project from `livelove-support-dir'. Set
;; `livelove-link-support-files' to nil to manage them yourself.
;;
;; On the game side, `main.lua' needs the livelove boilerplate. A minimal
;; `main.lua' looks like this:
;;
;;     local livelove = require("livelove")
;;
;;     function love.update(dt)
;;       livelove.instantupdate()
;;     end
;;
;;     function love.draw()
;;       livelove.postdraw()
;;     end
;;
;; Commands:
;;
;; - `livelove-run', `livelove-stop' and `livelove-restart' drive the game, and
;;   `livelove-reset' clears its graphics state without a restart.
;; - `livelove-eval-expression', `livelove-eval-region' and `livelove-eval-line'
;;   evaluate Lua in the running game.
;; - `livelove-values' opens the live values panel, `livelove-toggle-hints'
;;   hides or shows the inline overlays, and `livelove-toggle-live-vars' turns
;;   live-feedback reporting on or off.
;; - `livelove-status' and `livelove-show-log' inspect the server and its log.
;;
;; By default the inline overlays annotate every occurrence of a variable in
;; the buffer. In a large file that gets noisy, so `livelove-hints-scope' can
;; narrow them to the current line (`line') or the enclosing function (`defun')
;; rather than the whole buffer (`buffer').
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
The LÖVE client hard-codes 12345, so change it only if you patch the game too."
  :type 'natnum)

(defcustom livelove-log-level 'info
  "Minimum severity recorded in the livelove log buffer.
Set to nil to disable logging entirely."
  :type '(choice (const :tag "Debug"    debug)
                 (const :tag "Info"     info)
                 (const :tag "Warning"  warning)
                 (const :tag "Error"    error)
                 (const :tag "Disabled" nil)))

;;;; Protocol constants and state

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

(defvar livelove--live-vars t
  "Non-nil when the game should report live variable values.
It mirrors the game's live_vars flag and resets to t when a game launches.")

(defvar livelove-connect-functions nil
  "Abnormal hook run when a game connects, called with the client process.")

(defvar livelove-frame-functions nil
  "Abnormal hook run for each received frame, with (HEADER PAYLOAD CLIENT).
HEADER is the frame's first line, PAYLOAD the rest (or nil), CLIENT the process.")

(defvar livelove-values-updated-hook nil
  "Normal hook run after `livelove--values' changes for any managed buffer.")

(defvar-local livelove--values nil
  "Hash table mapping a variable name to its latest value string.")

(defvar-local livelove--overlays nil
  "Hash table mapping a variable name to its list of value overlays.")

(defvar-local livelove--dirty-positions t
  "Non-nil when overlay positions may be stale after a buffer change.")

(defvar-local livelove--label-widths nil
  "Hash table mapping a variable name to the widest (MAX-LEFT . MAX-RIGHT)
value widths seen, which keeps numeric overlays from jittering.")

(defvar-local livelove--hint-region nil
  "The (BEG . END) region overlays currently cover, or nil for the whole buffer.
Used to re-render only when the scoped region changes.")

;;;; Logging

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

;;;; Incoming frames

(defun livelove--dispatch-frame (raw client)
  "Dispatch a single protocol frame RAW received from CLIENT.
RAW still has its surrounding newlines, which are trimmed here."
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

;;;; Outgoing frames

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

;;;; Connection lifecycle

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
      (livelove--log 'info "Client disconnected: %s" (process-name proc))
      (unless livelove--clients
        (livelove--clear-all-feedback)))))

;;;; Server lifecycle

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

;;;; Live coding: push source for hot reload

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
  "Mark overlay positions stale and schedule a source push after an edit."
  (setq livelove--dirty-positions t)
  (when livelove--clients
    (livelove--schedule-flush (current-buffer))))

(defun livelove--register (buffer)
  "Start tracking BUFFER, installing its local hooks and pushing its source."
  (with-current-buffer buffer
    (unless (memq buffer livelove--managed-buffers)
      (push buffer livelove--managed-buffers)
      (add-hook 'after-change-functions #'livelove--after-change nil t)
      (add-hook 'kill-buffer-hook #'livelove--on-kill-buffer nil t)
      (add-hook 'post-command-hook #'livelove--hints-post-command nil t)
      (livelove--log 'info "Tracking %s" (buffer-file-name))))
  (livelove--send-file-update buffer))

(defun livelove--deregister (buffer)
  "Stop tracking BUFFER and clear its overlays and cached values."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (remove-hook 'after-change-functions #'livelove--after-change t)
      (remove-hook 'kill-buffer-hook #'livelove--on-kill-buffer t)
      (remove-hook 'post-command-hook #'livelove--hints-post-command t))
    (livelove--clear-feedback buffer))
  (setq livelove--managed-buffers (delq buffer livelove--managed-buffers)
        livelove--dirty-buffers (delq buffer livelove--dirty-buffers))
  (livelove--log 'info "Untracking %s" (buffer-name buffer)))

(add-hook 'livelove-connect-functions #'livelove--send-all-files)

;;;; Live feedback: render reported values as overlays

(defface livelove-value-face '((t :inherit shadow))
  "Face for live variable values shown next to their names.")

(defcustom livelove-show-hints t
  "When non-nil, show live values as inline overlays.
Hiding them with `livelove-toggle-hints' keeps value reporting on."
  :type 'boolean)

(defcustom livelove-hints-scope 'buffer
  "Where inline value overlays are shown, to reduce clutter in large files.
Either `buffer', `line' (at point), or `defun' (the enclosing function)."
  :type '(choice (const :tag "Whole buffer" buffer)
                 (const :tag "Current line" line)
                 (const :tag "Current defun" defun)))

(defcustom livelove-align-values 'decimal
  "How to pad live value overlays to reduce width jitter.
With `decimal' numeric values align on the decimal point, nil shows them as-is."
  :type '(choice (const :tag "Off" nil)
                 (const :tag "Align on the decimal point" decimal)))

(defcustom livelove-align-max-width nil
  "Maximum columns reserved per side when aligning values, or nil for no cap.
Values wider than the cap are still shown in full."
  :type '(choice (const :tag "No cap" nil) natnum))

(defconst livelove--number-regexp "\\`-?[0-9]+\\(\\.[0-9]+\\)?\\'"
  "Values matching this (integers and fixed-point decimals) are aligned.")

(defun livelove--clear-overlays ()
  "Delete every livelove value overlay in the current buffer."
  (when (hash-table-p livelove--overlays)
    (maphash (lambda (_name overlays) (mapc #'delete-overlay overlays))
             livelove--overlays)
    (clrhash livelove--overlays)))

(defcustom livelove-keep-values-on-disconnect nil
  "When non-nil, keep value overlays after the game disconnects.
By default they are cleared once the last game disconnects."
  :type 'boolean)

(defun livelove--clear-feedback (buffer)
  "Delete BUFFER's value overlays and drop its cached values."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (livelove--clear-overlays)
      (setq livelove--values nil
            livelove--label-widths nil
            livelove--dirty-positions t))))

(defun livelove--clear-all-feedback ()
  "Clear value overlays and cached values in every managed buffer.
Does nothing when `livelove-keep-values-on-disconnect' is non-nil."
  (unless livelove-keep-values-on-disconnect
    (dolist (buffer livelove--managed-buffers)
      (livelove--clear-feedback buffer))
    (run-hooks 'livelove-values-updated-hook)))

(defun livelove--align-decimal (name value)
  "Pad numeric VALUE of variable NAME to the widest width seen for NAME.
Integers reserve the fractional columns so the decimal point stays aligned."
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
Anchored to the character before POS, it evaporates when that text is deleted."
  (let ((overlay (make-overlay (1- pos) pos)))
    (overlay-put overlay 'evaporate t)
    (overlay-put overlay 'livelove t)
    (livelove--set-label overlay label)
    overlay))

(defun livelove--scan-name (name value beg end)
  "Return overlays for each occurrence of NAME between BEG and END showing VALUE."
  (let ((label (livelove--display-value name value))
        (regexp (concat "\\_<" (regexp-quote name) "\\_>"))
        (overlays nil))
    (goto-char beg)
    (while (re-search-forward regexp end t)
      (push (livelove--make-overlay (match-end 0) label) overlays))
    overlays))

(defun livelove--scope-bounds ()
  "Return the region hints should cover per `livelove-hints-scope'.
The result is a (BEG . END) cons, or nil for the whole buffer."
  (pcase livelove-hints-scope
    ('line (cons (line-beginning-position) (line-end-position)))
    ('defun (bounds-of-thing-at-point 'defun))
    (_ nil)))

(defun livelove--render-full (region)
  "Rebuild every overlay by scanning REGION for known variables.
REGION is a (BEG . END) cons, or nil for the whole buffer."
  (livelove--clear-overlays)
  (let ((beg (or (car region) (point-min)))
        (end (or (cdr region) (point-max))))
    (maphash (lambda (name value)
               (puthash name (livelove--scan-name name value beg end)
                        livelove--overlays))
             livelove--values))
  (setq livelove--dirty-positions nil
        livelove--hint-region region))

(defun livelove--render-values (region)
  "Update existing overlays in place, scanning REGION for new variables.
REGION is a (BEG . END) cons, or nil for the whole buffer."
  (let ((beg (or (car region) (point-min)))
        (end (or (cdr region) (point-max))))
    (maphash (lambda (name value)
               (if-let* ((overlays (gethash name livelove--overlays)))
                   (let ((label (livelove--display-value name value)))
                     (dolist (overlay overlays)
                       (livelove--set-label overlay label)))
                 (puthash name (livelove--scan-name name value beg end)
                          livelove--overlays)))
             livelove--values)))

(defun livelove--render (buffer)
  "Refresh value overlays for BUFFER, unless `livelove-show-hints' is nil.
Rescan positions after a text change, otherwise update labels in place."
  (when (and (buffer-live-p buffer) livelove-show-hints)
    (with-current-buffer buffer
      (unless (hash-table-p livelove--overlays)
        (setq livelove--overlays (make-hash-table :test 'equal)))
      (when (hash-table-p livelove--values)
        (save-match-data
          (save-excursion
            (without-restriction
              (let ((region (livelove--scope-bounds)))
                (if livelove--dirty-positions
                    (livelove--render-full region)
                  (livelove--render-values region))))))))))

(defun livelove--rescope (buffer)
  "Re-render BUFFER's hints when the scoped region changes.
Only acts for the `line' and `defun' scopes while hints are shown."
  (when (and (buffer-live-p buffer) livelove-show-hints
             (memq livelove-hints-scope '(line defun)))
    (with-current-buffer buffer
      (when (hash-table-p livelove--values)
        (let ((region (save-excursion
                        (without-restriction (livelove--scope-bounds)))))
          (unless (equal region livelove--hint-region)
            (setq livelove--dirty-positions t)
            (livelove--render buffer)))))))

(defun livelove--hints-post-command ()
  "Re-render scoped hints for the current buffer after point moves."
  (livelove--rescope (current-buffer)))

;;;###autoload
(defun livelove-toggle-hints ()
  "Toggle the inline value overlays across every tracked buffer.
Hiding the hints clears the overlays but keeps value reporting on."
  (interactive)
  (setq livelove-show-hints (not livelove-show-hints))
  (dolist (buffer livelove--managed-buffers)
    (when (buffer-live-p buffer)
      (with-current-buffer buffer
        (if livelove-show-hints
            (progn (setq livelove--dirty-positions t)
                   (livelove--render buffer))
          (livelove--clear-overlays)))))
  (message "livelove: hints %s" (if livelove-show-hints "on" "off")))

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
            (livelove--render buffer)
            (run-hooks 'livelove-values-updated-hook)))
      (error
       (livelove--log 'warning "Bad VARS_UPDATE: %s" (error-message-string err))))))

(defun livelove--on-frame (header payload _client)
  "Render a VARS_UPDATE frame's PAYLOAD, ignoring any other HEADER."
  (when (equal header "VARS_UPDATE")
    (livelove--handle-vars-update payload)))

(add-hook 'livelove-frame-functions #'livelove--on-frame)

;;;; Live eval (REPL)

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
Read CODE from the minibuffer and show the result in the echo area."
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
  "Show an EVAL_RESULT frame's PAYLOAD, ignoring any other HEADER."
  (when (equal header "EVAL_RESULT")
    (livelove--handle-eval-result payload)))

(add-hook 'livelove-frame-functions #'livelove--on-eval-result)

;;;; Values panel

(defconst livelove--values-buffer-name "*livelove-values*"
  "Name of the buffer showing live variable values.")

(defun livelove--values-group-name (buffer)
  "Return the values-panel group label for BUFFER.
Uses the file name relative to the LÖVE project root when available."
  (let ((file (buffer-file-name buffer)))
    (if file
        (let ((root (with-current-buffer buffer (livelove--love-project-root))))
          (if root (file-relative-name file root) (file-name-nondirectory file)))
      (buffer-name buffer))))

(defun livelove--values-cell (value)
  "Return VALUE as a single-line string safe for a tabulated-list cell."
  (let ((text (if (stringp value) value (format "%s" value))))
    (replace-regexp-in-string "\n" " " text)))

(defun livelove--values-groups ()
  "Return grouped panel rows aggregated over every managed buffer.
Each group is a source file whose rows are its variables sorted by name."
  (let ((groups nil))
    (dolist (buffer livelove--managed-buffers)
      (when (buffer-live-p buffer)
        (let ((values (buffer-local-value 'livelove--values buffer)))
          (when (hash-table-p values)
            (let ((name (livelove--values-group-name buffer))
                  (rows nil))
              (maphash
               (lambda (var value)
                 (push (list (cons buffer var)
                             (vector var (livelove--values-cell value)))
                       rows))
               values)
              (when rows
                (setq rows (sort rows (lambda (a b)
                                        (string< (aref (cadr a) 0)
                                                 (aref (cadr b) 0)))))
                (push (cons name rows) groups)))))))
    (nreverse groups)))

(define-derived-mode livelove-values-mode tabulated-list-mode "LL-Values"
  "Major mode for the live values panel.
Each row shows a tracked variable and its latest value, grouped by file."
  (setq tabulated-list-format [("Variable" 24 nil) ("Value" 0 nil)])
  (setq tabulated-list-groups #'livelove--values-groups)
  (setq tabulated-list-padding 1)
  (tabulated-list-init-header))

(defun livelove--values-refresh ()
  "Reprint the values panel from current state when it is live."
  (let ((buffer (get-buffer livelove--values-buffer-name)))
    (when (buffer-live-p buffer)
      (with-current-buffer buffer
        (tabulated-list-print t t)))))

(defun livelove--values-on-kill ()
  "Detach the panel from the update hook when its buffer is killed."
  (remove-hook 'livelove-values-updated-hook #'livelove--values-refresh))

;;;###autoload
(defun livelove-values ()
  "Display the live values panel and keep it updated.
Shows every tracked variable and its latest value, grouped by file."
  (interactive)
  (let ((buffer (get-buffer-create livelove--values-buffer-name)))
    (with-current-buffer buffer
      (unless (derived-mode-p 'livelove-values-mode)
        (livelove-values-mode)
        (add-hook 'livelove-values-updated-hook #'livelove--values-refresh)
        (add-hook 'kill-buffer-hook #'livelove--values-on-kill nil t))
      (tabulated-list-print))
    (pop-to-buffer buffer)))

;;;; Minor mode and project integration

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

;;;###autoload
(define-minor-mode livelove-mode
  "Live coding for a LÖVE 2D buffer.
Push its source to the game for hot reload and overlay the reported values.
See `global-livelove-mode' to enable this across a project automatically."
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

;;;; Asset hot reload

(declare-function file-notify-add-watch "filenotify")
(declare-function file-notify-rm-watch "filenotify")

(defcustom livelove-watch-assets t
  "When non-nil, `livelove-run' watches asset files and pushes changes.
Files whose extension is in `livelove-asset-extensions' are sent as
ASSET_FILE_UPDATE frames on change, so shaders reload without a restart."
  :type 'boolean)

(defcustom livelove-asset-extensions '("glsl" "frag" "vert" "vs" "fs")
  "File extensions treated as reloadable text assets.
Only text assets work, since images or audio would corrupt the stream."
  :type '(repeat string))

(defvar livelove--asset-watches nil
  "Active file-notify descriptors for watched asset directories.")

(defun livelove--asset-file-p (file)
  "Return non-nil when FILE's extension is in `livelove-asset-extensions'."
  (when-let* ((ext (file-name-extension file)))
    (member (downcase ext) livelove-asset-extensions)))

(defun livelove--asset-directories (root)
  "Return the directories under ROOT that hold reloadable asset files.
Hidden directories such as .git are skipped."
  (when livelove-asset-extensions
    (let ((regexp (concat "\\.\\(?:"
                          (mapconcat #'regexp-quote livelove-asset-extensions "\\|")
                          "\\)\\'")))
      (delete-dups
       (mapcar #'file-name-directory
               (directory-files-recursively
                root regexp nil
                (lambda (dir)
                  (not (string-prefix-p
                        "." (file-name-nondirectory (directory-file-name dir)))))))))))

(defun livelove--on-asset-change (event)
  "Send an ASSET_FILE_UPDATE for the file named in a file-notify EVENT."
  (pcase-let ((`(,_desc ,action ,file ,file1) (append event '(nil))))
    (let ((target (if (and (eq action 'renamed) file1) file1 file)))
      (when (and (memq action '(created changed renamed))
                 (stringp target)
                 (livelove--asset-file-p target)
                 (file-readable-p target))
        (livelove--broadcast
         (livelove--frame (concat "ASSET_FILE_UPDATE:" target)
                          (with-temp-buffer
                            (insert-file-contents target)
                            (buffer-string))))
        (livelove--log 'info "Sent ASSET_FILE_UPDATE for %s" target)))))

(defun livelove--watch-assets (root)
  "Watch every asset directory under ROOT for changes."
  (livelove--unwatch-assets)
  (require 'filenotify)
  (dolist (dir (livelove--asset-directories root))
    (condition-case err
        (push (file-notify-add-watch dir '(change) #'livelove--on-asset-change)
              livelove--asset-watches)
      (error
       (livelove--log 'warning "Cannot watch %s: %s"
                      dir (error-message-string err))))))

(defun livelove--unwatch-assets ()
  "Remove every active asset file-notify watch."
  (dolist (desc livelove--asset-watches)
    (file-notify-rm-watch desc))
  (setq livelove--asset-watches nil))

;;;; Running the game

(defcustom livelove-love-command "love"
  "Executable used to launch the LÖVE runtime."
  :type 'string)

(defcustom livelove-link-support-files t
  "When non-nil, `livelove-run' symlinks the Lua support files into the project.
They point at `livelove-support-dir' so the game can require them."
  :type 'boolean)

(defcustom livelove-support-dir
  (expand-file-name "lua/"
                    (file-name-directory
                     (or load-file-name buffer-file-name default-directory)))
  "Directory holding the Lua files the game needs at runtime.
Defaults to the `lua/' directory shipped alongside this package."
  :type 'directory)

(defconst livelove--support-files
  '("livelove.lua" "instrumenter.lua")
  "Lua support files linked into a project by `livelove-run'.")

(defun livelove--ensure-support-files (project-dir)
  "Link the Lua support files into PROJECT-DIR from `livelove-support-dir'.
Existing files and good symlinks are left alone, and copying is a fallback."
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
  "Clear `livelove--game-process' and asset watches once PROC has exited."
  (unless (process-live-p proc)
    (setq livelove--game-process nil)
    (livelove--unwatch-assets)
    (livelove--log 'info "Game exited")))

;;;###autoload
(defun livelove-run ()
  "Launch the LÖVE game for the current project.
Start the server first so the game can connect, then run it from the root."
  (interactive)
  (when (process-live-p livelove--game-process)
    (user-error "livelove: A game is already running (use `livelove-stop')"))
  (unless (executable-find livelove-love-command)
    (user-error "livelove: %s not found in PATH" livelove-love-command))
  (setq livelove--live-vars t)
  (let ((default-directory (or (livelove--love-project-root)
                               (user-error "livelove: Not inside a LÖVE project"))))
    (when livelove-link-support-files
      (livelove--ensure-support-files default-directory))
    (unless (process-live-p livelove--server)
      (livelove-start-server))
    (when livelove-watch-assets
      (livelove--watch-assets default-directory))
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

;;;; Game control

(defun livelove--send-control (command)
  "Broadcast a GAME_CONTROL COMMAND to every connected game."
  (livelove--prune-clients)
  (unless livelove--clients
    (user-error "livelove: No game connected"))
  (livelove--broadcast (livelove--frame "GAME_CONTROL" command))
  (livelove--log 'debug "Sent GAME_CONTROL: %s" command))

;;;###autoload
(defun livelove-reset ()
  "Reset the running game's graphics state (canvas, shader, transforms)."
  (interactive)
  (livelove--send-control "reset"))

;;;###autoload
(defun livelove-toggle-live-vars ()
  "Toggle live variable reporting in the running game.
Turning it off stops VARS_UPDATE traffic and the instrumentation overhead."
  (interactive)
  (setq livelove--live-vars (not livelove--live-vars))
  (livelove--send-control
   (if livelove--live-vars "live_vars_on" "live_vars_off"))
  (message "livelove: live vars %s" (if livelove--live-vars "on" "off")))

;;;###autoload
(defun livelove-restart ()
  "Restart the LÖVE game: stop it and run it again."
  (interactive)
  (livelove-stop)
  (livelove-run))

(provide 'livelove)
;;; livelove.el ends here
