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
;; paste      - clip files, then copy, move or link them elsewhere
;; subtree    - expand directories inline without leaving the buffer
;; vc         - mark the Git state of each entry in the fringe
;; breadcrumb - show the current directory in the header line
;; split      - second Dired pane with independent navigation
;; mode-line  - per-buffer mode line with size, time, sort, position
;; columns    - size, time and permissions at the right edge
;; copy-uri   - copy files as file:// URIs to the clipboard

;;; Code:

(eval-when-compile
  (require 'cl-lib)
  (require 'cond-star)
  (require 'dired)
  (require 'dired-aux)
  (require 'dired-x)
  (require 'browse-url)
  (require 'completion-preview)
  (require 'filenotify))

;; `with-work-buffer' needs subr-x at run time.
(require 'subr-x)

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
(declare-function dired-change-marks "dired")
(declare-function dired-find-file "dired")
(declare-function dired-goto-file "dired")
(declare-function dired-goto-next-file "dired")
(declare-function dired-advertise "dired")
(declare-function dired-hide-details-mode "dired")
(declare-function dired-add-file "dired-aux")
(declare-function dired-remove-file "dired-aux")
(declare-function dired-relist-file "dired-aux")
(declare-function dired-rename-subdir "dired-aux")
(declare-function dired-query "dired-aux")
(declare-function dired-log "dired")
(declare-function dired-log-summary "dired")
(declare-function dired-kill-subdir "dired-aux")
(declare-function dired-hide-subdir "dired-aux")
(declare-function dired-omit-mode "dired-x")
(declare-function dired-omit-expunge "dired-x")
(declare-function browse-url-file-url "browse-url")
(declare-function file-notify-add-watch "filenotify")
(declare-function file-notify-rm-watch "filenotify")
(declare-function file-notify-valid-p "filenotify")

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
          (with-work-buffer
            (when (zerop (call-process "zoxide" nil t nil "query" "--" input))
              (let ((dir (string-trim (buffer-string))))
                (and (file-directory-p dir) dir)))))))))

(defvar dired-snacks--zoxide-last-dir nil
  "Directory most recently registered in the zoxide database.")

(defun dired-snacks--zoxide-add (dir)
  "Register DIR in the zoxide database, unless it was the last one added."
  (when (and dir (executable-find "zoxide"))
    (let ((dir (file-name-as-directory (expand-file-name dir))))
      (unless (equal dir dired-snacks--zoxide-last-dir)
        (setq dired-snacks--zoxide-last-dir dir)
        (call-process "zoxide" nil 0 nil "add" "--" dir)))))

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
  "Completion-at-point function for literal directory names."
  (list (minibuffer-prompt-end) (point) #'completion-file-name-table
        :predicate #'file-directory-p))

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
  ;; The setup hook sets `completion-preview' options, so the library has to
  ;; be loaded before that, not by the autoloaded mode command.
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
  :type '(repeat string))

(defcustom dired-snacks-find-debounce 0.15
  "Seconds of idle input before the live search refreshes."
  :type 'number)

(defcustom dired-snacks-find-max-results 2000
  "Maximum number of results shown by a search."
  :type 'natnum)

(defcustom dired-snacks-find-min-length 2
  "Minimum number of characters before a search runs."
  :type 'natnum)

(defcustom dired-snacks-find-group-by-directory t
  "When non-nil, group search results by directory, else list them together."
  :type 'boolean)

(defcustom dired-snacks-find-show-hidden nil
  "When non-nil, show hidden files in the find buffer."
  :type 'boolean)

(defvar dired-snacks--find-proc nil
  "Current live-search `fd' process, or nil.")

(defvar dired-snacks--find-timer nil
  "Timer used to debounce live search updates.")

(defvar dired-snacks--find-buffer nil
  "Live search results buffer, or nil.")

(defvar dired-snacks--find-root nil
  "Root directory of the current search.")

(defvar dired-snacks--find-query nil
  "Query of the latest search started.")

(defvar dired-snacks--find-results nil
  "Last complete `fd' results, as (QUERY . ENTRIES), or nil.")

(defun dired-snacks--find-case-fold-p (query)
  "Return non-nil if QUERY should match regardless of case."
  (let ((case-fold-search nil))
    (not (string-match-p "[[:upper:]]" query))))

(defun dired-snacks--find-fd-args (query dir)
  "Return the `fd' arguments to search for every word of QUERY under DIR."
  (let ((terms (split-string query)))
    (append `("--color=never" "--list-details" "--no-ignore"
              "--type" "f" "--fixed-strings"
              ,(if (dired-snacks--find-case-fold-p query)
                   "--ignore-case"
                 "--case-sensitive")
              "--batch-size"
              ,(number-to-string (1+ dired-snacks-find-max-results)))
            (and dired-snacks-find-show-hidden '("--hidden"))
            (mapcan (lambda (d) (list "--exclude" d))
                    dired-snacks-find-prune-dirs)
            (mapcan (lambda (term) (list "--and" term)) (cdr terms))
            (list "--" (car terms) (expand-file-name dir)))))

(defun dired-snacks--find-parse (line)
  "Parse an `fd --list-details' LINE into (DIR BASENAME DETAILS)."
  (when (string-match "\\(/.*\\)\\'" line)
    (let ((file (match-string 1 line)))
      (list (file-name-directory file)
            (file-name-nondirectory file)
            (substring line 0 (match-beginning 1))))))

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

(defun dired-snacks--find-insert-groups (groups)
  "Insert GROUPS as Dired subdir listings."
  (let ((first t))
    (dolist (group groups)
      (if first (setq first nil) (insert "\n"))
      (insert "  " (directory-file-name (car group)) ":\n")
      (insert (format "  total used in directory %d\n" (length (cdr group))))
      (dolist (entry (cdr group))
        (insert "  " (nth 2 entry) (nth 1 entry) "\n")))))

(defun dired-snacks--find-insert-flat (root entries)
  "Insert ENTRIES as one Dired listing of ROOT, sorted by file name."
  (let ((lines (mapcar (lambda (entry)
                         (cons (file-relative-name (concat (car entry) (nth 1 entry)) root)
                               (nth 2 entry)))
                       entries)))
    (insert "  " (directory-file-name root) ":\n")
    (insert (format "  total used in directory %d\n" (length lines)))
    (pcase-dolist (`(,name . ,details) (sort lines :key #'car))
      (insert "  " details name "\n"))))

(defun dired-snacks--find-insert-listing (root)
  "Insert the contents of ROOT as a Dired listing."
  (let ((beg (point))
        (end (point-marker)))
    (dired-insert-directory root dired-actual-switches nil nil t)
    (set-marker end (point))
    (dired-snacks--subtree-delete-dots beg end (not dired-snacks-find-show-hidden))
    (set-marker end nil)))

(defun dired-snacks--find-render (root entries)
  "Render ENTRIES from `dired-snacks--find-parse' under ROOT as a Dired buffer.
If ENTRIES is `listing', show the contents of ROOT instead."
  (when (buffer-live-p dired-snacks--find-buffer)
    (with-current-buffer dired-snacks--find-buffer
      (let ((inhibit-read-only t))
        (widen)
        (remove-overlays nil nil 'dired-snacks--find-icon t)
        (erase-buffer)
        (setq-local default-directory (file-name-as-directory root))
        (cond
         ((eq entries 'listing)
          (dired-snacks--find-insert-listing root))
         ((null entries)
          (insert "  " (directory-file-name root) ":\n"
                  "  total used in directory 0\n\n"
                  "  (no matches)\n"))
         (dired-snacks-find-group-by-directory
          (dired-snacks--find-insert-groups (seq-group-by #'car entries)))
         (t (dired-snacks--find-insert-flat root entries)))
        (dired-build-subdir-alist)
        (dired-insert-set-properties (point-min) (point-max))
        (run-hooks 'dired-after-readin-hook)
        (dired-snacks--find-icon-subdirs)
        (goto-char (point-min))
        (when (and (consp entries) (null (cdr entries)))
          (dired-goto-next-file))))))

(defun dired-snacks--find-show (query entries)
  "Render ENTRIES, the `fd' results for QUERY, up to the maximum."
  (let ((max dired-snacks-find-max-results))
    (if (length> entries max)
        (progn
          (setq dired-snacks--find-results nil
                entries (take max entries))
          (message "find: showing the first %d results" max))
      (setq dired-snacks--find-results (cons query entries)))
    (dired-snacks--find-render dired-snacks--find-root entries)))

(defun dired-snacks--find-refinable-p (query)
  "Return non-nil if the last `fd' results include every match for QUERY."
  (when-let* ((last (car dired-snacks--find-results)))
    (let ((terms (split-string (if (dired-snacks--find-case-fold-p last)
                                   (downcase query)
                                 query))))
      (seq-every-p (lambda (old)
                     (seq-some (lambda (term) (string-search old term)) terms))
                   (split-string last)))))

(defun dired-snacks--find-refine (query)
  "Return the entries of the last `fd' results whose names match QUERY."
  (let ((case-fold-search (dired-snacks--find-case-fold-p query))
        (regexps (mapcar #'regexp-quote (split-string query))))
    (seq-filter (lambda (entry)
                  (let ((name (nth 1 entry)))
                    (seq-every-p (lambda (regexp) (string-match-p regexp name))
                                 regexps)))
                (cdr dired-snacks--find-results))))

(defun dired-snacks--find-filter (proc output)
  "Insert OUTPUT of PROC, stopping it once there are more results than shown."
  (when (buffer-live-p (process-buffer proc))
    (with-current-buffer (process-buffer proc)
      (goto-char (point-max))
      (insert output)
      (when (save-excursion
              (goto-char (point-min))
              (and (zerop (forward-line dired-snacks-find-max-results))
                   (search-forward "\n" nil t)))
        (process-put proc 'dired-snacks--cut t)
        (delete-process proc)))))

(defun dired-snacks--find-sentinel (proc event query)
  "Show the results of PROC, a search for QUERY, when EVENT ends it.
Drop them if a newer search has started."
  (when-let* ((_ (memq (process-status proc) '(exit signal)))
              (buf (process-buffer proc))
              (_ (buffer-live-p buf)))
    (when (and (or (string-prefix-p "finished" event)
                   (process-get proc 'dired-snacks--cut))
               (equal query dired-snacks--find-query))
      (let ((entries (with-current-buffer buf
                       (seq-keep #'dired-snacks--find-parse
                                 (split-string (buffer-string) "\n" t)))))
        (with-demoted-errors "find render error: %S"
          (dired-snacks--find-show query entries))))
    (kill-buffer buf)))

(defun dired-snacks--find-dispatch (query)
  "Show the results for QUERY, replacing any other running search."
  (unless (equal query dired-snacks--find-query)
    (setq dired-snacks--find-query query)
    (when (and dired-snacks--find-proc
               (process-live-p dired-snacks--find-proc))
      (delete-process dired-snacks--find-proc))
    (cond
     ((let ((input (string-trim query)))
        (or (string-empty-p input)
            (length< input dired-snacks-find-min-length)))
      (dired-snacks--find-render dired-snacks--find-root 'listing))
     ((dired-snacks--find-refinable-p query)
      (dired-snacks--find-render dired-snacks--find-root
                                 (dired-snacks--find-refine query)))
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
                   :filter #'dired-snacks--find-filter
                   :sentinel (lambda (proc event)
                               (dired-snacks--find-sentinel proc event query)))))
        (setq dired-snacks--find-proc proc))))))

(defun dired-snacks--find-schedule (&rest _)
  "Schedule a search after minibuffer input settles."
  (let ((query (minibuffer-contents-no-properties)))
    (when (timerp dired-snacks--find-timer)
      (cancel-timer dired-snacks--find-timer))
    (setq dired-snacks--find-timer
          (run-with-timer dired-snacks-find-debounce nil
                          #'dired-snacks--find-dispatch query))))

(defun dired-snacks--find-cleanup (&optional keep-proc)
  "Tear down the live-search timer and, unless KEEP-PROC, the process."
  (when (timerp dired-snacks--find-timer)
    (cancel-timer dired-snacks--find-timer))
  (unless keep-proc
    (when (and dired-snacks--find-proc
               (process-live-p dired-snacks--find-proc))
      (delete-process dired-snacks--find-proc))
    (setq dired-snacks--find-proc nil))
  (setq dired-snacks--find-timer nil))

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
    (dired-snacks--find-cleanup)
    (setq dired-snacks--find-buffer buf
          dired-snacks--find-root root
          dired-snacks--find-query nil
          dired-snacks--find-results nil)
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (setq-local default-directory (file-name-as-directory root))
        (let ((dired-buffers nil)) (dired-mode root)))
      (setq-local dired-omit-mode nil)
      (let ((map (make-sparse-keymap)))
        (set-keymap-parent map dired-mode-map)
        (keymap-set map "q" #'kill-current-buffer)
        (keymap-set map "TAB" #'dired-hide-subdir)
        (use-local-map map)))
    (dired-snacks--find-dispatch "")
    (let ((display-buffer-overriding-action
           (and side `(display-buffer-in-side-window
                       (side . ,side) (slot . ,(or slot 0))))))
      (display-buffer buf '(display-buffer-same-window)))
    (let ((query nil))
      (unwind-protect
          (progn
            (setq query
                  (condition-case nil
                      (minibuffer-with-setup-hook
                          (lambda ()
                            (add-hook 'after-change-functions
                                      #'dired-snacks--find-schedule nil t))
                        (read-from-minibuffer "Find files: "))
                    (quit nil)))
            (if query
                (when (buffer-live-p buf)
                  (dired-snacks--find-dispatch query)
                  (if-let* ((win (get-buffer-window buf)))
                      (select-window win)
                    (pop-to-buffer buf)))
              (when (buffer-live-p buf) (kill-buffer buf))))
        (dired-snacks--find-cleanup query)))))

;; ===============================================================
;;; open

(defcustom dired-snacks-open-full-window nil
  "When non-nil, opening a file kills the Dired buffer and fills the window."
  :type 'boolean)

(defun dired-snacks--kde-session-p ()
  "Return non-nil in a KDE Plasma session."
  (or (and (getenv "KDE_FULL_SESSION") t)
      (and (member "KDE" (split-string (or (getenv "XDG_CURRENT_DESKTOP") "")
                                       ":" t))
           t)))

(defun dired-snacks--system-openers ()
  "Return the default opener chain for this desktop session.
Under KDE, `kde-open' comes first, so files are opened through KIO."
  (append (and (dired-snacks--kde-session-p) '(("kde-open")))
          '(("gio" "open")
            ("xdg-open"))))

(defcustom dired-snacks-external-openers (dired-snacks--system-openers)
  "Programs tried, in order, to open a file externally.
Each entry is (PROGRAM ARG...); the first available PROGRAM is used."
  :type '(repeat (cons string (repeat string))))

(defcustom dired-snacks-single-file-openers '("xdg-open")
  "Openers that accept only one file per invocation.
These are called once per file instead of once for the whole batch."
  :type '(repeat string))

(defcustom dired-snacks-external-app-alist nil
  "File extensions to open in an external application.
Each entry is (EXTENSIONS PROGRAM ARG...), where EXTENSIONS is a
string or list of strings.  PROGRAM opens those files; when
omitted, `dired-snacks-external-openers' is used instead."
  :type '(repeat (cons (choice string (repeat string))
                       (repeat string))))

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

(defun dired-snacks--call-opener (opener files)
  "Open FILES with OPENER, as (PROGRAM ARG...).
Openers in `dired-snacks-single-file-openers' are called once per file."
  (pcase-let ((`(,program . ,args) opener))
    (dolist (batch (if (member program dired-snacks-single-file-openers)
                       (mapcar #'list files)
                     (list files)))
      (apply #'call-process program nil 0 nil (append args batch)))))

(defun dired-snacks--open-external (files)
  "Open each of FILES in its external application.
Files sharing an opener are passed together in one call."
  (let ((groups nil))
    (dolist (file files)
      (if-let* ((opener (dired-snacks--opener-for-file file)))
          (push (expand-file-name file) (alist-get opener groups nil nil #'equal))
        (user-error "No external opener found; install glib2 (gio) or xdg-utils")))
    (pcase-dolist (`(,opener . ,names) groups)
      (dired-snacks--call-opener opener (nreverse names)))))

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
      (let ((buf (find-file-noselect file)))
        (kill-buffer (current-buffer))
        (switch-to-buffer buf)))
     (t
      (dired-find-file)))))

;; ===============================================================
;;; duplicate

(defun dired-snacks--numbered-stem (base ext dir)
  "Return BASE without a trailing -N if that name, plus EXT, exists in DIR."
  (let ((stem (and (string-match "\\`\\(.+?\\)-[0-9]+\\'" base)
                   (match-string 1 base))))
    (if (and stem (file-exists-p
                   (expand-file-name (concat stem (and ext (concat "." ext))) dir)))
        stem
      base)))

(defun dired-snacks--unique-copy-name (file)
  "Return an absolute, free name for a numbered copy of FILE."
  (let* ((file (directory-file-name (expand-file-name file)))
         (dir  (file-name-directory file))
         (node (file-name-nondirectory file))
         (ext  (unless (file-directory-p file) (file-name-extension node)))
         (base (if ext (file-name-sans-extension node) node))
         (stem (dired-snacks--numbered-stem base ext dir))
         (n 1)
         candidate)
    (while (progn
             (setq candidate
                   (expand-file-name
                    (concat stem "-" (number-to-string n)
                            (and ext (concat "." ext)))
                    dir))
             (file-exists-p candidate))
      (incf n))
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
  (let ((copies (mapcar #'dired-snacks--duplicate-file (dired-get-marked-files))))
    (when copies
      (dired-goto-file (car copies))
      (message "Duplicated %d file%s"
               (length copies) (if (length= copies 1) "" "s")))))

;; ===============================================================
;;; paste

(defconst dired-snacks--paste-operations
  '((copy       "Copy"             "cp" "-a")
    (move       "Move"             "mv")
    (symlink    "Symlink"          "ln" "-sf")
    (relsymlink "Relative symlink" "ln" "-srf")
    (hardlink   "Hardlink"         "ln" "-f"))
  "Paste operations, as (OP LABEL PROGRAM ARG...).")

(defvar dired-snacks--clipped nil
  "Files clipped for a later paste.")

(defvar dired-snacks--paste-query nil
  "Answer to the overwrite query, for `dired-query'.")

(defvar dired-snacks--paste-backup-query nil
  "Answer to the backup query, for `dired-query'.")

(cl-defstruct dired-snacks--paste-task
  "A paste running in the background."
  op jobs total failures proc cancelled)

(defvar dired-snacks--paste-tasks nil
  "Pastes running in the background, oldest first.")

;;;###autoload
(defun dired-snacks-clip (&optional replace)
  "Add the marked files, or the file at point, to the files to paste.
With prefix argument REPLACE, clip only these files."
  (interactive "P" dired-mode)
  (let ((files (or (dired-get-marked-files) (user-error "No file to clip"))))
    (setq dired-snacks--clipped
          (if replace files (seq-union dired-snacks--clipped files)))
    (dired-change-marks dired-marker-char ?\s)
    (force-mode-line-update t)
    (message "%d file%s to paste" (length dired-snacks--clipped)
             (if (length= dired-snacks--clipped 1) "" "s"))))

;;;###autoload
(defun dired-snacks-clip-clear ()
  "Forget the files to paste."
  (interactive)
  (unless dired-snacks--clipped
    (user-error "No files to paste"))
  (let ((count (length dired-snacks--clipped)))
    (setq dired-snacks--clipped nil)
    (force-mode-line-update t)
    (message "Cleared %d file%s to paste" count (if (= count 1) "" "s"))))

(defun dired-snacks--paste-label (op)
  "Return the name of the paste operation OP."
  (cadr (assq op dired-snacks--paste-operations)))

(defun dired-snacks--paste-progress (task)
  "Return the progress of TASK, such as \"Copy 3/10\"."
  (let ((total (dired-snacks--paste-task-total task)))
    (format "%s %d/%d"
            (dired-snacks--paste-label (dired-snacks--paste-task-op task))
            (- total (length (dired-snacks--paste-task-jobs task)))
            total)))

(defun dired-snacks--paste-command (op from to)
  "Return the command that applies OP to FROM, creating TO."
  (append (cddr (assq op dired-snacks--paste-operations))
          (list "-T" "--" from to)))

(defun dired-snacks--paste-jobs (op dir)
  "Return the jobs for pasting the clipped files into DIR with OP."
  (let ((dired-snacks--paste-query nil)
        (dired-snacks--paste-backup-query nil))
    (seq-keep
     (lambda (from)
       (let ((to (expand-file-name (file-name-nondirectory from) dir)))
         (cond
          ((equal from to)
           (unless (eq op 'move)
             (list from (dired-snacks--unique-copy-name from) nil)))
          ((not (or (file-exists-p to) (file-symlink-p to)))
           (list from to nil))
          ((dired-query 'dired-snacks--paste-query "Overwrite `%s'?" to)
           (list from to
                 (and dired-backup-overwrite
                      (or (eq dired-backup-overwrite 'always)
                          (dired-query 'dired-snacks--paste-backup-query
                                       "Make backup for existing file `%s'?" to))))))))
     dired-snacks--clipped)))

(defun dired-snacks--paste-update (op from to)
  "Bring the buffers up to date after OP created TO from FROM."
  (dired-remove-file to)
  (pcase op
    ('move
     (dired-remove-file from)
     (if (file-directory-p to)
         (dired-rename-subdir from to)
       (when-let* ((buffer (get-file-buffer from)))
         (with-current-buffer buffer
           (set-visited-file-name to nil t)))))
    ('hardlink
     (dired-relist-file from)))
  (dired-add-file to)
  (dired-snacks--subtree-prune-visible))

(defun dired-snacks--paste-report (task)
  "Report the outcome of TASK."
  (let* ((op (dired-snacks--paste-task-op task))
         (label (dired-snacks--paste-label op))
         (total (dired-snacks--paste-task-total task))
         (failures (dired-snacks--paste-task-failures task))
         (plural (if (= total 1) "" "s")))
    (cond
     ((dired-snacks--paste-task-cancelled task)
      (let ((summary (format "%s: cancelled after %d of %d file%s" label
                             (- total (length (dired-snacks--paste-task-jobs task)))
                             total plural)))
        (if (eq op 'move)
            (dired-log-summary summary nil)
          (message "%s" summary))))
     (failures
      (dired-log-summary (format "%s: %d of %d file%s failed" label
                                 (length failures) total plural)
                         (mapcar #'file-name-nondirectory (reverse failures))))
     (t
      (message "%s: %d file%s done" label total plural)))))

(defun dired-snacks--paste-restore (to backup)
  "Move BACKUP back to TO, unless something took its place."
  (when backup
    (if (or (file-exists-p to) (file-symlink-p to))
        (dired-log "Kept the old `%s' as `%s'\n" to backup)
      (rename-file backup to)
      (dired-remove-file backup)
      (dired-relist-file to))))

(defun dired-snacks--paste-discard (op from to new backup)
  "Clean up the interrupted job of OP from FROM to TO, using NEW and BACKUP."
  (pcase op
    ('copy
     (when (or new backup)
       (if (and (file-directory-p to) (not (file-symlink-p to)))
           (delete-directory to t)
         (delete-file to))
       (dired-remove-file to)))
    ('move
     (dired-log "Move `%s' to `%s' was interrupted, check both\n" from to)))
  (dired-snacks--paste-restore to backup))

(defun dired-snacks--paste-sentinel (proc event task new backup)
  "Record how PROC, the first job of TASK, ended with EVENT, then go on."
  (unless (process-live-p proc)
    (pcase-let ((`(,from ,to) (car (dired-snacks--paste-task-jobs task)))
                (op (dired-snacks--paste-task-op task))
                (output (with-current-buffer (process-buffer proc)
                          (buffer-string))))
      (kill-buffer (process-buffer proc))
      (if (eq (process-status proc) 'signal)
          (progn
            (setf (dired-snacks--paste-task-cancelled task) t)
            (with-demoted-errors "dired-snacks: %S"
              (dired-snacks--paste-discard op from to new backup)))
        (pop (dired-snacks--paste-task-jobs task))
        (if (zerop (process-exit-status proc))
            (with-demoted-errors "dired-snacks: %S"
              (dired-snacks--paste-update op from to))
          (push from (dired-snacks--paste-task-failures task))
          (dired-log "%s `%s' to `%s' failed (%s):\n%s\n"
                     (dired-snacks--paste-label op) from to (string-trim event) output)
          (with-demoted-errors "dired-snacks: %S"
            (dired-snacks--paste-restore to backup))))
      (dired-snacks--paste-next task))))

(defun dired-snacks--paste-start (task job)
  "Start JOB of TASK and return its process."
  (pcase-let* ((`(,from ,to ,backup) job)
               (new (not (or (file-exists-p to) (file-symlink-p to))))
               (backup (and backup (not new) (car (find-backup-file-name to)))))
    (when backup
      (rename-file to backup t)
      (dired-relist-file backup))
    (let ((default-directory "/"))
      (make-process
       :name "dired-snacks-paste"
       :buffer (generate-new-buffer " *dired-snacks-paste*")
       :command (dired-snacks--paste-command (dired-snacks--paste-task-op task) from to)
       :connection-type 'pipe
       :sentinel (lambda (proc event)
                   (dired-snacks--paste-sentinel proc event task new backup))))))

(defun dired-snacks--paste-next (task)
  "Start the next job of TASK, or report on TASK when none is left."
  (if-let* ((_ (not (dired-snacks--paste-task-cancelled task)))
            (job (car (dired-snacks--paste-task-jobs task))))
      (condition-case err
          (setf (dired-snacks--paste-task-proc task)
                (dired-snacks--paste-start task job))
        (file-error
         (pop (dired-snacks--paste-task-jobs task))
         (push (car job) (dired-snacks--paste-task-failures task))
         (dired-log "%s `%s' to `%s' failed:\n%s\n"
                    (dired-snacks--paste-label (dired-snacks--paste-task-op task))
                    (car job) (cadr job) (error-message-string err))
         (dired-snacks--paste-next task)))
    (setq dired-snacks--paste-tasks (delq task dired-snacks--paste-tasks))
    (dired-snacks--paste-report task))
  (dired-snacks--mode-line-animate-pastes))

(defun dired-snacks--paste (op)
  "Paste the clipped files into the current directory with OP."
  (require 'dired-aux)
  (let ((dir (dired-current-directory)))
    (unless dired-snacks--clipped
      (user-error "No files to paste"))
    (when (seq-some #'file-remote-p (cons dir dired-snacks--clipped))
      (user-error "Cannot paste remote files"))
    (if-let* ((jobs (dired-snacks--paste-jobs op dir)))
        (let ((task (make-dired-snacks--paste-task
                     :op op :jobs jobs :total (length jobs))))
          (setq dired-snacks--clipped nil
                dired-snacks--paste-tasks (append dired-snacks--paste-tasks (list task)))
          (message "%s: %d file%s in progress" (dired-snacks--paste-label op)
                   (length jobs) (if (length= jobs 1) "" "s"))
          (dired-snacks--paste-next task))
      (message "Nothing pasted"))))

;;;###autoload
(defun dired-snacks-paste ()
  "Copy the clipped files into the current directory."
  (interactive nil dired-mode)
  (dired-snacks--paste 'copy))

;;;###autoload
(defun dired-snacks-paste-move ()
  "Move the clipped files into the current directory."
  (interactive nil dired-mode)
  (dired-snacks--paste 'move))

;;;###autoload
(defun dired-snacks-paste-symlink ()
  "Make symbolic links to the clipped files in the current directory."
  (interactive nil dired-mode)
  (dired-snacks--paste 'symlink))

;;;###autoload
(defun dired-snacks-paste-relsymlink ()
  "Make relative symbolic links to the clipped files in the current directory."
  (interactive nil dired-mode)
  (dired-snacks--paste 'relsymlink))

;;;###autoload
(defun dired-snacks-paste-hardlink ()
  "Make hard links to the clipped files in the current directory."
  (interactive nil dired-mode)
  (dired-snacks--paste 'hardlink))

;;;###autoload
(defun dired-snacks-paste-cancel ()
  "Cancel the pastes running in the background."
  (interactive)
  (unless dired-snacks--paste-tasks
    (user-error "No paste is running"))
  (dolist (task (copy-sequence dired-snacks--paste-tasks))
    (setf (dired-snacks--paste-task-cancelled task) t)
    (delete-process (dired-snacks--paste-task-proc task))))

;; ===============================================================
;;; subtree

(defcustom dired-snacks-subtree-indicators '("+ " . "- ")
  "Strings shown before directories, as (COLLAPSED . EXPANDED)."
  :type '(cons (string :tag "Collapsed") (string :tag "Expanded")))

(defcustom dired-snacks-subtree-after-change-hook nil
  "Hook run after a subtree is expanded or collapsed."
  :type 'hook)

(defface dired-snacks-subtree-indicator '((t :inherit shadow))
  "Face for the subtree indicators.")

(defface dired-snacks-subtree-guide '((t :inherit shadow :inverse-video t))
  "Face for the subtree guide lines.")

(defvar-local dired-snacks--subtree-overlays nil
  "Subtree overlays in this buffer.")

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

(defun dired-snacks--subtree-line-prefix (depth)
  "Return the `line-prefix' for a subtree at DEPTH.
Each level is two columns wide, with a line under the parent's indicator."
  (mapconcat
   (lambda (level)
     (concat
      (propertize " " 'display `(space :align-to (,(+ (* 2 level) 1.5) . width)))
      (propertize " " 'display '(space :width (1)) 'face 'dired-snacks-subtree-guide)
      (propertize " " 'display `(space :align-to (,(* 2 (1+ level)) . width)))))
   (number-sequence 0 (1- depth))))

(defun dired-snacks--subtree-dot-p ()
  "Return non-nil if the current line lists the . or .. entry."
  (member (dired-get-filename 'no-dir t) '("." "..")))

(defun dired-snacks--subtree-directory-p ()
  "Return non-nil if the current line lists a directory that can be expanded."
  (and (not (dired-snacks--subtree-dot-p))
       (save-excursion
         (beginning-of-line)
         (or (looking-at-p dired-re-dir)
             (and (looking-at-p dired-re-sym)
                  (file-directory-p (dired-get-filename nil t)))))))

(defun dired-snacks--subtree-draw-indicators (beg end)
  "Draw the subtree indicators on the lines between BEG and END."
  (remove-overlays beg end 'dired-snacks--subtree-indicator t)
  (let ((blank (make-string (string-width (car dired-snacks-subtree-indicators)) ?\s)))
    (save-excursion
      (goto-char beg)
      (while (< (point) end)
        (when-let* ((pos (dired-move-to-filename)))
          (let ((indicator (cond ((not (dired-snacks--subtree-directory-p)) blank)
                                 ((dired-snacks--subtree-child-overlay)
                                  (cdr dired-snacks-subtree-indicators))
                                 (t (car dired-snacks-subtree-indicators))))
                (ov (make-overlay (1- pos) pos)))
            (overlay-put ov 'dired-snacks--subtree-indicator t)
            (overlay-put ov 'evaporate t)
            (overlay-put ov 'display (propertize indicator 'face 'dired-snacks-subtree-indicator))))
        (forward-line 1)))))

(defun dired-snacks--subtree-absolutize (beg end dir)
  "Make the file names between BEG and END absolute under DIR.
DIR is inserted invisibly, so only the base name shows."
  (save-excursion
    (goto-char beg)
    (while (< (point) end)
      (if-let* ((pos (dired-move-to-filename nil)))
          (progn
            (goto-char pos)
            (insert (propertize dir
                                'dired-filename t
                                'invisible 'dired-snacks--subtree-hidden)))
        (put-text-property (pos-bol) (min end (1+ (pos-eol)))
                           'invisible 'dired-snacks--subtree-hidden))
      (forward-line 1))))

(defun dired-snacks--subtree-delete-dots (beg end &optional dotfiles)
  "Delete the . and .. entries between BEG and END, and the dotfiles if DOTFILES."
  (save-excursion
    (goto-char beg)
    (while (< (point) end)
      (if (or (dired-snacks--subtree-dot-p)
              (and dotfiles
                   (string-prefix-p "." (or (dired-get-filename 'no-dir t) ""))))
          (delete-region (pos-bol) (1+ (pos-eol)))
        (forward-line 1)))))

(defun dired-snacks--subtree-insert ()
  "Insert the directory on this line as an inline subtree."
  (let* ((dir (file-name-as-directory (dired-get-filename nil t)))
         (depth (1+ (dired-snacks--subtree-depth-at (point))))
         (prefix (dired-snacks--subtree-line-prefix depth))
         (parent (pos-bol))
         (inhibit-read-only t))
    (save-excursion
      (forward-line 1)
      (let ((beg (point))
            (end (point-marker)))
        (let ((dired-free-space nil))
          (dired-insert-directory dir dired-actual-switches nil nil nil))
        (set-marker end (point))
        (dired-snacks--subtree-absolutize beg end dir)
        (dired-snacks--subtree-delete-dots beg end)
        (when (bound-and-true-p dired-omit-mode)
          (let ((dired-omit-size-limit nil)
                (dired-omit-verbose nil))
            (dired-omit-expunge)))
        (let ((ov (make-overlay beg end nil nil t)))
          (overlay-put ov 'dired-snacks--subtree depth)
          (overlay-put ov 'dired-snacks--subtree-parent (copy-marker parent t))
          (overlay-put ov 'line-prefix prefix)
          (overlay-put ov 'evaporate t)
          (push ov dired-snacks--subtree-overlays))
        (dired-snacks--subtree-draw-indicators parent end)
        (set-marker end nil)))
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
    (delete-region beg end))
  (dired-snacks--subtree-draw-indicators (pos-bol) (pos-eol))
  (run-hooks 'dired-snacks-subtree-after-change-hook)
  (dired-move-to-filename))

;;;###autoload
(defun dired-snacks-subtree-toggle ()
  "Expand the directory at point as an inline subtree, or collapse it."
  (interactive)
  (cond*
   ((not (dired-snacks--subtree-directory-p))
    (user-error "No directory to expand on this line"))
   ((bind-and* (ov (dired-snacks--subtree-child-overlay)))
    (dired-snacks--subtree-remove ov))
   (t (dired-snacks--subtree-insert))))

(defun dired-snacks--subtree-reset ()
  "Collapse every tracked subtree."
  (when dired-snacks--subtree-overlays
    (let ((inhibit-read-only t))
      (dolist (ov (sort dired-snacks--subtree-overlays
                        :key (lambda (o) (or (overlay-get o 'dired-snacks--subtree) 0))
                        :reverse t))
        (when (overlay-buffer ov)
          (delete-region (overlay-start ov) (overlay-end ov)))
        (delete-overlay ov)))
    (setq dired-snacks--subtree-overlays nil)))

(defun dired-snacks--subtree-prune ()
  "Collapse the subtrees whose directory line was deleted."
  (when dired-snacks--subtree-overlays
    (let ((pruned nil)
          (inhibit-read-only t))
      (dolist (ov dired-snacks--subtree-overlays)
        (when-let* ((_ (overlay-buffer ov))
                    (parent (overlay-get ov 'dired-snacks--subtree-parent))
                    ;; Once the directory line is deleted, its marker sits
                    ;; at the subtree, or past a line inserted in its place.
                    (_ (>= parent (overlay-start ov))))
          (delete-region parent (overlay-end ov))
          (delete-overlay ov)
          (setq pruned t)))
      (setq dired-snacks--subtree-overlays
            (seq-filter #'overlay-buffer dired-snacks--subtree-overlays))
      (when pruned
        (run-hooks 'dired-snacks-subtree-after-change-hook)))))

(defun dired-snacks--subtree-prune-visible ()
  "Collapse the orphan subtrees of the buffers in visible windows."
  (with-demoted-errors "dired-snacks: %S"
    (walk-windows (lambda (window)
                    (with-current-buffer (window-buffer window)
                      (dired-snacks--subtree-prune)))
                  'no-minibuf 'visible)))

(defun dired-snacks--subtree-after-readin ()
  "Collapse every subtree on a full readin, then draw the indicators."
  (unless (buffer-narrowed-p)
    (dired-snacks--subtree-reset))
  (dired-snacks--subtree-draw-indicators (point-min) (point-max)))

(defun dired-snacks--subtree-setup ()
  "Enable inline subtrees in the current Dired buffer."
  (remove-from-invisibility-spec 'dired-snacks--subtree-hidden)
  (add-to-invisibility-spec 'dired-snacks--subtree-hidden)
  (add-hook 'dired-after-readin-hook #'dired-snacks--subtree-after-readin nil t))

(defun dired-snacks--subtree-teardown ()
  "Disable inline subtrees in the current Dired buffer."
  (remove-hook 'dired-after-readin-hook #'dired-snacks--subtree-after-readin t)
  (dired-snacks--subtree-reset)
  (remove-overlays nil nil 'dired-snacks--subtree-indicator t)
  (remove-from-invisibility-spec 'dired-snacks--subtree-hidden))

(defun dired-snacks--subtree-refresh-icons ()
  "Redraw file icons after a subtree change, when `nerd-icons-dired' is on."
  (when (bound-and-true-p nerd-icons-dired-mode)
    (nerd-icons-dired--refresh)))

;; ===============================================================
;;; vc

(defcustom dired-snacks-vc-marks t
  "When non-nil, mark the Git state of each entry in the fringe."
  :type 'boolean)

(defface dired-snacks-vc-added '((t :inherit success))
  "Face for the fringe mark of new files.")

(defface dired-snacks-vc-modified '((t :inherit warning))
  "Face for the fringe mark of modified files.")

(defface dired-snacks-vc-conflict '((t :inherit error))
  "Face for the fringe mark of files with conflicts.")

(defconst dired-snacks--vc-faces
  '(dired-snacks-vc-conflict dired-snacks-vc-modified dired-snacks-vc-added)
  "Faces of the Git states, from the highest priority to the lowest.")

(define-fringe-bitmap 'dired-snacks--vc-bar [7] nil 3 '(center t))

(defvar-local dired-snacks--vc-proc nil
  "Running `git status' process, or nil.")

(defvar-local dired-snacks--vc-states nil
  "Hash table from file names to fringe faces, or nil.")

(defvar-local dired-snacks--vc-timer nil
  "Timer of the pending refresh of the Git marks, or nil.")

(defvar-local dired-snacks--vc-watch nil
  "File notification watch on the Git directory, or nil.")

(defun dired-snacks--vc-face (code)
  "Return the face for the `git status' CODE."
  (cond ((or (member code '("DD" "AA")) (string-search "U" code))
         'dired-snacks-vc-conflict)
        ((or (equal code "??") (eq (aref code 0) ?A))
         'dired-snacks-vc-added)
        (t 'dired-snacks-vc-modified)))

(defun dired-snacks--vc-parse (root)
  "Return the states in the `git status' output in this buffer.
File names are relative to ROOT.  A directory gets the state of highest
priority among the files below it."
  (let ((states (make-hash-table :test #'equal)))
    (dolist (entry (split-string (buffer-string) "\0" t) states)
      (let ((face (dired-snacks--vc-face (substring entry 0 2)))
            (name (substring entry 3)))
        (while name
          (let* ((file (directory-file-name (expand-file-name name root)))
                 (old (gethash file states)))
            (when (or (not old)
                      (< (seq-position dired-snacks--vc-faces face)
                         (seq-position dired-snacks--vc-faces old)))
              (puthash file face states)))
          (setq name (file-name-directory (directory-file-name name))))))))

(defun dired-snacks--vc-draw ()
  "Mark the Git state of each entry in the left fringe."
  (remove-overlays nil nil 'dired-snacks--vc t)
  (when (and dired-snacks-vc-marks dired-snacks--vc-states)
    (save-excursion
      (goto-char (point-min))
      (while (not (eobp))
        (when-let* ((file (dired-get-filename nil t))
                    (face (gethash (directory-file-name file) dired-snacks--vc-states)))
          (let ((ov (make-overlay (pos-bol) (pos-eol))))
            (overlay-put ov 'dired-snacks--vc t)
            (overlay-put ov 'evaporate t)
            (overlay-put ov 'before-string
                         (propertize " " 'display `(left-fringe dired-snacks--vc-bar ,face)))))
        (forward-line 1)))))

(defun dired-snacks--vc-sentinel (proc buffer root)
  "Mark BUFFER with the states PROC read under ROOT."
  (unless (process-live-p proc)
    (when (and (buffer-live-p buffer) (eq (process-status proc) 'exit))
      (let ((states (and (zerop (process-exit-status proc))
                         (with-current-buffer (process-buffer proc)
                           (dired-snacks--vc-parse root)))))
        (with-current-buffer buffer
          (setq dired-snacks--vc-states states)
          (dired-snacks--vc-draw))))
    (kill-buffer (process-buffer proc))))

(defun dired-snacks--vc-schedule (buffer)
  "Refresh the Git marks of BUFFER after a short delay."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (when (timerp dired-snacks--vc-timer)
        (cancel-timer dired-snacks--vc-timer))
      (setq dired-snacks--vc-timer
            (run-with-timer 0.2 nil
                            (lambda ()
                              (when (buffer-live-p buffer)
                                (with-current-buffer buffer
                                  (dired-snacks--vc-refresh)))))))))

(defun dired-snacks--vc-git-dir (root)
  "Return the Git directory of the repository at ROOT, or nil."
  (let ((dot-git (expand-file-name ".git" root)))
    (if (file-directory-p dot-git)
        dot-git
      (with-work-buffer
        (insert-file-contents dot-git)
        (when (looking-at "gitdir: \\(.+\\)")
          (expand-file-name (match-string 1) root))))))

(defun dired-snacks--vc-add-watch (root)
  "Refresh the Git marks whenever the Git directory of ROOT changes."
  (require 'filenotify)
  (unless (file-notify-valid-p dired-snacks--vc-watch)
    (when-let* ((dir (dired-snacks--vc-git-dir root)))
      (let ((buffer (current-buffer)))
        (setq dired-snacks--vc-watch
              (ignore-error file-notify-error
                (file-notify-add-watch dir '(change)
                                       (lambda (_event)
                                         (dired-snacks--vc-schedule buffer)))))))))

(defun dired-snacks--vc-remove-watch ()
  "Stop watching the Git directory."
  (when dired-snacks--vc-watch
    (file-notify-rm-watch dired-snacks--vc-watch)
    (setq dired-snacks--vc-watch nil)))

(defun dired-snacks--vc-refresh ()
  "Read the Git state of this directory in the background, then mark it."
  (when (process-live-p dired-snacks--vc-proc)
    (delete-process dired-snacks--vc-proc))
  (if-let* (dired-snacks-vc-marks
            (_ (not (file-remote-p default-directory)))
            (root (locate-dominating-file default-directory ".git"))
            (_ (executable-find "git")))
      (let ((buffer (current-buffer))
            (root (expand-file-name root)))
        (dired-snacks--vc-add-watch root)
        ;; `--no-optional-locks' keeps git from writing the index, which
        ;; could collide with a git command the user is running.
        (setq dired-snacks--vc-proc
              (make-process
               :name "dired-snacks-vc"
               :buffer (generate-new-buffer " *dired-snacks-vc*")
               :command '("git" "--no-optional-locks" "status" "--porcelain" "-z"
                          "--no-renames" "--untracked-files=all" "--" ".")
               :connection-type 'pipe
               :noquery t
               :sentinel (lambda (proc _event)
                           (dired-snacks--vc-sentinel proc buffer root)))))
    (setq dired-snacks--vc-states nil)
    (dired-snacks--vc-draw)))

(defun dired-snacks--vc-after-save ()
  "Refresh the Git marks of the Dired buffers in this file's repository."
  (when-let* ((_ (not (file-remote-p buffer-file-name)))
              (root (locate-dominating-file buffer-file-name ".git")))
    (dired-snacks--map-buffers
     (lambda ()
       (when (file-in-directory-p default-directory root)
         (dired-snacks--vc-schedule (current-buffer)))))))

(defun dired-snacks--vc-on-select (window)
  "Refresh the Git marks when WINDOW gets selected."
  (when (eq window (selected-window))
    (dired-snacks--vc-schedule (current-buffer))))

(defun dired-snacks--vc-after-readin ()
  "Mark the new entries with the last known states, then refresh them."
  (dired-snacks--vc-draw)
  (unless (and (eq (current-buffer) dired-snacks--find-buffer)
               dired-snacks--vc-states)
    (dired-snacks--vc-refresh)))

(defun dired-snacks--vc-setup ()
  "Enable the Git marks in the current Dired buffer."
  (add-hook 'dired-after-readin-hook #'dired-snacks--vc-after-readin nil t)
  (add-hook 'window-selection-change-functions #'dired-snacks--vc-on-select nil t)
  (add-hook 'kill-buffer-hook #'dired-snacks--vc-remove-watch nil t))

(defun dired-snacks--vc-teardown ()
  "Disable the Git marks in the current Dired buffer."
  (remove-hook 'dired-after-readin-hook #'dired-snacks--vc-after-readin t)
  (remove-hook 'window-selection-change-functions #'dired-snacks--vc-on-select t)
  (remove-hook 'kill-buffer-hook #'dired-snacks--vc-remove-watch t)
  (dired-snacks--vc-remove-watch)
  (when (timerp dired-snacks--vc-timer)
    (cancel-timer dired-snacks--vc-timer))
  (when (process-live-p dired-snacks--vc-proc)
    (delete-process dired-snacks--vc-proc))
  (remove-overlays nil nil 'dired-snacks--vc t)
  (setq dired-snacks--vc-states nil))

;; ===============================================================
;;; breadcrumb

(defcustom dired-snacks-breadcrumb-separator " » "
  "Separator drawn between breadcrumb segments."
  :type 'string)

(defcustom dired-snacks-breadcrumb-home "~"
  "Glyph for the home directory in the breadcrumb."
  :type 'string)

(defcustom dired-snacks-breadcrumb-root "/"
  "Glyph for the filesystem root in the breadcrumb."
  :type 'string)

(defcustom dired-snacks-breadcrumb-margin "  "
  "Left padding before the breadcrumb."
  :type 'string)

(defcustom dired-snacks-breadcrumb-hide-header t
  "When non-nil, hide the directory header line."
  :type 'boolean)

(defcustom dired-snacks-breadcrumb-spacing 0.2
  "Height of the gap under the breadcrumb, as a fraction of a line."
  :type 'number)

(defcustom dired-snacks-breadcrumb-height 0.95
  "Font size of the breadcrumb, as a fraction of the default."
  :type 'number)

(defun dired-snacks--breadcrumb-segments (dir)
  "Split DIR into breadcrumb segments."
  (let* ((abbr (abbreviate-file-name (directory-file-name dir)))
         (parts (split-string abbr "/" t)))
    (cond
     ((string-prefix-p "~" abbr) (cons dired-snacks-breadcrumb-home (cdr parts)))
     ((string-prefix-p "/" abbr) (cons dired-snacks-breadcrumb-root parts))
     (t parts))))

(defun dired-snacks--breadcrumb-quote (string)
  "Return STRING with `%' escaped, for use in a mode line construct."
  (string-replace "%" "%%" string))

(defun dired-snacks--directory-at-point ()
  "Return the directory holding the entry at point, or nil."
  (if-let* ((file (ignore-errors (dired-get-filename nil t))))
      (file-name-directory file)
    (ignore-errors (dired-current-directory))))

(defun dired-snacks--breadcrumb ()
  "Return a breadcrumb for the directory at point, or nil."
  (when (derived-mode-p 'dired-mode)
    (let* ((dir (or (dired-snacks--directory-at-point) default-directory))
           (height dired-snacks-breadcrumb-height)
           (sep (propertize (dired-snacks--breadcrumb-quote
                             dired-snacks-breadcrumb-separator)
                            'face `(:inherit shadow :height ,height))))
      (concat (dired-snacks--breadcrumb-quote dired-snacks-breadcrumb-margin)
              (mapconcat (lambda (s)
                           (propertize (dired-snacks--breadcrumb-quote s)
                                       'face `(:inherit dired-header :height ,height)))
                         (dired-snacks--breadcrumb-segments dir)
                         sep)
              (when (plusp dired-snacks-breadcrumb-spacing)
                (propertize " " 'display
                            `(raise ,(- dired-snacks-breadcrumb-spacing))))))))

(defun dired-snacks--breadcrumb-decorate ()
  "Hide the directory header line."
  (unless (eq (current-buffer) dired-snacks--find-buffer)
    (remove-overlays (point-min) (point-max) 'dired-snacks--header t)
    (when dired-snacks-breadcrumb-hide-header
      (let* ((first (next-single-property-change (point-min) 'dired-filename))
             (end (if first (save-excursion (goto-char first) (pos-bol))
                    (point-max)))
             (ov (make-overlay (point-min) end)))
        (overlay-put ov 'dired-snacks--header t)
        (overlay-put ov 'evaporate t)
        (overlay-put ov 'invisible 'dired-snacks--header)))))

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

(defcustom dired-snacks-side-window nil
  "When non-nil, show Dired in a bottom side window, half the frame high.
Split panes then open beside each other."
  :type 'boolean)

(defun dired-snacks--side-window-p (buffer &rest _)
  "Return non-nil if BUFFER is a Dired buffer for the side window."
  (and dired-snacks-side-window
       (buffer-match-p '(derived-mode . dired-mode) buffer)))

(defun dired-snacks--display-in-side-pane (buffer alist)
  "Show BUFFER in the selected window if it is a Dired side window.
ALIST is the action alist of `display-buffer'."
  (let ((window (selected-window)))
    (when (and (not (cdr (assq 'inhibit-same-window alist)))
               (window-parameter window 'window-side)
               (with-current-buffer (window-buffer window)
                 (derived-mode-p 'dired-mode)))
      (set-window-buffer window buffer)
      window)))

(defconst dired-snacks--side-window-rule
  '(dired-snacks--side-window-p
    (dired-snacks--display-in-side-pane display-buffer-in-side-window)
    (side . bottom) (slot . 0) (window-height . 0.5))
  "The `display-buffer-alist' entry behind `dired-snacks-side-window'.")

(defun dired-snacks--windows ()
  "Return the list of windows showing a Dired buffer."
  (seq-filter (lambda (w)
                (eq (buffer-local-value 'major-mode (window-buffer w)) 'dired-mode))
              (window-list)))

(defun dired-snacks-quit ()
  "Close this Dired pane, selecting the other one when there is one."
  (interactive)
  (let ((win (selected-window))
        (others (remq (selected-window) (dired-snacks--windows))))
    (if (not (window-parameter win 'dired-snacks-pane))
        (quit-window)
      (kill-current-buffer)
      (when (and (window-live-p win) (eq (window-deletable-p win) t))
        (delete-window win)))
    (when-let* ((w (seq-find #'window-live-p others)))
      (select-window w))))

(defvar-keymap dired-snacks--quit-mode-map
  "<remap> <quit-window>" #'dired-snacks-quit)

(define-minor-mode dired-snacks--quit-mode
  "Make q close this Dired pane."
  :keymap dired-snacks--quit-mode-map)

;;;###autoload
(defun dired-snacks-split ()
  "Open a second Dired in the current directory.
It opens beside this one in a wide or side window, else below it."
  (interactive)
  (let* ((dir default-directory)
         (win (selected-window))
         (side (window-parameter win 'window-side))
         (buf (let ((dired-buffers nil)) (dired-noselect dir))))
    (with-current-buffer buf
      (dired-advertise))
    (if side
        (let ((display-buffer-overriding-action
               `(display-buffer-in-side-window
                 (side . ,side)
                 (slot . ,(1+ (or (window-parameter win 'window-slot) 0))))))
          (select-window (display-buffer buf)))
      (select-window (if (window-splittable-p win t)
                         (split-window-right)
                       (split-window-below)))
      (switch-to-buffer buf))
    (set-window-parameter nil 'dired-snacks-pane t)))

(defun dired-snacks--give-own-buffer (window buffer)
  "Show in WINDOW a Dired buffer of its own for the listing of BUFFER."
  (let* ((file (with-current-buffer buffer
                 (save-excursion
                   (goto-char (window-point window))
                   (dired-get-filename nil t))))
         (own (let ((dired-buffers (seq-remove (lambda (entry)
                                                 (and (buffer-live-p (cdr entry))
                                                      (get-buffer-window (cdr entry) t)))
                                               dired-buffers)))
                (with-current-buffer buffer
                  (dired-noselect dired-directory dired-actual-switches)))))
    (with-current-buffer own
      (dired-advertise))
    (set-window-buffer window own)
    (when file
      (set-window-point window (with-current-buffer own
                                 (save-excursion
                                   (or (dired-goto-file file) (point-min))))))))

(defun dired-snacks--isolate-panes ()
  "Give each window its own Dired buffer while the frame has a split pane."
  (let ((windows (window-list nil 'no-minibuf)))
    (when (seq-find (lambda (w) (window-parameter w 'dired-snacks-pane)) windows)
      (pcase-dolist (`(,buffer . ,shared) (seq-group-by #'window-buffer windows))
        (when (and (cdr shared)
                   (rassq buffer dired-buffers)
                   (stringp (buffer-local-value 'dired-directory buffer)))
          (let ((keep (or (seq-find (lambda (w) (eq (window-old-buffer w) buffer)) shared)
                          (car shared))))
            (dolist (w (remq keep shared))
              (with-demoted-errors "dired-snacks: %S"
                (dired-snacks--give-own-buffer w buffer)))))))))

;; ===============================================================
;;; mode-line

(defcustom dired-snacks-mode-line-show-size t
  "When non-nil, show the size of the file at point, or a directory's items."
  :type 'boolean)

(defcustom dired-snacks-mode-line-show-time t
  "When non-nil, show the modification time of the entry at point."
  :type 'boolean)

(defcustom dired-snacks-mode-line-show-omit t
  "When non-nil, show the `dired-omit-mode' indicator."
  :type 'boolean)

(defcustom dired-snacks-mode-line-show-sort t
  "When non-nil, show the sort criterion."
  :type 'boolean)

(defcustom dired-snacks-mode-line-show-paste t
  "When non-nil, show the running pastes and the number of files to paste."
  :type 'boolean)

(defcustom dired-snacks-mode-line-index-width 7
  "Width reserved for the entry counter, so it never shifts."
  :type 'integer)

(defcustom dired-snacks-mode-line-size-width 10
  "Width reserved for the size or item count, so it never shifts."
  :type 'integer)

(defcustom dired-snacks-mode-line-time-format "%Y-%m-%d %H:%M"
  "Format of the timestamp shown in the mode line."
  :type 'string)

(defvar-local dired-snacks--mode-line-last-file nil
  "File at point after the last command.")

(defvar-local dired-snacks--mode-line-attr-cache nil
  "Cached attributes of the entry at point.")

(defvar-local dired-snacks--mode-line-items-cache nil
  "Cached (DIR MTIME . COUNT) of the last directory counted.")

(defvar-local dired-snacks--mode-line-total-cache nil
  "Cached count of the entries in this listing.")

(defvar-local dired-snacks--mode-line-current-cache nil
  "Cached count of the entries above a line, as (TICK BOL . N).")

(defun dired-snacks--mode-line-entry-p ()
  "Return non-nil when the current line holds an entry."
  (when-let* ((name (dired-get-filename 'no-dir t)))
    (not (member name '("." "..")))))

(defun dired-snacks--mode-line-count (beg end)
  "Return the number of entries on the lines starting from BEG before END."
  (save-excursion
    (goto-char beg)
    (let ((n 0))
      (while (< (point) end)
        (when (dired-snacks--mode-line-entry-p) (incf n))
        (forward-line 1))
      n)))

(defun dired-snacks--mode-line-total ()
  "Return the number of visible files and directories."
  (let ((tick (buffer-chars-modified-tick)))
    (unless (eql tick (car dired-snacks--mode-line-total-cache))
      (setq dired-snacks--mode-line-total-cache
            (cons tick (dired-snacks--mode-line-count (point-min) (point-max)))))
    (cdr dired-snacks--mode-line-total-cache)))

(defun dired-snacks--mode-line-current ()
  "Return the position of the entry at point in the listing."
  (let ((tick (buffer-chars-modified-tick))
        (bol (pos-bol)))
    (pcase-let* ((`(,old-tick ,old-bol . ,n) dired-snacks--mode-line-current-cache)
                 (from-top (- bol (point-min)))
                 (from-end (- (point-max) bol))
                 (from-last (and (eql tick old-tick) (abs (- bol old-bol)))))
      (setq n (cond ((and from-last (<= from-last (min from-top from-end)))
                     (if (< old-bol bol)
                         (+ n (dired-snacks--mode-line-count old-bol bol))
                       (- n (dired-snacks--mode-line-count bol old-bol))))
                    ((<= from-top from-end)
                     (dired-snacks--mode-line-count (point-min) bol))
                    (t (- (dired-snacks--mode-line-total)
                          (dired-snacks--mode-line-count bol (point-max))))))
      (setq dired-snacks--mode-line-current-cache (cons tick (cons bol n)))
      (if (dired-snacks--mode-line-entry-p) (1+ n) n))))

(defun dired-snacks--mode-line-index ()
  "Return the entry counter, as current over total."
  (when (derived-mode-p 'dired-mode)
    (let ((s (concat (number-to-string (dired-snacks--mode-line-current))
                     "/" (number-to-string (dired-snacks--mode-line-total)))))
      (concat "  " (string-pad s dired-snacks-mode-line-index-width nil t)))))

(defun dired-snacks--mode-line-file-attrs ()
  "Return the attributes of the entry at point, or nil."
  (when-let* ((name (and (derived-mode-p 'dired-mode)
                         (not (file-remote-p default-directory))
                         (dired-get-filename nil t))))
    (let ((key (cons name (buffer-chars-modified-tick))))
      (unless (equal key (car dired-snacks--mode-line-attr-cache))
        (setq dired-snacks--mode-line-attr-cache
              (cons key (file-attributes name)))))
    (cdr dired-snacks--mode-line-attr-cache)))

(defconst dired-snacks--items-limit 10000
  "Number of items past which a directory is not counted further.")

(defun dired-snacks--mode-line-items (dir mtime)
  "Return the number of items in DIR, whose modification time is MTIME."
  (pcase-let ((`(,d ,m . ,n) dired-snacks--mode-line-items-cache))
    (if (and (equal d dir) (time-equal-p m mtime))
        n
      (let ((n (ignore-errors
                 (length (directory-files dir nil directory-files-no-dot-files-regexp t
                                          (1+ dired-snacks--items-limit))))))
        (setq dired-snacks--mode-line-items-cache (cons dir (cons mtime n)))
        n))))

(defun dired-snacks--size-text (file attrs)
  "Return the size of FILE from its ATTRS, or its number of items if a directory."
  (let* ((type (file-attribute-type attrs))
         (dir-attrs (cond ((eq type t) attrs)
                          ((and (stringp type) (file-directory-p file))
                           (file-attributes (file-truename file))))))
    (if (not dir-attrs)
        (file-size-human-readable (file-attribute-size attrs))
      (let ((n (dired-snacks--mode-line-items
                file (file-attribute-modification-time dir-attrs))))
        (cond ((not n) "-")
              ((> n dired-snacks--items-limit)
               (format "%d+" dired-snacks--items-limit))
              (t (number-to-string n)))))))

(defun dired-snacks--mode-line-size ()
  "Return the size of the file at point, or a directory's items, or nil."
  (when dired-snacks-mode-line-show-size
    (when-let* ((attrs (dired-snacks--mode-line-file-attrs)))
      (let ((text (dired-snacks--size-text (dired-get-filename nil t) attrs)))
        (concat "  " (propertize (string-pad text dired-snacks-mode-line-size-width nil t)
                                 'face 'shadow))))))

(defun dired-snacks--mode-line-time ()
  "Return the modification time of the entry at point, or nil."
  (when dired-snacks-mode-line-show-time
    (when-let* ((attrs (dired-snacks--mode-line-file-attrs)))
      (concat "  " (propertize (format-time-string dired-snacks-mode-line-time-format
                                                   (file-attribute-modification-time attrs))
                               'face 'shadow)))))

(defun dired-snacks--mode-line-omit ()
  "Return the `dired-omit-mode' indicator, or nil."
  (when (and dired-snacks-mode-line-show-omit (bound-and-true-p dired-omit-mode))
    (propertize "  omit" 'face 'shadow)))

(defun dired-snacks--sort-criterion (switches)
  "Return the sort criterion named by the `ls' SWITCHES."
  (let ((crit "name"))
    (dolist (switch (split-string switches) crit)
      (cond
       ((string-prefix-p "--sort=" switch)
        (setq crit (pcase (string-remove-prefix "--sort=" switch)
                     ("extension" "type")
                     (word word))))
       ((string-match-p "\\`-[^-]" switch)
        (dolist (c (string-to-list (substring switch 1)))
          (setq crit (alist-get c '((?t . "time") (?S . "size") (?X . "type")
                                    (?v . "version") (?U . "none"))
                                crit))))))))

(defun dired-snacks--mode-line-sort ()
  "Return the sort criterion of this listing, or nil."
  (when (and dired-snacks-mode-line-show-sort (derived-mode-p 'dired-mode))
    (concat "  " (propertize (dired-snacks--sort-criterion dired-actual-switches)
                             'face 'shadow))))

(defconst dired-snacks--mode-line-spinner '("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
  "Frames of the animation shown next to a running paste.")

(defvar dired-snacks--mode-line-spinner-step 0
  "Number of frames the running pastes have been animated.")

(defvar dired-snacks--mode-line-spinner-timer nil
  "Timer that animates the running pastes, or nil.")

(defun dired-snacks--mode-line-spin ()
  "Show the next frame of the paste animation."
  (incf dired-snacks--mode-line-spinner-step)
  (dired-snacks--map-buffers #'force-mode-line-update))

(defun dired-snacks--mode-line-animate-pastes ()
  "Animate the mode lines while a paste runs, and refresh them."
  (cond
   ((and dired-snacks--paste-tasks (not dired-snacks--mode-line-spinner-timer))
    (setq dired-snacks--mode-line-spinner-timer
          (run-with-timer 0.1 0.1 #'dired-snacks--mode-line-spin)))
   ((and (not dired-snacks--paste-tasks) dired-snacks--mode-line-spinner-timer)
    (cancel-timer dired-snacks--mode-line-spinner-timer)
    (setq dired-snacks--mode-line-spinner-timer nil)))
  (force-mode-line-update t))

(defun dired-snacks--mode-line-paste ()
  "Return the progress of the running pastes and the files to paste, or nil."
  (when-let* ((_ dired-snacks-mode-line-show-paste)
              (frame (nth (mod dired-snacks--mode-line-spinner-step
                               (length dired-snacks--mode-line-spinner))
                          dired-snacks--mode-line-spinner))
              (parts (append (mapcar (lambda (task)
                                       (concat frame " " (dired-snacks--paste-progress task)))
                                     dired-snacks--paste-tasks)
                             (and dired-snacks--clipped
                                  (list (format "%d to paste" (length dired-snacks--clipped)))))))
    (concat "  " (string-join parts "  "))))

(defun dired-snacks--mode-line-width (&rest segments)
  "Return the total display width of SEGMENTS."
  (apply #'+ (mapcar #'string-width (delq nil segments))))

(defun dired-snacks--mode-line-right ()
  "Return the right-hand segments of the mode line.
The omit indicator and the sort criterion are dropped when space runs out."
  (when (derived-mode-p 'dired-mode)
    (let ((paste (dired-snacks--mode-line-paste))
          (size (dired-snacks--mode-line-size))
          (time (dired-snacks--mode-line-time))
          (crit (dired-snacks--mode-line-sort))
          (omit (dired-snacks--mode-line-omit))
          (index (dired-snacks--mode-line-index))
          (room (- (window-width)
                   (+ 10 (max 12 (string-width (buffer-name)))))))
      (when (> (dired-snacks--mode-line-width paste size time crit omit index) room)
        (setq omit nil))
      (when (> (dired-snacks--mode-line-width paste size time crit omit index) room)
        (setq crit nil))
      (concat paste size time crit omit index))))

(defcustom dired-snacks-mode-line-format
  '("%e  "
    (:propertize " " display (raise +0.1)) ; top padding
    (:propertize " " display (raise -0.1)) ; bottom padding
    mode-line-modified
    "  "
    mode-line-buffer-identification
    mode-line-format-right-align
    (:eval (dired-snacks--mode-line-right))
    "  ")
  "The mode line shown in Dired buffers."
  :type 'sexp)

(defun dired-snacks--mode-line-refresh ()
  "Refresh the mode line when point moves to another entry."
  (let ((name (dired-get-filename nil t)))
    (unless (equal name dired-snacks--mode-line-last-file)
      (setq dired-snacks--mode-line-last-file name)
      (force-mode-line-update))))

(defun dired-snacks--mode-line-setup ()
  "Give this Dired buffer its own mode line."
  (setq-local mode-line-format dired-snacks-mode-line-format)
  (add-hook 'post-command-hook #'dired-snacks--mode-line-refresh nil t))

(defun dired-snacks--mode-line-teardown ()
  "Give this Dired buffer the usual mode line back."
  (kill-local-variable 'mode-line-format)
  (remove-hook 'post-command-hook #'dired-snacks--mode-line-refresh t)
  (force-mode-line-update))

(defun dired-snacks--map-buffers (fn)
  "Call FN in every live Dired buffer."
  (dolist (buf (buffer-list))
    (with-current-buffer buf
      (when (derived-mode-p 'dired-mode) (funcall fn)))))

;; ===============================================================
;;; columns

(defcustom dired-snacks-hide-details t
  "When non-nil, turn on `dired-hide-details-mode' in Dired buffers."
  :type 'boolean)

(defcustom dired-snacks-columns '(size time)
  "Columns shown at the right edge while details are hidden, in this order."
  :type '(set (const permissions) (const size) (const time)))

(defcustom dired-snacks-columns-time-format "%Y-%m-%d %H:%M"
  "Format of the time column, as for `format-time-string'."
  :type 'string)

(defface dired-snacks-column '((t :inherit shadow))
  "Face for the columns at the right edge.")

(defconst dired-snacks--columns-size-width 6
  "Width of the size column, so that the columns line up.")

(defvar-local dired-snacks--columns-highlighted nil
  "Columns overlay drawn with the `hl-line' face, or nil.")

(defun dired-snacks--column-text (column file attrs)
  "Return the text of COLUMN for FILE, whose attributes are ATTRS."
  (pcase column
    ('permissions (file-attribute-modes attrs))
    ('size (string-pad (dired-snacks--size-text file attrs)
                       dired-snacks--columns-size-width nil t))
    ('time (format-time-string dired-snacks-columns-time-format
                               (file-attribute-modification-time attrs)))))

(defun dired-snacks--columns-stamp (file attrs)
  "Return the status change time the columns of FILE, with ATTRS, depend on."
  (file-attribute-status-change-time
   (if (stringp (file-attribute-type attrs))
       (or (file-attributes (file-truename file)) attrs)
     attrs)))

(defun dired-snacks--columns-refresh-stale ()
  "Redraw the visible columns of files that changed since they were drawn."
  (with-demoted-errors "dired-snacks: %S"
    (dolist (window (window-list nil 'no-minibuf))
      (with-current-buffer (window-buffer window)
        (when (derived-mode-p 'dired-mode)
          (dolist (ov (overlays-in (window-start window) (window-end window)))
            (when-let* ((file (overlay-get ov 'dired-snacks--columns-file)))
              (let ((attrs (file-attributes file)))
                (unless (and attrs
                             (time-equal-p (overlay-get ov 'dired-snacks--columns-stamp)
                                           (dired-snacks--columns-stamp file attrs)))
                  (jit-lock-refontify (overlay-start ov) (overlay-end ov)))))))))))

(defun dired-snacks--columns-hl-line ()
  "Return the overlay of `hl-line-mode' in this buffer, or nil."
  (seq-find (lambda (ov) (and (overlayp ov) (overlay-buffer ov)))
            (list (bound-and-true-p hl-line-overlay)
                  (bound-and-true-p global-hl-line-overlay))))

(defun dired-snacks--columns-paint (ov hl)
  "Show the columns of OV, with the face of the `hl-line' overlay HL if non-nil."
  (let ((string (overlay-get ov 'dired-snacks--columns-string)))
    (when hl
      (setq string (copy-sequence string))
      (add-face-text-property 0 (length string) (overlay-get hl 'face) t string)
      (setq dired-snacks--columns-highlighted ov))
    (overlay-put ov 'after-string string)))

(defun dired-snacks--columns-follow-hl-line (&rest _)
  "Move the `hl-line' face to the columns of the highlighted line."
  (let* ((hl (dired-snacks--columns-hl-line))
         (ov (and hl (seq-find (lambda (o) (overlay-get o 'dired-snacks--columns))
                               (overlays-at (overlay-start hl))))))
    (unless (eq ov dired-snacks--columns-highlighted)
      (when-let* ((old dired-snacks--columns-highlighted)
                  (_ (overlay-buffer old)))
        (dired-snacks--columns-paint old nil))
      (setq dired-snacks--columns-highlighted nil)
      (when ov
        (dired-snacks--columns-paint ov hl)))))

(defun dired-snacks--columns-draw (beg end)
  "Draw the columns on the lines between BEG and END."
  (save-excursion
    (setq beg (progn (goto-char beg) (pos-bol))
          end (progn (goto-char end) (min (1+ (pos-eol)) (point-max))))
    (remove-overlays beg end 'dired-snacks--columns t)
    (when (and dired-hide-details-mode
               dired-snacks-columns
               (not (file-remote-p default-directory)))
      (let ((hl (dired-snacks--columns-hl-line)))
        (goto-char beg)
        (while (< (point) end)
          (when-let* ((_ (not (invisible-p (point))))
                      (file (dired-get-filename nil t))
                      (attrs (file-attributes file)))
            (let ((text (concat "  " (mapconcat (lambda (column)
                                                  (dired-snacks--column-text column file attrs))
                                                dired-snacks-columns "  ")))
                  (ov (make-overlay (pos-bol) (pos-eol))))
              (overlay-put ov 'dired-snacks--columns t)
              (overlay-put ov 'evaporate t)
              (overlay-put ov 'dired-snacks--columns-file file)
              (overlay-put ov 'dired-snacks--columns-stamp
                           (dired-snacks--columns-stamp file attrs))
              (overlay-put ov 'dired-snacks--columns-string
                           (concat (propertize " " 'display
                                               `(space :align-to
                                                       (- right (,(1+ (string-width text)) . width))))
                                   (propertize text 'face 'dired-snacks-column)))
              (dired-snacks--columns-paint
               ov (and hl (= (overlay-start hl) (pos-bol)) hl))))
          (forward-line 1))))
    `(jit-lock-bounds ,beg . ,end)))

(defun dired-snacks--columns-setup ()
  "Show the columns in the current Dired buffer."
  (when dired-snacks-hide-details
    (dired-hide-details-mode 1))
  (when dired-snacks-columns
    (setq-local truncate-lines t))
  (add-hook 'dired-hide-details-mode-hook #'jit-lock-refontify nil t)
  (add-hook 'post-command-hook #'dired-snacks--columns-follow-hl-line 90 t)
  (add-hook 'window-selection-change-functions #'dired-snacks--columns-follow-hl-line nil t)
  (jit-lock-register #'dired-snacks--columns-draw)
  (jit-lock-refontify))

(defun dired-snacks--columns-teardown ()
  "Remove the columns from the current Dired buffer."
  (jit-lock-unregister #'dired-snacks--columns-draw)
  (remove-hook 'dired-hide-details-mode-hook #'jit-lock-refontify t)
  (remove-hook 'post-command-hook #'dired-snacks--columns-follow-hl-line t)
  (remove-hook 'window-selection-change-functions #'dired-snacks--columns-follow-hl-line t)
  (remove-overlays nil nil 'dired-snacks--columns t)
  (kill-local-variable 'truncate-lines)
  (setq dired-snacks--columns-highlighted nil))

;; ===============================================================
;;; last-file

(defun dired-snacks--stay-on-last-file ()
  "Move point from the empty end of the buffer to the last visible file."
  (when (and (eobp) (derived-mode-p 'dired-mode))
    (let ((pos nil))
      (save-excursion
        (while (and (not pos) (zerop (forward-line -1)))
          (unless (invisible-p (point))
            (setq pos (dired-move-to-filename)))))
      (when pos
        (goto-char pos)))))

;; ===============================================================
;;; minor mode

(defun dired-snacks--setup ()
  "Install the buffer-local features in the current Dired buffer."
  (dired-snacks--subtree-setup)
  (dired-snacks--vc-setup)
  (dired-snacks--columns-setup)
  (dired-snacks--breadcrumb-setup)
  (dired-snacks--subtree-draw-indicators (point-min) (point-max))
  (dired-snacks--breadcrumb-decorate)
  (unless (zerop (buffer-size))
    (dired-snacks--vc-refresh))
  (dired-snacks--mode-line-setup)
  (add-hook 'post-command-hook #'dired-snacks--stay-on-last-file nil t)
  (dired-snacks--quit-mode 1))

(defun dired-snacks--teardown ()
  "Remove the buffer-local features from the current Dired buffer."
  (dired-snacks--subtree-teardown)
  (dired-snacks--vc-teardown)
  (dired-snacks--columns-teardown)
  (dired-snacks--breadcrumb-teardown)
  (dired-snacks--mode-line-teardown)
  (remove-hook 'post-command-hook #'dired-snacks--stay-on-last-file t)
  (dired-snacks--quit-mode -1))

(defun dired-snacks--enable ()
  "Install the passive features."
  (add-hook 'find-file-hook #'dired-snacks--zoxide-add-default-directory)
  (add-hook 'dired-mode-hook #'dired-snacks--zoxide-add-default-directory)
  (add-hook 'dired-mode-hook #'dired-snacks--setup)
  (add-hook 'dired-snacks-subtree-after-change-hook #'dired-snacks--subtree-refresh-icons)
  (add-hook 'dired-snacks-subtree-after-change-hook #'dired-snacks--vc-draw)
  (add-hook 'after-save-hook #'dired-snacks--vc-after-save)
  (add-hook 'post-command-hook #'dired-snacks--isolate-panes)
  (add-hook 'post-command-hook #'dired-snacks--columns-refresh-stale)
  (add-hook 'post-command-hook #'dired-snacks--subtree-prune-visible)
  (add-to-list 'display-buffer-alist dired-snacks--side-window-rule)
  (dired-snacks--map-buffers #'dired-snacks--setup))

(defun dired-snacks--disable ()
  "Remove the passive features."
  (remove-hook 'find-file-hook #'dired-snacks--zoxide-add-default-directory)
  (remove-hook 'dired-mode-hook #'dired-snacks--zoxide-add-default-directory)
  (remove-hook 'dired-mode-hook #'dired-snacks--setup)
  (remove-hook 'dired-snacks-subtree-after-change-hook #'dired-snacks--subtree-refresh-icons)
  (remove-hook 'dired-snacks-subtree-after-change-hook #'dired-snacks--vc-draw)
  (remove-hook 'after-save-hook #'dired-snacks--vc-after-save)
  (remove-hook 'post-command-hook #'dired-snacks--isolate-panes)
  (remove-hook 'post-command-hook #'dired-snacks--columns-refresh-stale)
  (remove-hook 'post-command-hook #'dired-snacks--subtree-prune-visible)
  (setq display-buffer-alist (delete dired-snacks--side-window-rule display-buffer-alist))
  (dired-snacks--map-buffers #'dired-snacks--teardown))

;;;###autoload
(define-minor-mode dired-snacks-mode
  "Toggle the dired-snacks features applied to every Dired buffer."
  :global t
  (if dired-snacks-mode
      (dired-snacks--enable)
    (dired-snacks--disable)))

(provide 'dired-snacks)
;;; dired-snacks.el ends here
