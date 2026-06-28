;;; my-load-theme.el --- load/persist theme  -*- lexical-binding: t; -*-
;;; Commentary:
;;; Code:

(defvar my/theme nil
  "Currently active theme.")

(defun my/theme-list ()
  "Return the available themes, excluding the built-in ones."
  (let ((builtin (expand-file-name "themes" data-directory)))
    (seq-remove (lambda (theme)
                  (locate-file (format "%s-theme.el" theme) (list builtin)))
                (custom-available-themes))))

(defun my/load-theme (theme)
  "Disable active themes and load THEME."
  (mapc #'disable-theme custom-enabled-themes)
  (load-theme theme :no-confirm)
  (setq my/theme theme))

(defun my/select-theme ()
  "Interactively select and load a theme."
  (interactive)
  (let ((choice (completing-read "Theme: " (my/theme-list) nil t)))
    (unless (string-empty-p choice)
      (my/load-theme (intern choice)))))

(defun my/rotate-theme ()
  "Load the next theme in `my/theme-list'."
  (interactive)
  (let* ((themes (my/theme-list))
         (current (or (seq-position themes my/theme) -1))
         (next (mod (1+ current) (length themes))))
    (my/load-theme (nth next themes))))

;; restore the saved theme after startup, and persist it on exit.
(add-hook 'after-init-hook
          (lambda () (when my/theme (my/load-theme my/theme))))
(add-hook 'kill-emacs-hook
          (lambda () (when my/theme (customize-save-variable 'my/theme my/theme))))

(provide 'my-load-theme)
;;; my-load-theme.el ends here
