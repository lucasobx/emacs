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

;; ===============================================================
;;; TERMINAL FRAME

(declare-function eshell "eshell")
(defvar eshell-buffer-name)

(defcustom my/eshell-terminal-frame-title "eshell-term"
  "Frame title of the standalone eshell terminal.
Match this title from your compositor's window rules."
  :type 'string
  :group 'my)

(defcustom my/eshell-terminal-hide-mode-line t
  "When non-nil, hide the mode line in the standalone eshell terminal."
  :type 'boolean
  :group 'my)

(defun my/eshell-terminal--exit ()
  "Quit Emacs after the terminal's eshell buffer is killed."
  (run-at-time 0 nil #'kill-emacs))

(defun my/eshell-terminal--setup (dedicated)
  "Strip the current eshell buffer down to a bare terminal.
When DEDICATED is non-nil, killing the buffer quits Emacs."
  (setq-local truncate-lines nil
              header-line-format nil)
  (when my/eshell-terminal-hide-mode-line
    (setq-local mode-line-format nil))
  (set-window-fringes (selected-window) 0 0)
  (when dedicated
    (add-hook 'kill-buffer-hook #'my/eshell-terminal--exit nil t)))

(defun my/eshell-terminal (&optional dedicated)
  "Open a bare Eshell terminal filling the frame.
With DEDICATED non-nil, exiting the shell also quits Emacs; pass it
when launching a throwaway terminal from your compositor."
  (interactive)
  (set-frame-parameter nil 'title my/eshell-terminal-frame-title)
  (let ((eshell-buffer-name (generate-new-buffer-name "*eshell-term*")))
    (eshell))
  (delete-other-windows)
  (my/eshell-terminal--setup dedicated))

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

(defun pcomplete/z ()
  "Completion for the `z' eshell command from the zoxide database."
  (while (pcomplete-here (my/eshell--zoxide-list))))

(provide 'my-eshell)
;;; my-eshell.el ends here
