;;; my-eshell.el --- eshell prompt and tweaks  -*- lexical-binding: t; -*-
;;; Commentary:
;;; Code:

;; ===============================================================
;;; GIT SEGMENT

(defun my/eshell--git-call (&rest args)
  "Run git with ARGS in `default-directory'; return trimmed stdout, or nil.
Uses `process-file' so it works over TRAMP and spawns no shell."
  (with-temp-buffer
    (when (zerop (apply #'process-file "git" nil '(t nil) nil args))
      (let ((output (string-trim (buffer-string))))
        (unless (string-empty-p output) output)))))

(defun my/eshell--git-branch ()
  "Return the current branch name, or the short SHA when detached."
  (or (my/eshell--git-call "symbolic-ref" "--short" "HEAD")
      (my/eshell--git-call "rev-parse" "--short" "HEAD")))

(defun my/eshell--git-dirty-p ()
  "Return non-nil when the worktree has uncommitted changes."
  (and (my/eshell--git-call "status" "--porcelain") t))

(defun my/eshell--git-segment ()
  "Return a propertized git segment for the prompt, or nil outside a repo."
  (when (and (executable-find "git")
             (locate-dominating-file default-directory ".git"))
    (when-let* ((branch (my/eshell--git-branch)))
      (let ((dirty (my/eshell--git-dirty-p)))
        (concat " "
                (propertize branch 'face (if dirty 'warning 'success))
                (and dirty (propertize "*" 'face 'error)))))))

;; ===============================================================
;;; PROMPT

(defconst my/eshell-prompt-regexp "^[^#$\n]*[#$] "
  "Regexp matching the trailing part of `my/eshell-prompt'.")

(defun my/eshell-prompt ()
  "Return the eshell prompt: abbreviated cwd, git segment, prompt char.
The whole prompt is read-only; input typed after it stays editable."
  (let ((prompt
         (concat
          (propertize (abbreviate-file-name default-directory)
                      'face 'font-lock-keyword-face)
          (or (my/eshell--git-segment) "")
          (propertize (if (= (user-uid) 0) " #" " $") 'face 'default)
          " ")))
    (add-text-properties 0 (length prompt)
                         '(read-only t
                           front-sticky (face read-only)
                           rear-nonsticky (face read-only))
                         prompt)
    prompt))

(provide 'my-eshell)
;;; my-eshell.el ends here
