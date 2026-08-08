;;; dired-snacks.el --- Dired utilities -*- lexical-binding: t; -*-

;; Author: Lucas
;; Version: 0.1.0
;; Package-Requires: ((emacs "31.0"))
;; Keywords: files, convenience

;;; Commentary:

;; A bundle of small Dired enhancements:
;; zoxide     - jump to a directory by frecency, with inline preview
;; find       - incremental file-name search as you type
;; open       - smart RET for opening files in external apps
;; duplicate  - duplicate marked files with auto-numbered names
;; subtree    - expand directories inline without leaving the buffer
;; breadcrumb - show the current directory in the header line
;; split      - second Dired pane with independent navigation
;; mode-line  - per-buffer mode line with size, time, sort, position
;; copy-uri   - copy files as file:// URIs to the clipboard

;;; Code:

(eval-when-compile
  (require 'dired)
  (require 'dired-aux)
  (require 'dired-x)
  (require 'browse-url)
  (require 'completion-preview))

(declare-function dired-get-filename "dired")
(declare-function dired-get-marked-files "dired")
(declare-function dired-get-file-for-visit "dired")
(declare-function dired-get-subdir "dired")
(declare-function dired-current-directory "dired")
(declare-function dired-move-to-filename "dired")
(declare-function dired-goto-subdir "dired")
(declare-function dired-build-subdir-alist "dired")
(declare-function dired-insert-directory "dired")
(declare-function dired-insert-set-properties "dired")
(declare-function dired-unmark-all-marks "dired")
(declare-function dired-find-file "dired")
(declare-function dired-goto-file "dired")
(declare-function dired-add-file "dired-aux")
(declare-function dired--find-file "dired")
(declare-function dired-kill-subdir "dired-aux")
(declare-function dired-hide-subdir "dired-aux")
(declare-function dired-omit-mode "dired-x")
(declare-function browse-url-file-url "browse-url")

(declare-function nerd-icons-dired--refresh "nerd-icons-dired")
(declare-function nerd-icons-dired-mode "nerd-icons-dired")
(defvar nerd-icons-dired-dir-icon-function)
(defvar nerd-icons-dired-infix-string)
(defvar nerd-icons-dired-icon-size)
(defvar nerd-icons-dired-mode)

(defgroup dired-snacks nil
  "Small Dired enhancements."
  :group 'dired
  :prefix "dired-snacks-")

;; ===============================================================
;;; zoxide

(defvar dired-snacks--zoxide-ghost-ov nil
  "Overlay showing the best zoxide match in the minibuffer.")

(defun dired-snacks--zoxide-query (input)
  "Return the directory for INPUT: a literal name, else zoxide's best match."
  (when (and input (not (string-empty-p input)))
    (let ((expanded (expand-file-name input)))
      (if (and (string-match-p "[/~]" input) (file-directory-p expanded))
          expanded
        (when (executable-find "zoxide")
          (with-temp-buffer
            (when (zerop (call-process "zoxide" nil t nil "query" "--" input))
              (let ((dir (string-trim (buffer-string))))
                (and (file-directory-p dir) dir)))))))))

(defun dired-snacks--zoxide-add (dir)
  "Register DIR in the zoxide database."
  (when (and dir (executable-find "zoxide"))
    (call-process "zoxide" nil 0 nil "add" "--" (expand-file-name dir))))

(defun dired-snacks--zoxide-add-default-directory ()
  "Register `default-directory' in the zoxide database."
  (when (and (not (file-remote-p default-directory))
             (file-directory-p default-directory))
    (dired-snacks--zoxide-add default-directory)))

(defun dired-snacks--zoxide-file-name-p (input)
  "Return non-nil if INPUT looks like a literal file name."
  (and (string-match-p "[/~]" input) t))

(defun dired-snacks--zoxide-update-ghost (&rest _)
  "Refresh the inline zoxide suggestion for fuzzy queries."
  (when (overlayp dired-snacks--zoxide-ghost-ov)
    (delete-overlay dired-snacks--zoxide-ghost-ov))
  (let ((input (minibuffer-contents)))
    (unless (dired-snacks--zoxide-file-name-p input)
      (when-let* ((dir (dired-snacks--zoxide-query input)))
        (setq dired-snacks--zoxide-ghost-ov (make-overlay (point-max) (point-max) nil t t))
        (overlay-put dired-snacks--zoxide-ghost-ov 'after-string
                     (propertize (concat "  → " (abbreviate-file-name dir))
                                 'face 'shadow 'cursor t))))))

(defun dired-snacks--zoxide-file-name-capf ()
  "Completion-at-point function for literal file names."
  (list (minibuffer-prompt-end) (point) #'completion-file-name-table))

(defun dired-snacks--zoxide-inhibit-preview ()
  "Inhibit `completion-preview' unless the input is a literal file name."
  (not (dired-snacks--zoxide-file-name-p (minibuffer-contents))))

(defun dired-snacks--zoxide-complete-file-name ()
  "Complete the minibuffer input as a directory name."
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

(defun dired-snacks-zoxide-complete ()
  "Complete the minibuffer input, as a file name or as a zoxide match."
  (interactive)
  (let ((input (minibuffer-contents)))
    (if (dired-snacks--zoxide-file-name-p input)
        (dired-snacks--zoxide-complete-file-name)
      (if-let* ((dir (dired-snacks--zoxide-query input)))
          (progn (delete-minibuffer-contents)
                 (insert (abbreviate-file-name dir)))
        (minibuffer-message "No zoxide match")))))

(defvar dired-snacks--zoxide-minibuffer-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map minibuffer-local-map)
    (keymap-set map "TAB" #'dired-snacks-zoxide-complete)
    map)
  "Minibuffer keymap for `dired-snacks-zoxide'.")

;;;###autoload
(defun dired-snacks-zoxide ()
  "Prompt for a zoxide query and open the chosen directory in Dired."
  (interactive)
  (require 'completion-preview)
  (let* ((orig (current-buffer))
         (input (minibuffer-with-setup-hook
                    (lambda ()
                      (setq dired-snacks--zoxide-ghost-ov nil)
                      (add-hook 'after-change-functions #'dired-snacks--zoxide-update-ghost nil t)
                      (add-hook 'completion-at-point-functions #'dired-snacks--zoxide-file-name-capf nil t)
                      (add-hook 'completion-preview-inhibit-functions
                                #'dired-snacks--zoxide-inhibit-preview nil t)
                      (setq-local completion-preview-completion-styles '(basic)
                                  completion-preview-minimum-symbol-length nil
                                  completion-preview-idle-delay nil
                                  completion-preview-overlay-priority 1200)
                      (completion-preview-mode 1))
                  (read-from-minibuffer "zoxide: " nil dired-snacks--zoxide-minibuffer-map)))
         (dir (dired-snacks--zoxide-query input)))
    (if dir
        (progn
          (dired-snacks--zoxide-add dir)
          (if (and (buffer-live-p orig)
                   (eq orig (window-buffer (selected-window)))
                   (with-current-buffer orig (derived-mode-p 'dired-mode)))
              (find-alternate-file dir)
            (dired dir)))
      (user-error "No zoxide match for: %s" input))))

;; ===============================================================
;;; copy-uri

;;;###autoload
(defun dired-snacks-copy-file-uri ()
  "Copy the marked files as file:// URIs to the Wayland clipboard."
  (interactive)
  (unless (executable-find "wl-copy")
    (user-error "Cannot find wl-copy; install wl-clipboard"))
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
      (process-send-eof proc))
    (dired-unmark-all-marks)
    (message "Copied %d file URI%s to clipboard"
             (length files)
             (if (length= files 1) "" "s"))))

;; ===============================================================
;;; find

(defcustom dired-snacks-find-prune-dirs '(".git" ".hg" ".svn" ".jj")
  "Directory names excluded from searches."
  :type '(repeat string)
  :group 'dired-snacks)

(defcustom dired-snacks-find-debounce 0.15
  "Seconds of idle input before the live search refreshes."
  :type 'number
  :group 'dired-snacks)

(defvar dired-snacks--find-proc nil
  "Current live-search `fd' process, or nil.")

(defvar dired-snacks--find-timer nil
  "Timer used to debounce live search updates.")

(defvar dired-snacks--find-buffer nil
  "Live search results buffer, or nil.")

(defvar dired-snacks--find-root nil
  "Root directory of the current search.")

(defun dired-snacks--find-fd-args (query dir)
  "Return the `fd' arguments to search for QUERY under DIR."
  (append '("--color=never" "--list-details" "--hidden" "--no-ignore"
            "--type" "f" "--fixed-strings" "--ignore-case")
          (mapcan (lambda (d) (list "--exclude" d))
                  dired-snacks-find-prune-dirs)
          (list "--" query (expand-file-name dir))))

(defun dired-snacks--find-parse (line)
  "Parse an `fd --list-details' LINE into (DIR BASENAME LISTING)."
  (when (string-match "\\(/.*\\)\\'" line)
    (let ((file (match-string 1 line))
          (prefix (substring line 0 (match-beginning 1))))
      (list (file-name-directory file)
            (file-name-nondirectory file)
            (concat prefix (file-name-nondirectory file))))))

(defun dired-snacks--find-icon-subdirs ()
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
                 (ov   (make-overlay pos (1+ pos))))
            (overlay-put ov 'dired-snacks--find-icon t)
            (overlay-put ov 'evaporate t)
            (overlay-put ov 'before-string (propertize str 'display str))))
        (forward-line 1)))))

(defun dired-snacks--find-goto (file)
  "Move point to FILE."
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

(defun dired-snacks--find-insert-groups (groups)
  "Insert GROUPS as Dired subdir listings."
  (let ((first t))
    (dolist (group groups)
      (if first (setq first nil) (insert "\n"))
      (insert "  " (directory-file-name (car group)) ":\n")
      (insert (format "  total used in directory %d\n" (length (cdr group))))
      (dolist (entry (cdr group))
        (insert "  " (nth 2 entry) "\n")))))

(defun dired-snacks--find-render (root details)
  "Render DETAILS under ROOT as a Dired buffer."
  (when (buffer-live-p dired-snacks--find-buffer)
    (with-current-buffer dired-snacks--find-buffer
      (let* ((inhibit-read-only t)
             (parsed (delq nil (mapcar #'dired-snacks--find-parse details)))
             (groups (seq-group-by #'car parsed)))
        (widen)
        (remove-overlays nil nil 'dired-snacks--find-icon t)
        (erase-buffer)
        (setq-local default-directory (file-name-as-directory root))
        (if (null parsed)
            (insert "  " (directory-file-name root) ":\n"
                    "  total used in directory 0\n\n"
                    "  (no matches)\n")
          (dired-snacks--find-insert-groups groups))
        (dired-build-subdir-alist)
        (dired-insert-set-properties (point-min) (point-max))
        (when (bound-and-true-p nerd-icons-dired-mode)
          (run-hooks 'dired-after-readin-hook))
        (dired-snacks--find-icon-subdirs)
        (goto-char (point-min))
        (when (and parsed (null (cdr parsed)))
          (let ((target (expand-file-name (nth 1 (car parsed))
                                          (nth 0 (car parsed)))))
            (dired-snacks--find-goto target)))))))

(defun dired-snacks--find-sentinel (proc event)
  "Render PROC's results when EVENT indicates completion, then clean up."
  (when (string-prefix-p "finished" event)
    (when-let* ((buf (process-buffer proc)) ((buffer-live-p buf)))
      (let ((details (with-current-buffer buf
                       (split-string (buffer-string) "\n" t))))
        (condition-case err
            (dired-snacks--find-render dired-snacks--find-root details)
          (error (message "find render error: %S" err))))
      (kill-buffer buf))))

(defun dired-snacks--find-dispatch (query)
  "Kill any running search and start an async `fd' for QUERY."
  (when (and dired-snacks--find-proc
             (process-live-p dired-snacks--find-proc))
    (delete-process dired-snacks--find-proc))
  (cond
   ((string-empty-p query)
    (dired-snacks--find-render dired-snacks--find-root nil))
   ((not (executable-find "fd"))
    (message "find: the `fd' program is required for live search"))
   (t
    (let ((proc (make-process
                 :name "find-fd"
                 :buffer (generate-new-buffer " *find-fd*")
                 :noquery t
                 :connection-type 'pipe
                 :command (cons "fd" (dired-snacks--find-fd-args
                                      query dired-snacks--find-root))
                 :sentinel #'dired-snacks--find-sentinel)))
      (setq dired-snacks--find-proc proc)))))

(defun dired-snacks--find-schedule (&rest _)
  "Schedule a search after minibuffer input settles."
  (let ((query (minibuffer-contents-no-properties)))
    (when (timerp dired-snacks--find-timer)
      (cancel-timer dired-snacks--find-timer))
    (setq dired-snacks--find-timer
          (run-with-timer dired-snacks-find-debounce nil
                          #'dired-snacks--find-dispatch query))))

(defun dired-snacks--find-cleanup ()
  "Tear down the live-search timer and process."
  (when (timerp dired-snacks--find-timer)
    (cancel-timer dired-snacks--find-timer))
  (when (and dired-snacks--find-proc
             (process-live-p dired-snacks--find-proc))
    (delete-process dired-snacks--find-proc))
  (setq dired-snacks--find-timer nil
        dired-snacks--find-proc nil))

;;;###autoload
(defun dired-snacks-find ()
  "Search for files under `default-directory', showing results as you type."
  (interactive)
  (require 'dired)
  (let* ((root (expand-file-name default-directory))
         (here (selected-window))
         (side (window-parameter here 'window-side))
         (slot (window-parameter here 'window-slot))
         (bufname (format "*find: %s*" (abbreviate-file-name root)))
         (buf (progn (when (get-buffer bufname) (kill-buffer bufname))
                     (get-buffer-create bufname))))
    (setq dired-snacks--find-buffer buf
          dired-snacks--find-root root)
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (setq-local default-directory (file-name-as-directory root))
        (let ((dired-buffers nil)) (dired-mode root)))
      (when (bound-and-true-p dired-omit-mode) (dired-omit-mode -1))
      (let ((map (make-sparse-keymap)))
        (set-keymap-parent map dired-mode-map)
        (keymap-set map "q" #'kill-current-buffer)
        (keymap-set map "TAB" #'dired-hide-subdir)
        (use-local-map map)))
    (let ((display-buffer-overriding-action
           (and side `(display-buffer-in-side-window
                       (side . ,side) (slot . ,(or slot 0))))))
      (display-buffer buf))
    (let ((confirmed nil))
      (unwind-protect
          (progn
            (condition-case nil
                (progn
                  (minibuffer-with-setup-hook
                      (lambda ()
                        (add-hook 'after-change-functions
                                  #'dired-snacks--find-schedule nil t)
                        (add-hook 'minibuffer-exit-hook
                                  #'dired-snacks--find-cleanup nil t))
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
        (dired-snacks--find-cleanup)))))

;; ===============================================================
;;; open

(defcustom dired-snacks-open-full-window nil
  "When non-nil, opening a file kills the Dired buffer and fills the window."
  :type 'boolean
  :group 'dired-snacks)

(defcustom dired-snacks-external-openers
  '(("gio" "open")
    ("xdg-open"))
  "Programs tried, in order, to open a file externally.
Each entry is (PROGRAM ARG...); the first available PROGRAM is used."
  :type '(repeat (cons string (repeat string)))
  :group 'dired-snacks)

(defcustom dired-snacks-external-app-alist nil
  "File extensions to open in an external application.
Each entry is (EXTENSIONS PROGRAM ARG...), where EXTENSIONS is a
string or list of strings.  PROGRAM opens those files; when
omitted, `dired-snacks-external-openers' is used instead."
  :type '(repeat (cons (choice string (repeat string))
                       (repeat string)))
  :group 'dired-snacks)

(defun dired-snacks--file-ext (file)
  "Return the downcased extension of FILE, or nil for a directory."
  (unless (file-directory-p file)
    (downcase (or (file-name-extension file) ""))))

(defun dired-snacks--entry-for-ext (ext)
  "Return the alist entry matching EXT, or nil."
  (when ext
    (seq-find (lambda (entry) (member ext (ensure-list (car entry))))
              dired-snacks-external-app-alist)))

(defun dired-snacks--external-file-p (file)
  "Return non-nil if FILE should be opened externally."
  (dired-snacks--entry-for-ext (dired-snacks--file-ext file)))

(defun dired-snacks--default-opener ()
  "Return the first available default opener, as (PROGRAM ARG...), or nil."
  (seq-find (lambda (entry) (executable-find (car entry)))
            dired-snacks-external-openers))

(defun dired-snacks--opener-for-file (file)
  "Return the opener for FILE, as (PROGRAM ARG...), or nil.
Prefer the mapped program, falling back to the default opener."
  (let ((mapped (cdr (dired-snacks--entry-for-ext
                      (dired-snacks--file-ext file)))))
    (if (and mapped (executable-find (car mapped)))
        mapped
      (dired-snacks--default-opener))))

(defun dired-snacks--open-external (files)
  "Open each of FILES in its external application.
Files sharing an opener are passed together in one call."
  (let ((groups nil))
    (dolist (file files)
      (if-let* ((opener (dired-snacks--opener-for-file file)))
          (push (expand-file-name file) (alist-get opener groups nil nil #'equal))
        (user-error "No external opener found; install glib2 (gio) or xdg-utils")))
    (pcase-dolist (`(,opener . ,names) groups)
      (apply #'call-process (car opener) nil 0 nil
             (append (cdr opener) (nreverse names))))))

;;;###autoload
(defun dired-snacks-open ()
  "Open the marked files, or the file at point.
Files matching `dired-snacks-external-app-alist' open in an external
application; the rest are visited in Emacs, and directories are entered."
  (interactive)
  (let ((file (dired-get-file-for-visit)))
    (cond
     ((and (not (file-directory-p file))
           (dired-snacks--external-file-p file))
      (dired-snacks--open-external
       (or (dired-get-marked-files nil nil #'dired-snacks--external-file-p)
           (list file))))
     ((and dired-snacks-open-full-window
           (not (file-directory-p file)))
      (kill-buffer (current-buffer))
      (find-file file))
     (t
      (dired-find-file)))))

;; ===============================================================
;;; duplicate

(defun dired-snacks--numbered-stem (base)
  "Return BASE without a trailing -N suffix."
  (if (string-match "\\`\\(.+?\\)-[0-9]+\\'" base)
      (match-string 1 base)
    base))

(defun dired-snacks--unique-copy-name (file)
  "Return an absolute, free name for a numbered copy of FILE."
  (let* ((file (directory-file-name (expand-file-name file)))
         (dir  (file-name-directory file))
         (node (file-name-nondirectory file))
         (ext  (unless (file-directory-p file) (file-name-extension node)))
         (base (if ext (file-name-sans-extension node) node))
         (stem (dired-snacks--numbered-stem base))
         (n 1)
         candidate)
    (while (progn
             (setq candidate
                   (expand-file-name
                    (concat stem "-" (number-to-string n)
                            (and ext (concat "." ext)))
                    dir))
             (file-exists-p candidate))
      (setq n (1+ n)))
    candidate))

(defun dired-snacks--duplicate-file (file)
  "Copy FILE to a numbered name and return that name."
  (let ((copy (dired-snacks--unique-copy-name file)))
    (if (file-directory-p file)
        (copy-directory file copy nil t nil)
      (copy-file file copy))
    (dired-add-file copy)
    copy))

;;;###autoload
(defun dired-snacks-duplicate ()
  "Duplicate the marked files, or the file at point.
Each copy is renamed with a numbered suffix to avoid clashes."
  (interactive)
  (let* ((files (dired-get-marked-files nil nil nil t))
         (single (eq (car files) t))
         (copies (mapcar #'dired-snacks--duplicate-file
                         (if single (cdr files) files))))
    (when copies
      (dired-goto-file (car copies))
      (message "Duplicated %d file%s"
               (length copies) (if (length= copies 1) "" "s")))))

;; ===============================================================
;;; subtree

(defcustom dired-snacks-subtree-line-prefix "  "
  "Indentation added per nesting level in a subtree."
  :type 'string
  :group 'dired-snacks)

(defcustom dired-snacks-subtree-after-change-hook nil
  "Hook run after a subtree is expanded or collapsed."
  :type 'hook
  :group 'dired-snacks)

(defvar-local dired-snacks--subtree-overlays nil
  "Subtree overlays in this buffer.")

(defvar-local dired-snacks--subtree-dirs nil
  "Directories currently expanded as subtrees.")

(defun dired-snacks--subtree-depth-at (pos)
  "Return the depth of the innermost subtree covering POS, or 0 if none."
  (let ((depth 0))
    (dolist (ov (overlays-at pos) depth)
      (let ((d (overlay-get ov 'dired-snacks--subtree)))
        (when (and d (> d depth)) (setq depth d))))))

(defun dired-snacks--subtree-child-overlay ()
  "Return the subtree expanded directly under the current line, or nil."
  (let ((start (save-excursion (forward-line 1) (line-beginning-position))))
    (seq-find (lambda (ov)
                (and (overlay-buffer ov)
                     (overlay-get ov 'dired-snacks--subtree)
                     (= (overlay-start ov) start)))
              dired-snacks--subtree-overlays)))

(defun dired-snacks--subtree-insert ()
  "Insert the directory on this line as an inline subtree."
  (let* ((dir (file-name-as-directory (dired-get-filename nil t)))
         (depth (1+ (dired-snacks--subtree-depth-at (point))))
         (prefix (apply #'concat (make-list depth dired-snacks-subtree-line-prefix)))
         (inhibit-read-only t))
    (save-excursion
      (forward-line 1)
      (let ((beg (point)) end header-end)
        (dired-insert-directory dir dired-actual-switches nil nil t)
        (setq end (point))
        (dired-build-subdir-alist)
        (save-excursion (goto-char beg) (forward-line 1) (setq header-end (point)))
        (let ((header (make-overlay beg header-end)))
          (overlay-put header 'invisible 'dired-snacks--subtree-header)
          (overlay-put header 'evaporate t)
          (push header dired-snacks--subtree-overlays))
        (let ((ov (make-overlay beg end)))
          (overlay-put ov 'dired-snacks--subtree depth)
          (overlay-put ov 'line-prefix prefix)
          (overlay-put ov 'evaporate t)
          (push ov dired-snacks--subtree-overlays))
        (unless (member dir dired-snacks--subtree-dirs)
          (push dir dired-snacks--subtree-dirs))))
    (run-hooks 'dired-snacks-subtree-after-change-hook)
    (dired-move-to-filename)))

(defun dired-snacks--subtree-remove (ov)
  "Collapse the subtree tracked by overlay OV."
  (let ((beg (overlay-start ov))
        (end (overlay-end ov))
        (inhibit-read-only t))
    (dolist (o (overlays-in beg end))
      (when (and (memq o dired-snacks--subtree-overlays)
                 (>= (overlay-start o) beg)
                 (<= (overlay-end o) end))
        (setq dired-snacks--subtree-overlays (delq o dired-snacks--subtree-overlays))
        (delete-overlay o)))
    (delete-region beg end)
    (dired-build-subdir-alist)
    (setq dired-snacks--subtree-dirs
          (seq-filter (lambda (d) (assoc d dired-subdir-alist))
                      dired-snacks--subtree-dirs)))
  (run-hooks 'dired-snacks-subtree-after-change-hook)
  (dired-move-to-filename))

;;;###autoload
(defun dired-snacks-subtree-toggle ()
  "Expand the directory at point as an inline subtree, or collapse it."
  (interactive)
  (let ((dir (dired-get-filename nil t)))
    (cond
     ((not (and dir (file-directory-p dir)))
      (user-error "Point is not on a directory"))
     ((dired-snacks--subtree-child-overlay)
      (dired-snacks--subtree-remove (dired-snacks--subtree-child-overlay)))
     (t (dired-snacks--subtree-insert)))))

(defun dired-snacks--subtree-reset ()
  "Collapse every tracked subtree."
  (when dired-snacks--subtree-dirs
    (let ((inhibit-read-only t))
      ;; deepest first, so a parent is removed only after its children
      (dolist (dir (sort (copy-sequence dired-snacks--subtree-dirs)
                         (lambda (a b) (> (length a) (length b)))))
        (when (assoc dir dired-subdir-alist)
          (save-excursion
            (when (dired-goto-subdir dir)
              (dired-kill-subdir)))))
      (mapc #'delete-overlay dired-snacks--subtree-overlays)
      (setq dired-snacks--subtree-overlays nil
            dired-snacks--subtree-dirs nil))))

(defun dired-snacks--subtree-setup ()
  "Enable inline subtrees in the current Dired buffer."
  (remove-from-invisibility-spec 'dired-snacks--subtree-header)
  (add-to-invisibility-spec 'dired-snacks--subtree-header)
  (add-hook 'dired-after-readin-hook #'dired-snacks--subtree-reset nil t))

(defun dired-snacks--subtree-teardown ()
  "Disable inline subtrees in the current Dired buffer."
  (remove-hook 'dired-after-readin-hook #'dired-snacks--subtree-reset t)
  (dired-snacks--subtree-reset)
  (remove-from-invisibility-spec 'dired-snacks--subtree-header))

(defun dired-snacks--subtree-refresh-icons ()
  "Redraw file icons after a subtree change, when `nerd-icons-dired' is on."
  (when (bound-and-true-p nerd-icons-dired-mode)
    (nerd-icons-dired--refresh)))

;; ===============================================================
;;; breadcrumb

(defcustom dired-snacks-breadcrumb-separator " » "
  "Separator drawn between breadcrumb segments."
  :type 'string
  :group 'dired-snacks)

(defcustom dired-snacks-breadcrumb-home "~"
  "Glyph for the home directory in the breadcrumb."
  :type 'string
  :group 'dired-snacks)

(defcustom dired-snacks-breadcrumb-root "/"
  "Glyph for the filesystem root in the breadcrumb."
  :type 'string
  :group 'dired-snacks)

(defcustom dired-snacks-breadcrumb-margin "  "
  "Left padding before the breadcrumb."
  :type 'string
  :group 'dired-snacks)

(defcustom dired-snacks-breadcrumb-hide-header t
  "When non-nil, hide the directory header line."
  :type 'boolean
  :group 'dired-snacks)

(defcustom dired-snacks-breadcrumb-spacing 0.2
  "Height of the gap under the breadcrumb, as a fraction of a line."
  :type 'number
  :group 'dired-snacks)

(defcustom dired-snacks-breadcrumb-height 0.95
  "Font size of the breadcrumb, as a fraction of the default."
  :type 'number
  :group 'dired-snacks)

(defun dired-snacks--breadcrumb-segments (dir)
  "Split DIR into breadcrumb segments."
  (let* ((abbr (abbreviate-file-name (directory-file-name dir)))
         (parts (split-string abbr "/" t)))
    (cond
     ((string-prefix-p "~" abbr) (cons dired-snacks-breadcrumb-home (cdr parts)))
     ((string-prefix-p "/" abbr) (cons dired-snacks-breadcrumb-root parts))
     (t parts))))

(defun dired-snacks--breadcrumb ()
  "Return a breadcrumb for the directory at point, or nil."
  (when (derived-mode-p 'dired-mode)
    (let* ((dir (or (ignore-errors (dired-current-directory)) default-directory))
           (height dired-snacks-breadcrumb-height)
           (sep (propertize dired-snacks-breadcrumb-separator
                            'face `(:inherit shadow :height ,height))))
      (concat dired-snacks-breadcrumb-margin
              (mapconcat (lambda (s)
                           (propertize (string-replace "%" "%%" s)
                                       'face `(:inherit dired-header :height ,height)))
                         (dired-snacks--breadcrumb-segments dir)
                         sep)))))

(defun dired-snacks--breadcrumb-decorate ()
  "Hide the directory header and add a gap under the breadcrumb."
  (unless (eq (current-buffer) dired-snacks--find-buffer)
    (remove-overlays (point-min) (point-max) 'dired-snacks--header t)
    (let* ((first (next-single-property-change (point-min) 'dired-filename))
           (end (if first (save-excursion (goto-char first) (pos-bol))
                  (point-max)))
           (ov (make-overlay (point-min) end)))
      (overlay-put ov 'dired-snacks--header t)
      (overlay-put ov 'evaporate t)
      (when dired-snacks-breadcrumb-hide-header
        (overlay-put ov 'invisible 'dired-snacks--header))
      (when (> dired-snacks-breadcrumb-spacing 0)
        (overlay-put ov 'before-string
                     (propertize "\n" 'face `(:height ,dired-snacks-breadcrumb-spacing)))))))

(defun dired-snacks--breadcrumb-setup ()
  "Show the breadcrumb header line and decorate the listing."
  (remove-from-invisibility-spec 'dired-snacks--header)
  (add-to-invisibility-spec 'dired-snacks--header)
  (setq-local header-line-format '(:eval (dired-snacks--breadcrumb)))
  (add-hook 'dired-after-readin-hook #'dired-snacks--breadcrumb-decorate nil t))

(defun dired-snacks--breadcrumb-teardown ()
  "Remove the breadcrumb header line and undo its decorations."
  (remove-hook 'dired-after-readin-hook #'dired-snacks--breadcrumb-decorate t)
  (remove-overlays (point-min) (point-max) 'dired-snacks--header t)
  (remove-from-invisibility-spec 'dired-snacks--header)
  (kill-local-variable 'header-line-format))

;; ===============================================================
;;; split

(defun dired-snacks--windows ()
  "Return the list of windows showing a Dired buffer."
  (seq-filter (lambda (w)
                (eq (buffer-local-value 'major-mode (window-buffer w)) 'dired-mode))
              (window-list)))

(defvar-local dired-snacks--split-pane nil
  "Non-nil in a Dired buffer opened as a split pane.")

(defun dired-snacks-quit ()
  "Close this Dired pane, selecting the other one when there is one."
  (interactive)
  (let ((others (remq (selected-window) (dired-snacks--windows))))
    (if dired-snacks--split-pane
        (kill-current-buffer)
      (quit-window))
    (when-let* ((w (seq-find #'window-live-p others)))
      (select-window w))))

(defun dired-snacks--quit-setup ()
  "Make q close this Dired pane."
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map dired-mode-map)
    (keymap-set map "q" #'dired-snacks-quit)
    (use-local-map map)))

(defun dired-snacks--quit-teardown ()
  "Give the current Dired buffer its usual keymap back."
  (use-local-map dired-mode-map))

(defun dired-snacks--split-mark ()
  "Mark the current buffer as a split pane."
  (setq-local dired-snacks--split-pane t))

;;;###autoload
(defun dired-snacks-split ()
  "Open a second Dired in the current directory, beside this one."
  (interactive)
  (let* ((dir default-directory)
         (win (selected-window))
         (side (window-parameter win 'window-side))
         (buf (let ((dired-buffers nil)) (dired-noselect dir))))
    (with-current-buffer buf (dired-snacks--split-mark))
    (if side
        (let ((display-buffer-overriding-action
               `(display-buffer-in-side-window
                 (side . ,side)
                 (slot . ,(1+ (or (window-parameter win 'window-slot) 0))))))
          (select-window (display-buffer buf)))
      (select-window (split-window-right))
      (switch-to-buffer buf))))

(defun dired-snacks--find-isolated (orig file)
  "Keep Dired panes independent when entering directories.
FILE is the file or directory being visited.  ORIG is the advised
function, called unchanged unless FILE is a directory and more than
one Dired pane is on screen."
  (if (and (file-directory-p file) (cdr (dired-snacks--windows)))
      (let ((dired-buffers nil)
            (pane dired-snacks--split-pane))
        (set-buffer-modified-p nil)
        (dired--find-file #'find-alternate-file file)
        (when pane (dired-snacks--split-mark)))
    (funcall orig file)))

;; ===============================================================
;;; mode-line

(defcustom dired-snacks-mode-line-show-size t
  "When non-nil, show the size of the entry at point."
  :type 'boolean :group 'dired-snacks)

(defcustom dired-snacks-mode-line-show-time t
  "When non-nil, show the modification time of the entry at point."
  :type 'boolean :group 'dired-snacks)

(defcustom dired-snacks-mode-line-show-omit t
  "When non-nil, show the `dired-omit-mode' indicator."
  :type 'boolean :group 'dired-snacks)

(defcustom dired-snacks-mode-line-show-sort t
  "When non-nil, show the sort criterion."
  :type 'boolean :group 'dired-snacks)

(defcustom dired-snacks-mode-line-index-width 7
  "Width reserved for the entry counter, so it never shifts."
  :type 'integer :group 'dired-snacks)

(defcustom dired-snacks-mode-line-size-width 8
  "Width reserved for the entry size, so it never shifts."
  :type 'integer :group 'dired-snacks)

(defcustom dired-snacks-mode-line-time-format "%Y-%m-%d %H:%M"
  "Format of the timestamp shown in the mode line."
  :type 'string :group 'dired-snacks)

(defvar-local dired-snacks--ml-last-file nil
  "File at point after the last command.")

(defvar-local dired-snacks--ml-attr-cache nil
  "Cached attributes of the entry at point.")

(defvar-local dired-snacks--ml-dir-size-cache nil
  "Cached recursive directory sizes, a hash of DIR to (MTIME . SIZE).")

(defvar-local dired-snacks--ml-dir-size-jobs nil
  "Directories with a `du' process in flight.")

(defcustom dired-snacks-mode-line-size-placeholder "…"
  "Text shown while a directory's size is being computed."
  :type 'string :group 'dired-snacks)

(defcustom dired-snacks-mode-line-size-idle-delay 0.2
  "Idle time before a directory's size starts computing."
  :type 'number :group 'dired-snacks)

(defvar-local dired-snacks--ml-dir-size-timer nil
  "Idle timer that starts the pending `du' computation.")

(defvar dired-snacks--ml-du-program 'unset
  "Cached file name of `du', or `unset' before it is looked up.")

(defvar-local dired-snacks--ml-total-cache nil
  "Cached count of the entries in this listing.")

(defvar-local dired-snacks--ml-current-cache nil
  "Cached index of the entry at point.")

(defun dired-snacks--ml-entry-p ()
  "Return non-nil when the current line holds an entry."
  (when-let* ((name (dired-get-filename 'no-dir t)))
    (not (member name '("." "..")))))

(defun dired-snacks--ml-total ()
  "Return the number of visible files and directories."
  (let ((tick (buffer-chars-modified-tick)))
    (unless (eql tick (car dired-snacks--ml-total-cache))
      (setq dired-snacks--ml-total-cache
            (cons tick
                  (save-excursion
                    (goto-char (point-min))
                    (let ((n 0))
                      (while (not (eobp))
                        (when (dired-snacks--ml-entry-p) (setq n (1+ n)))
                        (forward-line 1))
                      n)))))
    (cdr dired-snacks--ml-total-cache)))

(defun dired-snacks--ml-current ()
  "Return the position of the entry at point in the listing."
  (let ((key (cons (pos-bol) (buffer-chars-modified-tick))))
    (unless (equal key (car dired-snacks--ml-current-cache))
      (setq dired-snacks--ml-current-cache
            (cons key
                  (let ((limit (car key)) (n 0))
                    (save-excursion
                      (goto-char (point-min))
                      (while (and (<= (point) limit) (not (eobp)))
                        (when (dired-snacks--ml-entry-p) (setq n (1+ n)))
                        (forward-line 1)))
                    n))))
    (cdr dired-snacks--ml-current-cache)))

(defun dired-snacks--ml-index ()
  "Return the entry counter, as current over total."
  (when (derived-mode-p 'dired-mode)
    (let ((s (concat (number-to-string (dired-snacks--ml-current))
                     "/" (number-to-string (dired-snacks--ml-total)))))
      (concat "  " (string-pad s dired-snacks-mode-line-index-width nil t)))))

(defun dired-snacks--ml-file-attrs ()
  "Return the attributes of the entry at point, or nil."
  (when-let* ((name (and (derived-mode-p 'dired-mode)
                         (not (file-remote-p default-directory))
                         (dired-get-filename nil t))))
    (unless (equal name (car dired-snacks--ml-attr-cache))
      (setq dired-snacks--ml-attr-cache (cons name (file-attributes name))))
    (cdr dired-snacks--ml-attr-cache)))

(defun dired-snacks--ml-du-program ()
  "Return the file name of `du', or nil when it is unavailable."
  (when (eq dired-snacks--ml-du-program 'unset)
    (setq dired-snacks--ml-du-program (executable-find "du")))
  dired-snacks--ml-du-program)

(defun dired-snacks--ml-dir-size-cache-table ()
  "Return this buffer's directory-size cache, creating it if needed."
  (or dired-snacks--ml-dir-size-cache
      (setq dired-snacks--ml-dir-size-cache (make-hash-table :test 'equal))))

(defun dired-snacks--ml-dir-size-jobs-table ()
  "Return this buffer's `du' job table, creating it if needed."
  (or dired-snacks--ml-dir-size-jobs
      (setq dired-snacks--ml-dir-size-jobs (make-hash-table :test 'equal))))

(defun dired-snacks--ml-dir-size-cached (dir mtime)
  "Return DIR's cached size when still fresh for MTIME, else nil."
  (when-let* ((cache dired-snacks--ml-dir-size-cache)
              (hit (gethash dir cache))
              ((time-equal-p (car hit) mtime)))
    (cdr hit)))

(defun dired-snacks--ml-dir-size-start (dir mtime)
  "Spawn an async `du' for DIR, caching its size tagged with MTIME."
  (let* ((dired-buf (current-buffer))
         (out (generate-new-buffer " *dired-snacks-du*"))
         (proc (make-process
                :name "dired-snacks-du"
                :buffer out
                :noquery t
                :connection-type 'pipe
                :command (list (dired-snacks--ml-du-program)
                               "--summarize" "--bytes"
                               (expand-file-name dir))
                :sentinel
                (lambda (proc event)
                  (when (memq (process-status proc) '(exit signal))
                    (let ((size (and (string-prefix-p "finished" event)
                                     (with-current-buffer out
                                       (goto-char (point-min))
                                       (and (re-search-forward
                                             "\\`[[:space:]]*\\([0-9]+\\)" nil t)
                                            (string-to-number (match-string 1)))))))
                      (when (buffer-live-p dired-buf)
                        (with-current-buffer dired-buf
                          (remhash dir (dired-snacks--ml-dir-size-jobs-table))
                          (when size
                            (puthash dir (cons mtime size)
                                     (dired-snacks--ml-dir-size-cache-table)))
                          (force-mode-line-update t)))
                      (when (buffer-live-p out) (kill-buffer out))))))))
    (puthash dir proc (dired-snacks--ml-dir-size-jobs-table))))

(defun dired-snacks--ml-dir-size-schedule (dir mtime)
  "Start DIR's `du' after a short idle, tagging the result with MTIME."
  (when (timerp dired-snacks--ml-dir-size-timer)
    (cancel-timer dired-snacks--ml-dir-size-timer))
  (let ((buf (current-buffer)))
    (setq dired-snacks--ml-dir-size-timer
          (run-with-idle-timer
           dired-snacks-mode-line-size-idle-delay nil
           (lambda ()
             (when (buffer-live-p buf)
               (with-current-buffer buf
                 (unless (or (dired-snacks--ml-dir-size-cached dir mtime)
                             (gethash dir (dired-snacks--ml-dir-size-jobs-table)))
                   (dired-snacks--ml-dir-size-start dir mtime)))))))))

(defun dired-snacks--ml-dir-size-maybe (dir)
  "Schedule a `du' for DIR when it is a directory lacking a fresh size."
  (when (and (dired-snacks--ml-du-program)
             (file-directory-p dir))
    (let ((mtime (file-attribute-modification-time (file-attributes dir))))
      (unless (dired-snacks--ml-dir-size-cached dir mtime)
        (dired-snacks--ml-dir-size-schedule dir mtime)))))

(defun dired-snacks--ml-size ()
  "Return the size of the entry at point, or nil.
Directories are measured recursively."
  (when dired-snacks-mode-line-show-size
    (when-let* ((attrs (dired-snacks--ml-file-attrs)))
      (let* ((dirp (eq (file-attribute-type attrs) t))
             (size (cond
                    ((not dirp) (file-attribute-size attrs))
                    ((not (dired-snacks--ml-du-program))
                     (file-attribute-size attrs))
                    (t (dired-snacks--ml-dir-size-cached
                        (dired-get-filename nil t)
                        (file-attribute-modification-time attrs)))))
             (text (string-pad (if size
                                   (file-size-human-readable size)
                                 dired-snacks-mode-line-size-placeholder)
                               dired-snacks-mode-line-size-width nil t)))
        (concat "  " (propertize text 'face 'shadow))))))

(defun dired-snacks--ml-time ()
  "Return the modification time of the entry at point, or nil."
  (when dired-snacks-mode-line-show-time
    (when-let* ((attrs (dired-snacks--ml-file-attrs)))
      (concat "  " (propertize (format-time-string dired-snacks-mode-line-time-format
                                                   (file-attribute-modification-time attrs))
                               'face 'shadow)))))

(defun dired-snacks--ml-omit ()
  "Return the `dired-omit-mode' indicator, or nil."
  (when (and dired-snacks-mode-line-show-omit (bound-and-true-p dired-omit-mode))
    (propertize "  omit" 'face 'shadow)))

(defun dired-snacks--sort-criterion (switches)
  "Return the sort criterion named by the `ls' SWITCHES."
  (let ((parts (split-string switches)))
    (cond
     ((member "--sort=none" parts) "none")
     ((member "--sort=time" parts) "time")
     ((member "--sort=size" parts) "size")
     ((member "--sort=version" parts) "version")
     ((member "--sort=extension" parts) "type")
     ((member "--sort=width" parts) "width")
     ((string-match-p "\\(?:\\`\\| \\)-[a-zA-Z]*t" switches) "time")
     ((string-match-p "\\(?:\\`\\| \\)-[a-zA-Z]*S" switches) "size")
     ((string-match-p "\\(?:\\`\\| \\)-[a-zA-Z]*X" switches) "type")
     ((string-match-p "\\(?:\\`\\| \\)-[a-zA-Z]*v" switches) "version")
     (t "name"))))

(defun dired-snacks--ml-sort ()
  "Return the sort criterion of this listing, or nil."
  (when (and dired-snacks-mode-line-show-sort (derived-mode-p 'dired-mode))
    (concat "  " (propertize (dired-snacks--sort-criterion dired-actual-switches)
                             'face 'shadow))))

(defun dired-snacks--ml-width (&rest segments)
  "Return the total display width of SEGMENTS."
  (apply #'+ (mapcar #'string-width (delq nil segments))))

(defun dired-snacks--ml-right ()
  "Return the right-hand segments of the mode line.
The omit indicator and the sort criterion are dropped when space runs out."
  (when (derived-mode-p 'dired-mode)
    (let ((size (dired-snacks--ml-size))
          (time (dired-snacks--ml-time))
          (crit (dired-snacks--ml-sort))
          (omit (dired-snacks--ml-omit))
          (index (dired-snacks--ml-index))
          (room (- (window-width)
                   (+ 10 (max 12 (string-width (buffer-name)))))))
      (when (> (dired-snacks--ml-width size time crit omit index) room)
        (setq omit nil))
      (when (> (dired-snacks--ml-width size time crit omit index) room)
        (setq crit nil))
      (concat size time crit omit index))))

(defcustom dired-snacks-mode-line-format
  '("%e  "
    (:propertize " " display (raise +0.1)) ;; top padding
    (:propertize " " display (raise -0.1)) ;; bottom padding
    mode-line-modified
    "  "
    mode-line-buffer-identification
    mode-line-format-right-align
    (:eval (dired-snacks--ml-right))
    "  ")
  "The mode line shown in Dired buffers."
  :type 'sexp :group 'dired-snacks)

(defun dired-snacks--ml-refresh ()
  "Refresh the mode line when point moves to another entry."
  (let ((name (dired-get-filename nil t)))
    (unless (equal name dired-snacks--ml-last-file)
      (setq dired-snacks--ml-last-file name)
      (when (and dired-snacks-mode-line-show-size name)
        (dired-snacks--ml-dir-size-maybe name))
      (force-mode-line-update))))

(defun dired-snacks--ml-setup ()
  "Give this Dired buffer its own mode line."
  (setq-local mode-line-format dired-snacks-mode-line-format)
  (add-hook 'post-command-hook #'dired-snacks--ml-refresh nil t))

(defun dired-snacks--ml-teardown ()
  "Give this Dired buffer the usual mode line back."
  (when (timerp dired-snacks--ml-dir-size-timer)
    (cancel-timer dired-snacks--ml-dir-size-timer))
  (kill-local-variable 'mode-line-format)
  (remove-hook 'post-command-hook #'dired-snacks--ml-refresh t)
  (force-mode-line-update))

(defun dired-snacks--map-buffers (fn)
  "Call FN in every live Dired buffer."
  (dolist (buf (buffer-list))
    (with-current-buffer buf
      (when (derived-mode-p 'dired-mode) (funcall fn)))))

;; ===============================================================
;;; minor mode

(defun dired-snacks--setup ()
  "Install the buffer-local features in the current Dired buffer."
  (dired-snacks--subtree-setup)
  (dired-snacks--breadcrumb-setup)
  (dired-snacks--breadcrumb-decorate)
  (dired-snacks--ml-setup)
  (dired-snacks--quit-setup))

(defun dired-snacks--teardown ()
  "Remove the buffer-local features from the current Dired buffer."
  (dired-snacks--subtree-teardown)
  (dired-snacks--breadcrumb-teardown)
  (dired-snacks--ml-teardown)
  (dired-snacks--quit-teardown))

(defun dired-snacks--enable ()
  "Install the passive features."
  (add-hook 'find-file-hook #'dired-snacks--zoxide-add-default-directory)
  (add-hook 'dired-mode-hook #'dired-snacks--zoxide-add-default-directory)
  (add-hook 'dired-mode-hook #'dired-snacks--subtree-setup)
  (add-hook 'dired-mode-hook #'dired-snacks--breadcrumb-setup)
  (add-hook 'dired-mode-hook #'dired-snacks--ml-setup)
  (add-hook 'dired-mode-hook #'dired-snacks--quit-setup)
  (add-hook 'dired-snacks-subtree-after-change-hook #'dired-snacks--subtree-refresh-icons)
  (advice-add 'dired--find-possibly-alternative-file :around #'dired-snacks--find-isolated)
  (dired-snacks--map-buffers #'dired-snacks--setup))

(defun dired-snacks--disable ()
  "Remove the passive features."
  (remove-hook 'find-file-hook #'dired-snacks--zoxide-add-default-directory)
  (remove-hook 'dired-mode-hook #'dired-snacks--zoxide-add-default-directory)
  (remove-hook 'dired-mode-hook #'dired-snacks--subtree-setup)
  (remove-hook 'dired-mode-hook #'dired-snacks--breadcrumb-setup)
  (remove-hook 'dired-mode-hook #'dired-snacks--ml-setup)
  (remove-hook 'dired-mode-hook #'dired-snacks--quit-setup)
  (remove-hook 'dired-snacks-subtree-after-change-hook #'dired-snacks--subtree-refresh-icons)
  (advice-remove 'dired--find-possibly-alternative-file #'dired-snacks--find-isolated)
  (dired-snacks--map-buffers #'dired-snacks--teardown))

;;;###autoload
(define-minor-mode dired-snacks-mode
  "Toggle the passive Dired enhancements globally.
The commands work on their own; this mode adds the breadcrumb, the
Dired mode line, the split panes and the zoxide history."
  :global t
  :group 'dired-snacks
  (if dired-snacks-mode
      (dired-snacks--enable)
    (dired-snacks--disable)))

(provide 'dired-snacks)
;;; dired-snacks.el ends here
