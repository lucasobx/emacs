;;; dired-snacks.el --- dired snacks  -*- lexical-binding: t; -*-
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
  "Overlay showing the inline zoxide best-match in the minibuffer.")

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
  "Register DIR in the zoxide database (fire-and-forget)."
  (when (and dir (executable-find "zoxide"))
    (call-process "zoxide" nil 0 nil "add" "--" (expand-file-name dir))))

(defun my/zoxide--add-default-directory ()
  "Register `default-directory' in zoxide for `find-file' and Dired visits."
  (when (and (not (file-remote-p default-directory))
             (file-directory-p default-directory))
    (my/zoxide--add default-directory)))

(add-hook 'find-file-hook  #'my/zoxide--add-default-directory)
(add-hook 'dired-mode-hook #'my/zoxide--add-default-directory)

(defun my/zoxide--path-like-p (input)
  "Return non-nil when INPUT looks like a literal file-system path."
  (and (string-match-p "[/~]" input) t))

(defun my/zoxide--update-ghost (&rest _)
  "Refresh the inline ghost of the best zoxide match.
Fuzzy queries only. Literal paths use `completion-preview'."
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
  "Completion-at-point function for file-system paths.
Drives the `completion-preview' ghost for literal paths."
  (list (minibuffer-prompt-end) (point) #'completion-file-name-table))

(defun my/zoxide--inhibit-preview ()
  "Inhibit `completion-preview' unless the input looks like a literal path."
  (not (my/zoxide--path-like-p (minibuffer-contents))))

(defun my/zoxide-complete-path ()
  "Complete the minibuffer input as a directory path, in place."
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
  "Complete the minibuffer input on TAB.
Literal paths complete in place; fuzzy queries expand to the best zoxide
match. A visible `completion-preview' ghost overrides this on TAB."
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
  "Keymap for `my/zoxide-dired' with TAB path completion.")

(defun my/zoxide-dired ()
  "Prompt for a zoxide query and open the chosen directory in Dired.
Fuzzy queries show the best match inline. Literal paths get a preview."
  (interactive)
  (let* ((orig (current-buffer))
         (input (minibuffer-with-setup-hook
                    (lambda ()
                      (setq my/zoxide--ghost-ov nil)
                      ;; fuzzy best-match ghost
                      (add-hook 'after-change-functions #'my/zoxide--update-ghost nil t)
                      ;; literal-path ghost via completion-preview
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
;;; dired-copy-file-uri

(defun my/dired-copy-file-uri ()
  "Copy the marked files as file:// URIs to the Wayland clipboard."
  (interactive)
  (unless (executable-find "wl-copy")
    (user-error "wl-copy not found; install wl-clipboard"))
  (let* ((files (dired-get-marked-files))
         (uris (mapconcat (lambda (f) (concat "file://" f)) files "\n")))
    (let ((p (make-process :name "wl-copy"
                           :command '("wl-copy" "--type" "text/uri-list")
                           :connection-type 'pipe)))
      (process-send-string p uris)
      (process-send-eof p))
    (dired-unmark-all-marks)
    (message "Copied %d file URI%s to clipboard"
             (length files)
             (if (= (length files) 1) "" "s"))))

(provide 'dired-snacks)
;;; dired-snacks.el ends here
