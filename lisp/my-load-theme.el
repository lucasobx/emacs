;;; my-load-theme.el --- Load/persist theme  -*- lexical-binding: t; -*-

;; Author: Lucas
;; Keywords: faces

;;; Commentary:

;; A small theme manager: load a theme (disabling any others first), pick
;; one interactively or rotate through the available ones, and remember the
;; choice across sessions.

;;; Code:

(defcustom my/theme nil
  "Theme loaded at startup and saved across sessions, or nil for none.
Chosen with `my/select-theme' or `my/rotate-theme'."
  :type '(choice (const :tag "None" nil) (symbol :tag "Theme"))
  :group 'faces)

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
  (setq my/theme theme)
  (message "Theme: %s" theme))

(defun my/select-theme ()
  "Interactively select and load a theme."
  (interactive)
  (let ((choice (completing-read "Theme: " (my/theme-list) nil t)))
    (unless (string-empty-p choice)
      (my/load-theme (intern choice)))))

(defun my/rotate-theme ()
  "Load the next theme in `my/theme-list'."
  (interactive)
  (let ((themes (my/theme-list)))
    (if (null themes)
        (message "No themes available")
      (let* ((current (or (seq-position themes my/theme) -1))
             (next (mod (1+ current) (length themes))))
        (my/load-theme (nth next themes))))))

(defun my/theme--restore ()
  "Load the saved `my/theme', warning if it can no longer be found."
  (when my/theme
    (condition-case err
        (my/load-theme my/theme)
      ;; A saved theme may no longer exist (package removed, renamed);
      ;; don't let that abort startup.
      (error (message "Could not load saved theme `%s': %s"
                      my/theme (error-message-string err))))))

(defun my/theme--persist ()
  "Save `my/theme' for the next session."
  (when my/theme
    (customize-save-variable 'my/theme my/theme)))

;; restore the saved theme after startup, and persist it on exit.
(add-hook 'after-init-hook #'my/theme--restore)
(add-hook 'kill-emacs-hook #'my/theme--persist)

(provide 'my-load-theme)
;;; my-load-theme.el ends here
