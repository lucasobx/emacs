;;; my-load-theme.el --- Load/persist theme  -*- lexical-binding: t; -*-

;; Author: Lucas
;; Keywords: faces

;;; Commentary:

;; A small theme manager: load a theme (disabling any others first), pick
;; one interactively or rotate through the available ones, and remember the
;; choice across sessions.

;;; Code:

(declare-function consult-theme "consult")
(defvar consult-themes)

(defcustom my/theme nil
  "Theme loaded at startup, or nil for none.
It tracks the last theme enabled and is saved whenever it changes."
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
  (message "Theme: %s" theme))

(defun my/select-theme ()
  "Pick a theme from `my/theme-list', previewing each one."
  (interactive)
  (require 'consult)
  (let ((consult-themes (my/theme-list)))
    (call-interactively #'consult-theme)))

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
  "Load the saved `my/theme', reporting it if it can no longer be loaded."
  (when my/theme
    (condition-case err
        (my/load-theme my/theme)
      ;; A saved theme may no longer exist (package removed, renamed);
      ;; don't let that abort startup.
      (error (message "Could not load saved theme `%s': %s"
                      my/theme (error-message-string err))))))

(defun my/theme--track (theme)
  "Set `my/theme' to THEME, if it is an installed theme, and schedule a save."
  (when (memq theme (custom-available-themes))
    (setq my/theme theme)
    (add-hook 'post-command-hook #'my/theme--save)))

(defun my/theme--save ()
  "Save `my/theme' if it changed, once the minibuffer is closed.
Waiting skips the themes that `consult-theme' only previews."
  (unless (active-minibuffer-window)
    (remove-hook 'post-command-hook #'my/theme--save)
    (unless (equal my/theme (eval (car (get 'my/theme 'saved-value)) t))
      (customize-save-variable 'my/theme my/theme))))

;; track every theme change, and restore the saved theme after startup.
(add-hook 'enable-theme-functions #'my/theme--track)
(add-hook 'after-init-hook #'my/theme--restore)

(provide 'my-load-theme)
;;; my-load-theme.el ends here
