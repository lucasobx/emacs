;;; dired-snacks.el --- Dired utilities  -*- lexical-binding: t; -*-
;;; Commentary:
;;; Code:

;; ===============================================================
;;; zoxide-dired

(declare-function completion-preview-mode "completion-preview")
(defvar completion-preview-minimum-symbol-length)
(defvar completion-preview-completion-styles)
(defvar completion-preview-inhibit-functions)
(defvar completion-preview-overlay-priority)
(defvar completion-preview-idle-delay)

(defvar my/zoxide--ghost-ov nil
  "Overlay showing the best zoxide match in the minibuffer.")

(defun my/zoxide--query (input)
  "Return the directory for INPUT: a literal path, else zoxide's best match."
  (when (and input (not (string-empty-p input)))
    (let ((expanded (expand-file-name input)))
      (if (and (string-match-p "[/~]" input) (file-directory-p expanded))
          expanded
        (when (executable-find "zoxide")
          (with-temp-buffer
            (when (zerop (call-process "zoxide" nil t nil "query" "--" input))
              (let ((dir (string-trim (buffer-string))))
                (and (file-directory-p dir) dir)))))))))

(defun my/zoxide--add (dir)
  "Register DIR in the zoxide database."
  (when (and dir (executable-find "zoxide"))
    (call-process "zoxide" nil 0 nil "add" "--" (expand-file-name dir))))

(defun my/zoxide--add-default-directory ()
  "Register `default-directory' in the zoxide database."
  (when (and (not (file-remote-p default-directory))
             (file-directory-p default-directory))
    (my/zoxide--add default-directory)))

(add-hook 'find-file-hook  #'my/zoxide--add-default-directory)
(add-hook 'dired-mode-hook #'my/zoxide--add-default-directory)

(defun my/zoxide--path-like-p (input)
  "Return non-nil if INPUT looks like a literal filesystem path."
  (and (string-match-p "[/~]" input) t))

(defun my/zoxide--update-ghost (&rest _)
  "Refresh the inline zoxide suggestion for fuzzy queries."
  (when (overlayp my/zoxide--ghost-ov)
    (delete-overlay my/zoxide--ghost-ov))
  (let ((input (minibuffer-contents)))
    (unless (my/zoxide--path-like-p input)
      (when-let* ((dir (my/zoxide--query input)))
        (setq my/zoxide--ghost-ov (make-overlay (point-max) (point-max) nil t t))
        (overlay-put my/zoxide--ghost-ov 'after-string
                     (propertize (concat "  → " (abbreviate-file-name dir))
                                 'face 'shadow 'cursor t))))))

(defun my/zoxide--path-capf ()
  "Completion-at-point function for filesystem paths.
Used by `completion-preview' for literal paths."
  (list (minibuffer-prompt-end) (point) #'completion-file-name-table))

(defun my/zoxide--inhibit-preview ()
  "Inhibit `completion-preview' unless the input looks like a literal path."
  (not (my/zoxide--path-like-p (minibuffer-contents))))

(defun my/zoxide-complete-path ()
  "Complete the minibuffer input as a directory path."
  (interactive)
  (let* ((beg (minibuffer-prompt-end))
         (input (buffer-substring-no-properties beg (point-max)))
         (expanded (expand-file-name input))
         (dir (file-name-directory expanded))
         (base (file-name-nondirectory expanded))
         (comp (and (file-directory-p dir)
                    (file-name-completion base dir #'file-directory-p))))
    (cond
     ((null comp) (minibuffer-message "No match"))
     ((eq comp t) (minibuffer-message "Sole completion"))
     ((string= comp base)
      (minibuffer-message
       "%s" (mapconcat #'identity
                       (seq-filter (lambda (f) (string-suffix-p "/" f))
                                   (file-name-all-completions base dir))
                       "  ")))
     (t
      (delete-region beg (point-max))
      (insert (concat (or (file-name-directory input) "") comp))))))

(defun my/zoxide-complete ()
  "Complete the minibuffer input. Literal paths use filename completion.
Fuzzy queries expand to the best zoxide match."
  (interactive)
  (let ((input (minibuffer-contents)))
    (if (my/zoxide--path-like-p input)
        (my/zoxide-complete-path)
      (if-let* ((dir (my/zoxide--query input)))
          (progn (delete-minibuffer-contents)
                 (insert (abbreviate-file-name dir)))
        (minibuffer-message "No zoxide match")))))

(defvar my/zoxide-minibuffer-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map minibuffer-local-map)
    (keymap-set map "TAB" #'my/zoxide-complete)
    map)
  "Minibuffer keymap for `my/zoxide-dired'.")

(defun my/zoxide-dired ()
  "Prompt for a zoxide query and open the chosen directory in Dired."
  (interactive)
  (let* ((orig (current-buffer))
         (input (minibuffer-with-setup-hook
                    (lambda ()
                      (setq my/zoxide--ghost-ov nil)
                      (add-hook 'after-change-functions #'my/zoxide--update-ghost nil t)
                      (add-hook 'completion-at-point-functions #'my/zoxide--path-capf nil t)
                      (add-hook 'completion-preview-inhibit-functions
                                #'my/zoxide--inhibit-preview nil t)
                      (setq-local completion-preview-completion-styles '(basic)
                                  completion-preview-minimum-symbol-length nil
                                  completion-preview-idle-delay nil
                                  completion-preview-overlay-priority 1200)
                      (completion-preview-mode 1))
                  (read-from-minibuffer "zoxide: " nil my/zoxide-minibuffer-map)))
         (dir (my/zoxide--query input)))
    (if dir
        (progn
          (my/zoxide--add dir)
          (if (and (buffer-live-p orig)
                   (eq orig (window-buffer (selected-window)))
                   (with-current-buffer orig (derived-mode-p 'dired-mode)))
              (find-alternate-file dir)
            (dired dir)))
      (user-error "No zoxide match for: %s" input))))

;; ===============================================================
;;; dired-copy-file

(defun my/dired-copy-file-uri ()
  "Copy the marked files as file:// URIs to the Wayland clipboard."
  (interactive)
  (unless (executable-find "wl-copy")
    (user-error "wl-copy not found; install wl-clipboard"))
  (require 'browse-url)
  (let* ((files (dired-get-marked-files))
         (uris (mapconcat (lambda (file)
                            (concat (browse-url-file-url file) "\r\n"))
                          files "")))
    (let ((proc (make-process
                 :name "wl-copy"
                 :command '("wl-copy" "--type" "text/uri-list")
                 :connection-type 'pipe
                 :noquery t)))
      (process-send-string proc uris)
      (process-send-eof proc)
      (while (accept-process-output proc 0.1)))
    (dired-unmark-all-marks)
    (message "Copied %d file URI%s to clipboard"
             (length files)
             (if (length= files 1) "" "s"))))

;; ===============================================================
;;; dired-find-name

(declare-function nerd-icons-dired-mode "nerd-icons-dired")
(declare-function dired-insert-set-properties "dired")
(declare-function dired-build-subdir-alist "dired")
(declare-function dired-hide-details-mode "dired")
(declare-function dired-move-to-filename "dired")
(declare-function dired-get-filename "dired")
(declare-function dired-omit-mode "dired-x")
(declare-function dired-get-subdir "dired")
(declare-function dired-goto-file "dired")

(defvar nerd-icons-dired-dir-icon-function)
(defvar nerd-icons-dired-infix-string)
(defvar nerd-icons-dired-icon-size)
(defvar nerd-icons-dired-mode)

(defvar dired-listing-switches)
(defvar dired-actual-switches)
(defvar dired-mode-map)
(defvar dired-buffers)

(defvar my/dired-find-name-prune-dirs '(".git" ".hg" ".svn" ".jj")
  "Directory names excluded from searches.")

(defcustom my/dired-find-name-debounce 0.15
  "Seconds of idle input before refreshing the live search.
Lower values feel more responsive, higher values spawn fewer `fd' processes."
  :type 'number
  :group 'dired)

(defvar my/dired-find-name--proc nil
  "Current live-search `fd' process, or nil.")

(defvar my/dired-find-name--timer nil
  "Timer used to debounce live search updates.")

(defvar my/dired-find-name--buffer nil
  "Live search results buffer, or nil.")

(defvar my/dired-find-name--root nil
  "Root directory of the current search.")

(defun my/dired-find-name--fd-args (query dir)
  "Return `fd' arguments for searching QUERY under DIR.
Uses `--list-details' so a single process emits Dired-ready output."
  (append '("--color=never" "--list-details" "--hidden" "--no-ignore"
            "--type" "f" "--fixed-strings" "--ignore-case")
          (mapcan (lambda (d) (list "--exclude" d))
                  my/dired-find-name-prune-dirs)
          (list "--" query (expand-file-name dir))))

(defun my/dired-find-name--parse (line)
  "Parse an `fd --list-details' LINE.
Return (DIR BASENAME LISTING), where LISTING is ready for insertion
into a Dired subdir listing."
  (when (string-match "\\(/.*\\)\\'" line)
    (let ((path (match-string 1 line))
          (prefix (substring line 0 (match-beginning 1))))
      (list (file-name-directory path)
            (file-name-nondirectory path)
            (concat prefix (file-name-nondirectory path))))))

(defun my/dired-find-name--icon-subdirs ()
  "Add folder icons to Dired subdir headers."
  (when (bound-and-true-p nerd-icons-dired-mode)
    (save-excursion
      (goto-char (point-min))
      (while (not (eobp))
        (when-let* ((dir (dired-get-subdir)))
          (beginning-of-line)
          (skip-chars-forward " \t")
          (let* ((pos  (point))
                 (icon (funcall nerd-icons-dired-dir-icon-function
                                dir :height nerd-icons-dired-icon-size
                                :face 'dired-directory))
                 (str  (concat icon nerd-icons-dired-infix-string))
                 (ov   (make-overlay pos (1+ pos)))
                 (inhibit-read-only t))
            (overlay-put ov 'my/find-name-icon t)
            (overlay-put ov 'evaporate t)
            (overlay-put ov 'before-string (propertize str 'display str))))
        (forward-line 1)))))

(defun my/dired-find-name--goto (file)
  "Move point to FILE by scanning file names.
More reliable than `dired-goto-file' for this buffer."
  (goto-char (point-min))
  (let ((found nil))
    (while (and (not found) (not (eobp)))
      (when (dired-move-to-filename nil)
        (let ((this (dired-get-filename nil t)))
          (when (and this (file-equal-p this file))
            (setq found t))))
      (unless found (forward-line 1)))
    (when found (dired-move-to-filename))
    found))

(defun my/dired-find-name--insert-groups (groups)
  "Insert GROUPS as Dired subdir listings.
Each entry must be a (DIR BASENAME LISTING) triple."
  (let ((first t))
    (dolist (group groups)
      (if first (setq first nil) (insert "\n"))
      (insert "  " (directory-file-name (car group)) ":\n")
      (insert (format "  total used in directory %d\n" (length (cdr group))))
      (dolist (entry (cdr group))
        (insert "  " (nth 2 entry) "\n")))))

(defun my/dired-find-name--render (root details)
  "Render DETAILS under ROOT as a Dired buffer.
The buffer is assumed to already be in `dired-mode'."
  (when (buffer-live-p my/dired-find-name--buffer)
    (with-current-buffer my/dired-find-name--buffer
      (let* ((inhibit-read-only t)
             (parsed (delq nil (mapcar #'my/dired-find-name--parse details)))
             (groups (seq-group-by #'car parsed)))
        (widen)
        (remove-overlays nil nil 'my/find-name-icon t)
        (erase-buffer)
        (setq-local default-directory (file-name-as-directory root))
        (if (null parsed)
            (insert "  " (directory-file-name root) ":\n"
                    "  total used in directory 0\n\n"
                    "  (no matches)\n")
          (my/dired-find-name--insert-groups groups))
        (dired-build-subdir-alist)
        (dired-insert-set-properties (point-min) (point-max))
        (when (bound-and-true-p nerd-icons-dired-mode)
          (run-hooks 'dired-after-readin-hook))
        (my/dired-find-name--icon-subdirs)
        (goto-char (point-min))
        (when (and parsed (null (cdr parsed)))
          (let ((target (expand-file-name (nth 1 (car parsed))
                                          (nth 0 (car parsed)))))
            (my/dired-find-name--goto target)))))))

(defun my/dired-find-name--sentinel (proc event)
  "Render PROC's results when EVENT indicates completion, then clean up."
  (when (string-prefix-p "finished" event)
    (when-let* ((buf (process-buffer proc)) ((buffer-live-p buf)))
      (let ((details (with-current-buffer buf
                       (split-string (buffer-string) "\n" t))))
        (condition-case err
            (my/dired-find-name--render my/dired-find-name--root details)
          (error (message "find-name render error: %S" err))))
      (kill-buffer buf))))

(defun my/dired-find-name--dispatch (query)
  "Kill any running search and start an async `fd' for QUERY."
  (when (and my/dired-find-name--proc
             (process-live-p my/dired-find-name--proc))
    (delete-process my/dired-find-name--proc))
  (cond
   ((string-empty-p query)
    (my/dired-find-name--render my/dired-find-name--root nil))
   ((not (executable-find "fd"))
    (message "find-name: the `fd' program is required for live search"))
   (t
    (let ((proc (make-process
                 :name "find-name-fd"
                 :buffer (generate-new-buffer " *find-name-fd*")
                 :noquery t
                 :connection-type 'pipe
                 :command (cons "fd" (my/dired-find-name--fd-args
                                      query my/dired-find-name--root))
                 :sentinel #'my/dired-find-name--sentinel)))
      (setq my/dired-find-name--proc proc)))))

(defun my/dired-find-name--schedule (&rest _)
  "Schedule a search after minibuffer input settles."
  (let ((query (minibuffer-contents-no-properties)))
    (when (timerp my/dired-find-name--timer)
      (cancel-timer my/dired-find-name--timer))
    (setq my/dired-find-name--timer
          (run-with-timer my/dired-find-name-debounce nil
                          #'my/dired-find-name--dispatch query))))

(defun my/dired-find-name--cleanup ()
  "Tear down the live-search timer and process."
  (when (timerp my/dired-find-name--timer)
    (cancel-timer my/dired-find-name--timer))
  (when (and my/dired-find-name--proc
             (process-live-p my/dired-find-name--proc))
    (delete-process my/dired-find-name--proc))
  (setq my/dired-find-name--timer nil
        my/dired-find-name--proc nil))

(defun my/dired-find-name ()
  "Find files under `default-directory' whose names contain a query.
Display live results in a Dired buffer as you type."
  (interactive)
  (require 'dired)
  (let* ((root (expand-file-name default-directory))
         (bufname (format "*find-name: %s*" (abbreviate-file-name root)))
         (buf (progn (when (get-buffer bufname) (kill-buffer bufname))
                     (get-buffer-create bufname))))
    (setq my/dired-find-name--buffer buf
          my/dired-find-name--root root)
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (setq-local default-directory (file-name-as-directory root))
        (let ((dired-buffers nil)) (dired-mode root)))
      (when (bound-and-true-p dired-omit-mode) (dired-omit-mode -1))
      (let ((map (make-sparse-keymap)))
        (set-keymap-parent map dired-mode-map)
        (keymap-set map "q" #'kill-current-buffer)
        (use-local-map map)))
    (display-buffer buf)
    (let ((confirmed nil))
      (unwind-protect
          (progn
            (condition-case nil
                (progn
                  (minibuffer-with-setup-hook
                      (lambda ()
                        (add-hook 'after-change-functions
                                  #'my/dired-find-name--schedule nil t)
                        (add-hook 'minibuffer-exit-hook
                                  #'my/dired-find-name--cleanup nil t))
                    (read-from-minibuffer
                     (format "Find name under %s: "
                             (abbreviate-file-name root))))
                  (setq confirmed t))
              (quit nil))
            (if confirmed
                (when (buffer-live-p buf)
                  (if-let* ((win (get-buffer-window buf)))
                      (select-window win)
                    (pop-to-buffer buf)))
              (when (buffer-live-p buf) (kill-buffer buf))))
        (my/dired-find-name--cleanup)))))

;; ===============================================================
;;; dired-find-file (smart RET)

(declare-function dired-get-file-for-visit "dired")
(declare-function dired-do-open "dired-aux")
(declare-function dired-find-file "dired")

(defcustom my/dired-external-extensions
  '("png" "jpg" "jpeg" "gif" "bmp" "webp" "tiff" "tif" "svg" "ico" "avif"
    "mp4" "mkv" "avi" "mov" "webm" "flv" "wmv" "mpg" "mpeg" "m4v"
    "mp3" "flac" "wav" "ogg" "opus" "m4a" "aac"
    "xcf" "kra" "psd" "blend"
    "cbz" "cbr")
  "File extensions to open in an external application."
  :type '(repeat string)
  :group 'dired)

(defcustom my/dired-find-file-full-window nil
  "Whether `my/dired-find-file' opens files in a full window.
When non-nil, the Dired buffer is killed after opening the file."
  :type 'boolean
  :group 'dired)

(defun my/dired-external-file-p (file)
  "Return non-nil if FILE should be opened externally."
  (when-let* ((ext (file-name-extension file)))
    (member (downcase ext) my/dired-external-extensions)))

(defun my/dired-find-file ()
  "Visit the file on this line in Emacs or an external application."
  (interactive)
  (let ((file (dired-get-file-for-visit)))
    (cond
     ((and (not (file-directory-p file))
           (my/dired-external-file-p file)
           (fboundp 'dired-do-open))
      (dired-do-open))
     ((and my/dired-find-file-full-window
           (not (file-directory-p file)))
      (kill-buffer (current-buffer))
      (find-file file))
     (t
      (dired-find-file)))))

(provide 'dired-snacks)
;;; dired-snacks.el ends here
