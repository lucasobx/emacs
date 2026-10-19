;;; my-cache.el --- Centralized cache/state paths  -*- lexical-binding: t; -*-

;; Author: Lucas
;; Keywords: files

;;; Commentary:

;; Redirect the cache, history and state files various packages write into
;; `user-emacs-directory' to a single `my/cache-directory'.

;;; Code:

(defvar my/cache-directory (expand-file-name "cache/" user-emacs-directory)
  "Directory that holds the cache, history and state files.")

(defvar my/cache-paths
  '((transient-history-file      . "transient/history.el")
    (transient-levels-file       . "transient/levels.el")
    (transient-values-file       . "transient/values.el")
    (multisession-directory      . "multisession/")
    (recentf-save-file           . "recentf.eld")
    (save-place-file             . "saveplace")
    (bookmark-default-file       . "bookmarks")
    (project-list-file           . "projects")
    (savehist-file               . "history")
    (tramp-persistency-file-name . "tramp")
    (url-configuration-directory . "url/")
    (mc/list-file                . "mc-lists.el")
    (devdocs-data-dir            . "devdocs/"))
  "Variables to redirect into the cache, as (VARIABLE . PATH).")

(defun my/cache--path (rel)
  "Return the absolute cache path for REL, creating its directory."
  (let ((abs (expand-file-name rel my/cache-directory)))
    (make-directory (if (directory-name-p abs) abs (file-name-directory abs)) t)
    abs))

(defun my/cache-wire ()
  "Redirect `my/cache-paths', auto-saves and tree-sitter to the cache."
  (pcase-dolist (`(,var . ,rel) my/cache-paths)
    (funcall (or (get var 'custom-set) #'set-default-toplevel-value)
             var (my/cache--path rel)))
  ;; auto-save uses transforms/prefix, not single-value vars:
  (setq auto-save-list-file-prefix (my/cache--path "auto-saves/sessions/")
        auto-save-file-name-transforms
        `((".*" ,(my/cache--path "auto-saves/") t)))
  ;; tree-sitter grammars: search and install under cache
  (setq treesit-extra-load-path (list (my/cache--path "tree-sitter/"))))

(my/cache-wire)

(provide 'my-cache)
;;; my-cache.el ends here
