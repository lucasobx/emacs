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
(defvar dired-actual-switches)
(defvar dired-mode-map)
(defvar dired-buffers)

(defvar my/dired-find-name-prune-dirs '(".git" ".hg" ".svn" ".jj")
  "Directory names never descended into when searching for files.")

(defvar my/dired-find-name--ghost-ov nil
  "Overlay showing the live match count in the minibuffer.")

(defvar my/dired-find-name--ghost-timer nil
  "Debounce timer for the match-count ghost.")

(defun my/dired-find-name--matches (dir query)
  "Return absolute paths of files under DIR whose name contains QUERY.
Case-insensitive on the file name, skips `my/dired-find-name-prune-dirs'."
  (cond
   ((string-empty-p query) nil)
   ((executable-find "fd")
    (with-temp-buffer
      (when (zerop (apply #'call-process "fd" nil t nil
                          (append
                           '("--hidden" "--no-ignore" "--type" "f"
                             "--fixed-strings" "--ignore-case" "--absolute-path")
                           (mapcan (lambda (d) (list "--exclude" d))
                                   my/dired-find-name-prune-dirs)
                           (list "--" query (expand-file-name dir)))))
        (split-string (buffer-string) "\n" t))))
   (t
    (let ((case-fold-search t))
      (directory-files-recursively
       dir (regexp-quote query) nil
       (lambda (d)
         (not (member (file-name-nondirectory (directory-file-name d))
                      my/dired-find-name-prune-dirs))))))))

(defun my/dired-find-name--ghost (mb)
  "Refresh the match-count ghost for the prompt in minibuffer MB."
  (when (buffer-live-p mb)
    (with-current-buffer mb
      (when (overlayp my/dired-find-name--ghost-ov)
        (delete-overlay my/dired-find-name--ghost-ov))
      (let ((query (minibuffer-contents)))
        (unless (string-empty-p query)
          (let* ((matches (my/dired-find-name--matches default-directory query))
                 (n (length matches))
                 (label (cond ((= n 0) "no matches")
                              ((= n 1) (concat "→ " (file-name-nondirectory
                                                     (car matches))))
                              (t (format "→ %d matches" n)))))
            (setq my/dired-find-name--ghost-ov
                  (make-overlay (point-max) (point-max) nil t t))
            (overlay-put my/dired-find-name--ghost-ov 'after-string
                         (propertize (concat "  " label)
                                     'face 'shadow 'cursor t))))))))

(defun my/dired-find-name--update-ghost (&rest _)
  "Schedule a debounced refresh of the match-count ghost."
  (when (timerp my/dired-find-name--ghost-timer)
    (cancel-timer my/dired-find-name--ghost-timer))
  (setq my/dired-find-name--ghost-timer
        (run-with-timer 0.2 nil #'my/dired-find-name--ghost (current-buffer))))

(defun my/dired-find-name--insert-matches (dir files)
  "Insert a subdir listing of DIR showing only FILES, relative to DIR.
Like `dired-insert-subdir' but avoids scanning DIR in full."
  (let ((dirname (file-name-as-directory (expand-file-name dir)))
        (inhibit-read-only t))
    (dired-insert-subdir-validate dirname dired-actual-switches)
    (dired-insert-subdir-newpos dirname)
    (dired-insert-subdir-doupdate
     dirname nil
     (save-excursion
       (let ((begin (point))
             (default-directory dirname))
         (dired-insert-directory dirname dired-actual-switches files nil t)
         (list begin (point)))))))

(defun my/dired-find-name--icon-subdirs ()
  "Give each subdir header a folder icon, matching `nerd-icons-dired'."
  (when (bound-and-true-p nerd-icons-dired-mode)
    (save-excursion
      (goto-char (point-min))
      (while (not (eobp))
        (when-let* ((dir (dired-get-subdir)))
          (beginning-of-line)
          (skip-chars-forward " \t")
          (let* ((pos  (point))
                 (icon (funcall nerd-icons-dired-dir-icon-function
                                dir :height nerd-icons-dired-icon-size))
                 (str  (concat icon nerd-icons-dired-infix-string))
                 (ov   (make-overlay pos (1+ pos)))
                 (inhibit-read-only t))
            (overlay-put ov 'my/find-name-icon t)
            (overlay-put ov 'evaporate t)
            (overlay-put ov 'before-string (propertize str 'display str))))
        (forward-line 1)))))

(defun my/dired-find-name--drop-root-header ()
  "Remove the root's empty header and rebuild the subdir alist.
Used when no match lives directly in the searched directory."
  (let ((inhibit-read-only t))
    (save-excursion
      (goto-char (point-min))
      (forward-line 1)
      (while (and (not (eobp)) (not (dired-get-subdir)))
        (forward-line 1))
      (unless (eobp)
        (delete-region (point-min) (point))
        (dired-build-subdir-alist)))))

(defun my/dired-find-name--tree (root matches)
  "Show only MATCHES under ROOT in a transient Dired tree.
The buffer is independent of normal Dired navigation and `q' kills it."
  (require 'dired)
  (let ((bufname (format "*find-name: %s*" (abbreviate-file-name root)))
        (groups  (seq-group-by #'file-name-directory matches)))
    (when (get-buffer bufname)
      (kill-buffer bufname))
    (let ((buf (let ((dired-buffers nil))
                 (dired-noselect root))))
      (with-current-buffer buf
        (rename-buffer bufname)
        ;; never hide a matched file, also silences omit's size-limit notice
        (when (bound-and-true-p dired-omit-mode)
          (dired-omit-mode -1)
          (revert-buffer))
        ;; one subdir listing per directory that holds matches
        (dolist (group groups)
          (unless (file-equal-p (car group) root)
            (my/dired-find-name--insert-matches
             (car group) (mapcar #'file-name-nondirectory (cdr group)))))
        ;; keep only the matched files
        (let ((keep (mapcar #'file-truename matches))
              (inhibit-read-only t))
          (save-excursion
            (goto-char (point-min))
            (while (not (eobp))
              (let ((f (dired-get-filename nil t)))
                (if (and f (not (member (file-truename f) keep)))
                    (delete-region (line-beginning-position)
                                   (progn (forward-line 1) (point)))
                  (forward-line 1))))))
        ;; drop the root's own header when it holds no matches itself
        (unless (seq-find (lambda (g) (file-equal-p (car g) root)) groups)
          (my/dired-find-name--drop-root-header))
        (my/dired-find-name--icon-subdirs)
        ;; q kills this transient buffer instead of burying it
        (let ((map (make-sparse-keymap)))
          (set-keymap-parent map dired-mode-map)
          (keymap-set map "q" #'kill-current-buffer)
          (use-local-map map))
        (goto-char (point-min))
        (when (dired-goto-file (car matches))
          (dired-move-to-filename)))
      (pop-to-buffer-same-window buf))))

(defun my/dired-find-name ()
  "Find files under `default-directory' whose name contains a query.
A ghost shows the match count while typing. One match jumps to its
directory, several are shown as a Dired tree of just the matches."
  (interactive)
  (let* ((root (expand-file-name default-directory))
         (query (minibuffer-with-setup-hook
                    (lambda ()
                      (setq my/dired-find-name--ghost-ov nil
                            my/dired-find-name--ghost-timer nil)
                      (add-hook 'after-change-functions
                                #'my/dired-find-name--update-ghost nil t)
                      (add-hook 'minibuffer-exit-hook
                                (lambda ()
                                  (when (timerp my/dired-find-name--ghost-timer)
                                    (cancel-timer my/dired-find-name--ghost-timer)))
                                nil t))
                  (read-from-minibuffer
                   (format "Find name under %s: " (abbreviate-file-name root)))))
         (matches (my/dired-find-name--matches root query)))
    (cond
     ((string-empty-p query) (user-error "Empty query"))
     ((null matches)
      (user-error "No file matching %S under %s" query
                  (abbreviate-file-name root)))
     ((null (cdr matches)) (dired-jump nil (car matches)))
     (t (my/dired-find-name--tree root matches)))))

(provide 'dired-snacks)
;;; dired-snacks.el ends here
