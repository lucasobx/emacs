;;; my-cache.el --- centralized cache/state paths  -*- lexical-binding: t; -*-
;;; Commentary:
;;; Code:

(defgroup my nil "Personal configuration." :group 'emacs)

(defcustom my/cache-directory
  (expand-file-name "cache/" user-emacs-directory)
  "Base directory against which `my/cache-paths' is resolved."
  :type `(choice
          (const :tag "Inside config   (cache/ in user-emacs-directory)"
                 ,(expand-file-name "cache/" user-emacs-directory))
          (const :tag "System temp     (/tmp/emacs-cache/)" "/tmp/emacs-cache/")
          (directory :tag "Custom directory"))
  :group 'my)

(defvar my/cache-paths
  '(;; Files:
    (bookmark-default-file       . "bookmarks")
    (recentf-save-file           . "recentf.eld")
    (savehist-file               . "history")
    (save-place-file             . "saveplace")
    (project-list-file           . "projects")
    (transient-history-file      . "transient/history.el")
    (transient-levels-file       . "transient/levels.el")
    (transient-values-file       . "transient/values.el")
    (tramp-persistency-file-name . "tramp")
    (multisession-directory      . "multisession/")
    (url-configuration-directory . "url/")
    ;; Directories (resolution-only; not variables):
    (auto-saves                  . "auto-saves/")
    (auto-saves-sessions         . "auto-saves/sessions/"))
  "Alist of (KEY . RELATIVE-PATH) under `my/cache-directory'.
A trailing slash marks a directory.")

(defconst my/cache--non-variable-keys '(auto-saves auto-saves-sessions)
  "Keys in `my/cache-paths' used only for path resolution, not as variables.")

(defun my/cache--path (key)
  "Return the absolute path for KEY in `my/cache-paths'."
  (let ((rel (cdr (assq key my/cache-paths))))
    (unless rel (error "my/cache--path: unknown key %S" key))
    (expand-file-name rel my/cache-directory)))

(defun my/cache--ensure-dirs ()
  "Create every directory referenced by `my/cache-paths'."
  (dolist (entry my/cache-paths)
    (let* ((abs (my/cache--path (car entry)))
           (dir (if (directory-name-p abs) abs (file-name-directory abs))))
      (make-directory dir t))))

(defun my/cache-wire ()
  "Point every variable-named KEY in `my/cache-paths' at its resolved path."
  (dolist (entry my/cache-paths)
    (let ((key (car entry)))
      (unless (memq key my/cache--non-variable-keys)
        (funcall (or (get key 'custom-set) #'set-default-toplevel-value)
                 key (my/cache--path key)))))
  ;; auto-save uses transforms/prefix, not single-value vars:
  (setq auto-save-list-file-prefix (my/cache--path 'auto-saves-sessions)
        auto-save-file-name-transforms
        `((".*" ,(my/cache--path 'auto-saves) t))))

(my/cache--ensure-dirs)
(my/cache-wire)

(provide 'my-cache)
;;; my-cache.el ends here
