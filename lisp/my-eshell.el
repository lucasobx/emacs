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
  '(("clear" "clear-scrollback")
    ("gg"    "magit-status")
    ("ff"    "find-file $1")
    ("ll"    "ls -lh $*")
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

;; ===============================================================

  (interactive)
  (set-frame-parameter nil 'title my/eshell-terminal-frame-title)
  (let ((eshell-buffer-name (generate-new-buffer-name "*eshell-term*")))
    (eshell))
  (delete-other-windows)
  (my/eshell-terminal--setup dedicated))
;; ===============================================================
;;; CAT

(declare-function eshell/cat "em-unix")
(declare-function eshell-print "esh-mode")

(defun my/eshell--cat-file-p (arg)
  "Return non-nil when ARG names a readable regular file."
  (and (stringp arg)
       (not (string-prefix-p "-" arg))
       (file-regular-p arg)
       (file-readable-p arg)))

(defun my/eshell--cat-fontified (filename)
  "Return the contents of FILENAME with its major-mode fontification."
  (let ((buffer (get-file-buffer filename)))
    (with-current-buffer (or buffer (find-file-noselect filename t))
      (unwind-protect
          (progn (font-lock-ensure) (buffer-string))
        (unless buffer (kill-buffer))))))

(defun my/eshell-cat-syntax-highlight (orig-fn &rest args)
  "Around advice for `eshell/cat' that syntax-highlights regular files.
Falls back to ORIG-FN for pipelines, flags, and non-file ARGS."
  (let ((files (flatten-tree args)))
    (if (and (not (bound-and-true-p eshell-in-pipeline-p))
             files
             (seq-every-p #'my/eshell--cat-file-p files))
        (progn (dolist (file files)
                 (eshell-print (my/eshell--cat-fontified file)))
               nil)
      (apply orig-fn args))))

(with-eval-after-load 'em-unix
  (advice-add 'eshell/cat :around #'my/eshell-cat-syntax-highlight))

;; ===============================================================
;;; ZOXIDE

(eval-when-compile (require 'pcomplete))
(declare-function eshell/cd "em-dirs")
(declare-function pcomplete--here "pcomplete")

(defcustom my/eshell-zoxide-track t
  "When non-nil, register the working directory with zoxide after each command."
  :type 'boolean
  :group 'my)

(defun my/eshell--zoxide-add (dir)
  "Register DIR in the zoxide database."
  (when (and dir (executable-find "zoxide"))
    (call-process "zoxide" nil 0 nil "add" "--" (expand-file-name dir))))

(defun my/eshell--zoxide-track ()
  "Register `default-directory' with zoxide after each command."
  (when (and my/eshell-zoxide-track
             (not (file-remote-p default-directory))
             (file-directory-p default-directory))
    (my/eshell--zoxide-add default-directory)))

(add-hook 'eshell-post-command-hook #'my/eshell--zoxide-track)

(defun my/eshell--zoxide-args (args)
  "Coerce ARGS to a list of strings."
  (mapcar (lambda (arg) (if (numberp arg) (number-to-string arg) arg)) args))

(defun my/eshell--zoxide-query (keywords)
  "Return the best directory for KEYWORDS, or nil.
A lone keyword naming an existing path is taken literally; otherwise
KEYWORDS are resolved through `zoxide query'."
  (when keywords
    (let ((input (car keywords)))
      (if (and (null (cdr keywords))
               (string-match-p "[/~]" input)
               (file-directory-p (expand-file-name input)))
          (expand-file-name input)
        (when (executable-find "zoxide")
          (with-temp-buffer
            (when (zerop (apply #'call-process "zoxide" nil t nil
                                "query" "--" keywords))
              (let ((dir (string-trim (buffer-string))))
                (and (file-directory-p dir) dir)))))))))

(defun my/eshell--zoxide-list ()
  "Return the zoxide database, best first, home abbreviated."
  (when (executable-find "zoxide")
    (with-temp-buffer
      (when (zerop (call-process "zoxide" nil t nil "query" "--list"))
        (mapcar #'abbreviate-file-name
                (split-string (buffer-string) "\n" t))))))

(defun my/eshell--zoxide-table (dirs)
  "Completion table over DIRS that keeps zoxide's ordering."
  (lambda (string predicate action)
    (if (eq action 'metadata)
        '(metadata (display-sort-function . identity)
                   (category . file))
      (complete-with-action action dirs string predicate))))

(defun my/eshell--zoxide-pick ()
  "Pick a directory from the zoxide database via completion, best first."
  (let ((dirs (my/eshell--zoxide-list)))
    (cond ((null dirs) nil)
          ((null (cdr dirs)) (car dirs))
          (t (completing-read "zoxide: " (my/eshell--zoxide-table dirs) nil t)))))

(defun my/eshell--zoxide-jump (dir keywords)
  "Change to DIR, or signal that KEYWORDS produced no match."
  (if dir
      (eshell/cd dir)
    (user-error "No zoxide match%s"
                (if keywords
                    (format " for: %s" (mapconcat #'identity keywords " "))
                  ""))))

(defun eshell/z (&rest args)
  "Jump to a directory tracked by zoxide.
With no ARGS, pick interactively from the whole database; otherwise
jump to the best match for ARGS."
  (unless (executable-find "zoxide")
    (user-error "zoxide not found"))
  (let ((keywords (my/eshell--zoxide-args args)))
    (my/eshell--zoxide-jump
     (if keywords (my/eshell--zoxide-query keywords) (my/eshell--zoxide-pick))
     keywords)))

(defun my/eshell-cd-zoxide-fallback (orig-fn &rest args)
  "Around advice for `eshell/cd': on a miss, retry ARGS via zoxide.
ORIG-FN is the native `cd'. Re-signal its error when zoxide finds nothing."
  (condition-case err
      (apply orig-fn args)
    (error
     (let* ((keywords (my/eshell--zoxide-args (flatten-tree args)))
            (dir (and keywords
                      (executable-find "zoxide")
                      (my/eshell--zoxide-query keywords))))
       (if dir
           (funcall orig-fn dir)
         (signal (car err) (cdr err)))))))

(advice-add 'eshell/cd :around #'my/eshell-cd-zoxide-fallback)

(defun pcomplete/z ()
  "Completion for the `z' eshell command from the zoxide database."
  (while (pcomplete-here (my/eshell--zoxide-list))))

(provide 'my-eshell)
;;; my-eshell.el ends here
