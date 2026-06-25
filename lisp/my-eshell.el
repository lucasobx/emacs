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

(defun my/eshell--git-status-lines ()
  "Return porcelain status lines for the worktree, or nil when clean."
  (when-let* ((out (my/eshell--git-call "status" "--porcelain")))
    (split-string out "\n" t)))

(defun my/eshell--git-tracked-dirty-p (lines)
  "Return non-nil when LINES show changes to tracked files.
Untracked entries are ignored so they color the branch as clean."
  (seq-some (lambda (line) (not (string-prefix-p "??" line))) lines))

(defun my/eshell--git-segment ()
  "Return a propertized git segment for the prompt, or nil outside a repo."
  (when (and (executable-find "git")
             (locate-dominating-file default-directory ".git"))
    (when-let* ((branch (my/eshell--git-branch)))
      (let* ((lines (my/eshell--git-status-lines))
             (dirty (my/eshell--git-tracked-dirty-p lines)))
        (concat " "
                (propertize branch 'face (if dirty 'warning 'success))
                (and lines (propertize "*" 'face 'error)))))))

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

;; ===============================================================
;;; ALIASES

(defvar eshell-command-aliases-list)
(declare-function eshell-write-aliases-list "em-alias")

(defvar my/eshell-aliases
  '(("git"   "*git -c color.ui=always $*")
    ("clear" "clear-scrollback")
    ("gg"    "magit-status")
    ("f"     "find-file $1")
    ("l"     "ls -lh $*")
    ("d"     "dired $1")
    ("q"     "exit"))
  "Eshell command aliases.")

(defun my/eshell-set-aliases ()
  "Install `my/eshell-aliases', overriding any matching existing alias."
  (dolist (alias my/eshell-aliases)
    (setq eshell-command-aliases-list
          (cons alias (assoc-delete-all (car alias)
                                        eshell-command-aliases-list)))))

;; never persist aliases to disk
(with-eval-after-load 'em-alias
  (advice-add #'eshell-write-aliases-list :override #'ignore))

;; run after `eshell-read-aliases-list', so these take precedence
(add-hook 'eshell-mode-hook #'my/eshell-set-aliases)

(provide 'my-eshell)
;;; my-eshell.el ends here
