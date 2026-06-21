;;; dired-snacks.el --- dired snacks  -*- lexical-binding: t; -*-
;;; Commentary:
;;; Code:

;; ===============================================================
;;; zoxide-dired

(defvar my/zoxide--ghost-ov nil
  "Overlay showing the inline zoxide match in the minibuffer.")

(defun my/zoxide--query (input)
  "Return the directory for INPUT: a literal existing path, else zoxide's best match."
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

(defun my/zoxide--update-ghost (&rest _)
  "Refresh the inline ghost preview of the best zoxide match."
  (when (overlayp my/zoxide--ghost-ov)
    (delete-overlay my/zoxide--ghost-ov))
  (let ((dir (my/zoxide--query (minibuffer-contents))))
    (when dir
      (setq my/zoxide--ghost-ov (make-overlay (point-max) (point-max) nil t t))
      (overlay-put my/zoxide--ghost-ov 'after-string
                   (propertize (concat "  → " (abbreviate-file-name dir))
                               'face 'shadow 'cursor t)))))

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

(defvar my/zoxide-minibuffer-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map minibuffer-local-map)
    (keymap-set map "TAB" #'my/zoxide-complete-path)
    map)
  "Keymap for `my/zoxide-dired' with TAB path completion.")

(defun my/zoxide-dired ()
  "Prompt for a zoxide query showing the best match inline, then open that directory in Dired."
  (interactive)
  (let* ((orig (current-buffer))
         (input (minibuffer-with-setup-hook
                    (lambda ()
                      (setq my/zoxide--ghost-ov nil)
                      (add-hook 'after-change-functions #'my/zoxide--update-ghost nil t))
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
