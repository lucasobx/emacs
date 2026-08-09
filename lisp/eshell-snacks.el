;;; eshell-snacks.el --- Eshell utilities -*- lexical-binding: t; -*-

;; Author: Lucas
;; Version: 0.1.0
;; Package-Requires: ((emacs "31.0"))
;; Keywords: processes, convenience

;;; Commentary:

;; A bundle of small Eshell enhancements:
;; prompt   - compact cwd with a cached git status segment
;; history  - shared history merged across all Eshell buffers
;; complete - history and completion with inline previews
;; validate - highlights valid and invalid commands
;; visual   - keeps finished visual commands readable and dismissible with `q'
;; silent   - suppresses echoes of returned buffers and windows
;; cat      - regular files are printed with syntax highlighting
;; unpack   - extract an archive by its extension
;; z        - zoxide jumping with `cd' fallback
;; aliases  - session-only Eshell aliases
;; env      - pager-free environment with colored git and Emacs as EDITOR

;;; Code:

(eval-when-compile
  (require 'ring)
  (require 'em-hist)
  (require 'pcomplete)
  (require 'completion-preview))

(declare-function eshell-read-history "em-hist")
(declare-function eshell-write-history "em-hist")
(declare-function eshell-write-aliases-list "em-alias")
(declare-function eshell/cat "em-unix")
(declare-function eshell/cd "em-dirs")
(declare-function eshell-print "esh-mode")
(declare-function eshell-named-command "esh-cmd")
(declare-function eshell-wait-for-processes "esh-proc")
(declare-function eshell-stringify "esh-util")
(declare-function eshell-stringify-list "esh-util")
(declare-function pcomplete-entries "pcomplete")
(declare-function ring-elements "ring")
(declare-function pcomplete--here "pcomplete")
(declare-function completion-preview-mode "completion-preview")
(defvar eshell-history-file-name)
(defvar eshell-prompt-function)
(defvar eshell-history-ring)
(defvar eshell-last-output-end)
(defvar eshell-command-aliases-list)
(defvar completion-preview-completion-styles)
(defvar completion-preview-minimum-symbol-length)

(defgroup eshell-snacks nil
  "Small Eshell enhancements."
  :group 'eshell
  :prefix "eshell-snacks-")

;; ===============================================================
;;; DISPLAY

(defun eshell-snacks--setup-display ()
  "Tune the current eshell buffer's display."
  (setq-local scroll-margin 0)
  (visual-line-mode -1)
  (setf (alist-get 'continuation fringe-indicator-alist) nil)
  (setf (alist-get 'truncation  fringe-indicator-alist) nil))

(defun eshell-snacks-term-reset-scrolling ()
  "Zero the scrolling variables in term-like buffers."
  (setq-local scroll-conservatively 0)
  (setq-local scroll-margin 0)
  (setq-local scroll-step 0))

;; ===============================================================
;;; ENVIRONMENT

;; Buffer-local, so visual commands in `term' keep their own pager.
;; `color.ui=always' colors git without a TTY.
(defun eshell-snacks--setup-environment ()
  "Give this eshell buffer a pager-free environment with colored git."
  (setq-local process-environment
              (append '("PAGER=cat"
                        "GIT_CONFIG_COUNT=1"
                        "GIT_CONFIG_KEY_0=color.ui"
                        "GIT_CONFIG_VALUE_0=always")
                      process-environment)))

(defvar eshell-snacks--saved-editors nil
  "Alist of editor env vars saved before `eshell-snacks-mode' changed them.")

(defun eshell-snacks--set-editors ()
  "Point EDITOR and GIT_EDITOR at this Emacs, saving the old values."
  (let ((editor (format "emacs --init-directory=%s"
                        (shell-quote-argument
                         (expand-file-name user-emacs-directory)))))
    (dolist (var '("EDITOR" "GIT_EDITOR"))
      (push (cons var (getenv var)) eshell-snacks--saved-editors)
      (setenv var editor))))

(defun eshell-snacks--restore-editors ()
  "Restore EDITOR and GIT_EDITOR to their pre-mode values."
  (pcase-dolist (`(,var . ,value) eshell-snacks--saved-editors)
    (setenv var value))
  (setq eshell-snacks--saved-editors nil))

;; ===============================================================
;;; GIT SEGMENT

(defun eshell-snacks--git-call (&rest args)
  "Run git with ARGS in `default-directory'.  Return trimmed stdout, or nil.
Uses `process-file', so it works over TRAMP."
  (with-temp-buffer
    (when (zerop (apply #'process-file "git" nil '(t nil) nil args))
      (let ((output (string-trim (buffer-string))))
        (unless (string-empty-p output) output)))))

(defun eshell-snacks--git-branch ()
  "Return the current branch name, or the short SHA when detached."
  (or (eshell-snacks--git-call "symbolic-ref" "--short" "HEAD")
      (eshell-snacks--git-call "rev-parse" "--short" "HEAD")))

(defun eshell-snacks--git-status-lines ()
  "Return porcelain status lines for the worktree, or nil when clean."
  (when-let* ((out (eshell-snacks--git-call "status" "--porcelain")))
    (split-string out "\n" t)))

(defun eshell-snacks--git-tracked-dirty-p (lines)
  "Return non-nil when LINES show changes to tracked files.
Untracked entries are ignored, so they leave the branch clean."
  (seq-some (lambda (line) (not (string-prefix-p "??" line))) lines))

(defcustom eshell-snacks-git-cache-ttl 2
  "Seconds the git prompt segment stays cached before it is recomputed."
  :type 'number :group 'eshell-snacks)

(defvar eshell-snacks--git-cache nil
  "Last computed git segment data, a plist, or nil.")
(defvar eshell-snacks--git-cache-root nil
  "Git root the cached data was computed for.")
(defvar eshell-snacks--git-cache-time 0
  "Time the cache was last computed.")

(defun eshell-snacks--git-compute ()
  "Return fresh git segment data as a plist, or nil when there is no branch."
  (when-let* ((branch (eshell-snacks--git-branch)))
    (let ((lines (eshell-snacks--git-status-lines)))
      (list :branch branch
            :any (and lines t)
            :dirty (and lines (eshell-snacks--git-tracked-dirty-p lines))))))

(defun eshell-snacks--git-data ()
  "Return git segment data for `default-directory', cached briefly.
Recomputes on a new git root or past `eshell-snacks-git-cache-ttl'."
  (when-let* ((root (locate-dominating-file default-directory ".git")))
    (let ((now (float-time)))
      (unless (and (equal root eshell-snacks--git-cache-root)
                   (< (- now eshell-snacks--git-cache-time) eshell-snacks-git-cache-ttl))
        (setq eshell-snacks--git-cache-root root
              eshell-snacks--git-cache-time now
              eshell-snacks--git-cache (eshell-snacks--git-compute)))
      eshell-snacks--git-cache)))

(defun eshell-snacks--git-segment ()
  "Return a propertized git segment for the prompt, or nil outside a repo."
  (when (executable-find "git")
    (when-let* ((data (eshell-snacks--git-data)))
      (concat " "
              (propertize (plist-get data :branch)
                          'face (if (plist-get data :dirty) 'warning 'success))
              (and (plist-get data :any) (propertize "*" 'face 'error))))))

;; ===============================================================
;;; PROMPT

(defun eshell-snacks-prompt ()
  "Return the eshell prompt: abbreviated cwd, git segment, prompt char."
  (concat
   (propertize (abbreviate-file-name default-directory)
               'face 'font-lock-keyword-face)
   (or (eshell-snacks--git-segment) "")
   (propertize (if (= (user-uid) 0) " #" " $") 'face 'default)
   " "))

(defvar eshell-snacks--saved-prompt-function 'unset
  "Prompt function replaced by the mode.  `unset' means it was unbound.")

;; Setting this before `em-prompt' loads is enough: `defcustom' keeps an
;; existing value instead of overwriting it.
(defun eshell-snacks--set-prompt ()
  "Make eshell use `eshell-snacks-prompt', saving the old one."
  (setq eshell-snacks--saved-prompt-function
        (if (boundp 'eshell-prompt-function) eshell-prompt-function 'unset))
  (setq eshell-prompt-function #'eshell-snacks-prompt))

(defun eshell-snacks--restore-prompt ()
  "Restore `eshell-prompt-function' to its pre-mode value.
With nothing to put back, eshell's own default is restored."
  (if (not (eq eshell-snacks--saved-prompt-function 'unset))
      (setq eshell-prompt-function eshell-snacks--saved-prompt-function)
    (when-let* ((standard (get 'eshell-prompt-function 'standard-value)))
      (setq eshell-prompt-function (eval (car standard) t))))
  (setq eshell-snacks--saved-prompt-function 'unset))

;; ===============================================================
;;; ALIASES

(defvar eshell-snacks-aliases
  '(("clear" "clear-scrollback")
    ("g"     "magit-status")
    ("f"     "find-file $1")
    ("l"     "ls -lh $*")
    ("d"     "dired $1")
    ("q"     "exit"))
  "Eshell command aliases.")

(defun eshell-snacks-set-aliases ()
  "Install `eshell-snacks-aliases', overriding any matching existing alias."
  (dolist (alias eshell-snacks-aliases)
    (setq eshell-command-aliases-list
          (cons alias (assoc-delete-all (car alias)
                                        eshell-command-aliases-list)))))

;; ===============================================================
;;; SILENT UI RESULTS

;; Eshell echoes a Lisp command's return value, so `magit-status' and
;; friends print their "#<buffer ...>".  `eshell-print-maybe-n' prints
;; that value and nothing else, so ordinary values keep echoing.

(defun eshell-snacks--ui-object-p (object)
  "Return non-nil when OBJECT is an interface object not worth echoing."
  (or (bufferp object) (windowp object) (framep object)))

(defun eshell-snacks--suppress-ui-result (orig-fn object)
  "Call ORIG-FN on OBJECT unless it is an interface object."
  (unless (eshell-snacks--ui-object-p object)
    (funcall orig-fn object)))

;; ===============================================================
;;; VALIDATE COMMAND

(defface eshell-snacks-valid-command '((t :inherit success))
  "Face for a command that eshell can run."
  :group 'eshell-snacks)

(defface eshell-snacks-invalid-command '((t :inherit error))
  "Face for a command that eshell cannot find."
  :group 'eshell-snacks)

(defun eshell-snacks--command-valid-p (command)
  "Return non-nil when COMMAND is something eshell can run.
Covers programs, aliases, builtins, elisp functions and paths."
  (or (member command '("." ".." "exit"))
      (and (executable-find command) t)
      (assoc command (bound-and-true-p eshell-command-aliases-list))
      (fboundp (intern-soft (concat "eshell/" command)))
      (functionp (intern-soft command))
      (file-exists-p (expand-file-name command))))

(defun eshell-snacks--validate-command ()
  "Fontify the first word of the current input by command validity."
  (when (eq major-mode 'eshell-mode)
    (save-excursion
      (goto-char eshell-last-output-end)
      (when (re-search-forward "\\=[[:space:]]*\\([^[:space:]]+\\)"
                               (line-end-position) t)
        (let ((beg (match-beginning 1))
              (end (match-end 1))
              (command (match-string 1)))
          (with-silent-modifications
            (put-text-property
             beg end 'face
             (if (eshell-snacks--command-valid-p command)
                 'eshell-snacks-valid-command
               'eshell-snacks-invalid-command))
            (put-text-property beg end 'rear-nonsticky t)))))))

(defun eshell-snacks--setup-validate ()
  "Enable command validation in the current eshell buffer."
  (add-hook 'post-command-hook #'eshell-snacks--validate-command nil t))

;; ===============================================================
;;; HISTORY

;; Every buffer's ring is merged with the file on save, so no session's
;; history is lost.  All of it feeds the completion candidates below.

(defun eshell-snacks--history-from-buffers ()
  "Return the history entries held by every live eshell buffer."
  (mapcan (lambda (buf)
            (with-current-buffer buf
              (when (and (derived-mode-p 'eshell-mode)
                         (bound-and-true-p eshell-history-ring))
                (ring-elements eshell-history-ring))))
          (buffer-list)))

(defun eshell-snacks--history-file ()
  "Return the eshell history file, or nil if `em-hist' hasn't loaded.
Guarded so saving on `kill-emacs-hook' works without any eshell."
  (bound-and-true-p eshell-history-file-name))

(defun eshell-snacks--history-from-file ()
  "Return the history entries saved on disk, if any."
  (when-let* ((file (eshell-snacks--history-file))
              ((file-exists-p file)))
    (with-temp-buffer
      (insert-file-contents file)
      (split-string (buffer-string) "\n" t))))

(defun eshell-snacks--history-entries ()
  "Return merged history from all buffers and disk, to be saved back.
Excludes the external shells, which are never written to."
  (seq-uniq
   (seq-filter (lambda (s) (and (stringp s) (not (string-empty-p s))))
               (append (eshell-snacks--history-from-buffers)
                       (eshell-snacks--history-from-file)))))

(defcustom eshell-snacks-external-history-files
  '("~/.bash_history" "~/.zsh_history")
  "Shell history files offered as completions besides eshell's own.
Read only, never written back.  Zsh timestamp prefixes
\(\":1700000000:0;\") are stripped."
  :type '(repeat file)
  :group 'eshell-snacks)

(defun eshell-snacks--history-from-external ()
  "Return history entries from `eshell-snacks-external-history-files'."
  (mapcan
   (lambda (file)
     (when (file-readable-p (expand-file-name file))
       (with-temp-buffer
         (insert-file-contents (expand-file-name file))
         ;; Strip zsh's extended-history timestamp prefix.
         (goto-char (point-min))
         (while (re-search-forward "^: [0-9]+:[0-9]+;" nil t)
           (replace-match ""))
         (split-string (buffer-string) "\n" t))))
   eshell-snacks-external-history-files))

(defun eshell-snacks--history-dir (file)
  "Return the directory of FILE, created if needed."
  (let ((dir (file-name-directory file)))
    (when (and dir (not (file-directory-p dir)))
      (make-directory dir t))
    dir))

(defun eshell-snacks-save-merged-history ()
  "Save every eshell buffer's history, merged, to the history file."
  (when-let* ((file (eshell-snacks--history-file)))
    (when (eshell-snacks--history-dir file)
      (with-temp-file file
        (insert (mapconcat #'identity (eshell-snacks--history-entries) "\n"))))))

(defun eshell-snacks-load-history ()
  "Load the shared history file into this buffer's ring, if it exists."
  (when-let* ((file (eshell-snacks--history-file))
              ((file-exists-p file)))
    (eshell-read-history file t)))

(defun eshell-snacks--history-recent-first ()
  "Return merged history ordered newest first, for completion."
  (seq-uniq
   (seq-filter (lambda (s) (and (stringp s) (not (string-empty-p s))))
               (append (eshell-snacks--history-from-buffers)
                       (nreverse (eshell-snacks--history-from-file))
                       (nreverse (eshell-snacks--history-from-external))))))

;; ===============================================================
;;; AUTO-SUGGESTION

;; A capf over whole history lines, feeding completion at point and the
;; native `completion-preview'.  It runs ahead of eshell's own pcomplete
;; capf, and `:exclusive' no falls through to it when nothing matches.

(defun eshell-snacks--history-capf ()
  "Completion-at-point function over the whole input line's history.
The most recent matching entry is offered first."
  (when (derived-mode-p 'eshell-mode)
    (let ((beg (marker-position eshell-last-output-end))
          (end (point)))
      (when (>= end beg)
        (let* ((input (buffer-substring-no-properties beg end))
               (candidates (seq-filter (lambda (s) (string-prefix-p input s))
                                       (eshell-snacks--history-recent-first))))
          (when candidates
            (list beg end
                  (eshell-snacks--autosuggest-table candidates)
                  :exclusive 'no)))))))

(defun eshell-snacks--autosuggest-table (candidates)
  "Completion table over CANDIDATES that preserves their exact order.
Unlike `complete-with-action', `all-completions' keeps that order,
so the newest match is offered first."
  (lambda (string predicate action)
    (cond
     ((eq action 'metadata) '(metadata (display-sort-function . identity)))
     ((eq action t)
      (seq-filter (lambda (c)
                    (and (string-prefix-p string c)
                         (or (null predicate) (funcall predicate c))))
                  candidates))
     ((null action) (try-completion string candidates predicate))
     ((eq action 'lambda) (test-completion string candidates predicate))
     ((eq action 'boundaries) nil))))

(defun eshell-snacks--setup-autosuggest ()
  "Enable history completion in the current eshell buffer."
  (add-hook 'completion-at-point-functions
            #'eshell-snacks--history-capf -50 t)
  (setq-local completion-preview-completion-styles '(basic)
              completion-preview-minimum-symbol-length nil)
  (completion-preview-mode 1))

;; ===============================================================
;;; CAT

(defun eshell-snacks--cat-file-p (arg)
  "Return non-nil when ARG names a readable regular file."
  (and (stringp arg)
       (not (string-prefix-p "-" arg))
       (file-regular-p arg)
       (file-readable-p arg)))

(defun eshell-snacks--cat-fontified (filename)
  "Return the contents of FILENAME with its major-mode fontification."
  (let ((buffer (get-file-buffer filename)))
    (with-current-buffer (or buffer (find-file-noselect filename t))
      (unwind-protect
          (progn (font-lock-ensure) (buffer-string))
        (unless buffer (kill-buffer))))))

(defun eshell-snacks-cat-syntax-highlight (orig-fn &rest args)
  "Around advice for `eshell/cat' that syntax-highlights regular files.
Falls back to ORIG-FN for pipelines, flags, and non-file ARGS."
  (let ((files (flatten-tree args)))
    (if (and (not (bound-and-true-p eshell-in-pipeline-p))
             files
             (seq-every-p #'eshell-snacks--cat-file-p files))
        (progn (dolist (file files)
                 (eshell-print (eshell-snacks--cat-fontified file)))
               nil)
      (apply orig-fn args))))

;; ===============================================================
;;; UNPACK

(defcustom eshell-snacks-unpack-alist
  ;; tar detects the compression itself, so one entry covers every
  ;; flavor, including ones not spelled out here.
  '(("\\.\\(?:tar\\(?:\\.[[:alnum:]]+\\)?\\|t[bg]z2?\\|txz\\|tzst\\)\\'"
     "tar" "xf")
    ("\\.bz2\\'"  "bunzip2")
    ("\\.gz\\'"   "gunzip")
    ("\\.xz\\'"   "unxz")
    ("\\.zst\\'"  "unzstd")
    ("\\.zip\\'"  "unzip")
    ("\\.rar\\'"  "unrar" "x")
    ("\\.7z\\'"   "7z" "x")
    ("\\.Z\\'"    "uncompress"))
  "How to unpack a file, matched by regexp against its name.
Each entry is (REGEXP PROGRAM ARGS...).  The file is appended last."
  :type '(alist :key-type regexp :value-type (repeat string))
  :group 'eshell-snacks)

(defun eshell-snacks--unpack-command (file)
  "Return the (PROGRAM ARGS...) that unpacks FILE, or nil when unknown."
  (cdr (seq-find (lambda (entry) (string-match-p (car entry) file))
                 eshell-snacks-unpack-alist)))

;; A Lisp command's return value is echoed, never awaited, so the
;; process from `eshell-named-command' is swallowed and waited on here.
;; Otherwise it prints as "#<process unzip>" and the prompt lands
;; ahead of the output.
(defun eshell/unpack (file &rest args)
  "Unpack FILE using the right program for its extension.
Extra ARGS are passed to that program before FILE."
  (unless (stringp file)
    (setq file (eshell-stringify file)))
  (unless (file-exists-p file)
    (user-error "No such file: %s" file))
  (let ((command (eshell-snacks--unpack-command file)))
    (unless command
      (user-error "Don't know how to unpack: %s" file))
    (unless (executable-find (car command))
      (user-error "Program not found: %s" (car command)))
    (let ((result (eshell-named-command
                   (car command)
                   (append (cdr command)
                           (eshell-stringify-list (flatten-tree args))
                           (list file)))))
      (eshell-wait-for-processes
       (seq-filter #'processp (flatten-tree (list result)))))
    nil))

(defun eshell-snacks--unpack-regexp ()
  "Return a regexp matching every name `unpack' can extract.
Candidates ending in a slash match too, so directories stay open."
  (concat "/\\'\\|" (mapconcat #'car eshell-snacks-unpack-alist "\\|")))

(defun pcomplete/unpack ()
  "Completion for the `unpack' eshell command: archives and directories."
  (pcomplete-here (pcomplete-entries (eshell-snacks--unpack-regexp))))

;; ===============================================================
;;; ZOXIDE

(defcustom eshell-snacks-zoxide-track t
  "When non-nil, register the working directory with zoxide after each command."
  :type 'boolean
  :group 'eshell-snacks)

(defun eshell-snacks--zoxide-add (dir)
  "Register DIR in the zoxide database."
  (when (and dir (executable-find "zoxide"))
    (call-process "zoxide" nil 0 nil "add" "--" (expand-file-name dir))))

(defun eshell-snacks--zoxide-track ()
  "Register `default-directory' with zoxide after each command."
  (when (and eshell-snacks-zoxide-track
             (not (file-remote-p default-directory))
             (file-directory-p default-directory))
    (eshell-snacks--zoxide-add default-directory)))

(defun eshell-snacks--zoxide-args (args)
  "Coerce ARGS to a list of strings."
  (mapcar (lambda (arg) (if (numberp arg) (number-to-string arg) arg)) args))

(defun eshell-snacks--zoxide-query (keywords)
  "Return the best directory for KEYWORDS, or nil.
A lone keyword naming an existing path is taken literally, the rest
go through `zoxide query'."
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

(defun eshell-snacks--zoxide-list ()
  "Return the zoxide database, best first, home abbreviated."
  (when (executable-find "zoxide")
    (with-temp-buffer
      (when (zerop (call-process "zoxide" nil t nil "query" "--list"))
        (mapcar #'abbreviate-file-name
                (split-string (buffer-string) "\n" t))))))

(defun eshell-snacks--zoxide-table (dirs)
  "Completion table over DIRS that keeps zoxide's ordering."
  (lambda (string predicate action)
    (if (eq action 'metadata)
        '(metadata (display-sort-function . identity)
                   (category . file))
      (complete-with-action action dirs string predicate))))

(defun eshell-snacks--zoxide-pick ()
  "Pick a directory from the zoxide database via completion, best first."
  (let ((dirs (eshell-snacks--zoxide-list)))
    (cond ((null dirs) nil)
          ((null (cdr dirs)) (car dirs))
          (t (completing-read "zoxide: " (eshell-snacks--zoxide-table dirs) nil t)))))

(defun eshell-snacks--zoxide-jump (dir keywords)
  "Change to DIR, or signal that KEYWORDS produced no match."
  (if dir
      (eshell/cd dir)
    (user-error "No zoxide match%s"
                (if keywords
                    (format " for: %s" (mapconcat #'identity keywords " "))
                  ""))))

(defun eshell/z (&rest args)
  "Jump to a directory tracked by zoxide.
With no ARGS, pick interactively from the whole database, otherwise
jump to the best match for ARGS."
  (unless (executable-find "zoxide")
    (user-error "Cannot find zoxide"))
  (let ((keywords (eshell-snacks--zoxide-args args)))
    (eshell-snacks--zoxide-jump
     (if keywords (eshell-snacks--zoxide-query keywords) (eshell-snacks--zoxide-pick))
     keywords)))

(defun eshell-snacks-cd-zoxide-fallback (orig-fn &rest args)
  "Around advice for `eshell/cd': on a miss, retry ARGS via zoxide.
ORIG-FN is the native `cd', whose error is re-signaled on no match."
  (condition-case err
      (apply orig-fn args)
    (error
     (let* ((keywords (eshell-snacks--zoxide-args (flatten-tree args)))
            (dir (and keywords
                      (executable-find "zoxide")
                      (eshell-snacks--zoxide-query keywords))))
       (if dir
           (funcall orig-fn dir)
         (signal (car err) (cdr err)))))))

(defun pcomplete/z ()
  "Completion for the `z' eshell command from the zoxide database."
  (while (pcomplete-here (eshell-snacks--zoxide-list))))

;; ===============================================================
;;; minor mode

(defun eshell-snacks--enable ()
  "Install every hook and advice the mode owns."
  (eshell-snacks--set-editors)
  (eshell-snacks--set-prompt)
  (add-hook 'term-mode-hook #'eshell-snacks-term-reset-scrolling)
  (add-hook 'eshell-mode-hook #'eshell-snacks--setup-display)
  (add-hook 'eshell-mode-hook #'eshell-snacks--setup-environment)
  (add-hook 'eshell-mode-hook #'eshell-snacks-set-aliases)
  (add-hook 'eshell-mode-hook #'eshell-snacks-load-history)
  (add-hook 'eshell-mode-hook #'eshell-snacks--setup-validate)
  (add-hook 'eshell-mode-hook #'eshell-snacks--setup-autosuggest)
  (add-hook 'eshell-exit-hook #'eshell-snacks-save-merged-history)
  (add-hook 'eshell-post-command-hook #'eshell-snacks--zoxide-track)
  (add-hook 'kill-emacs-hook #'eshell-snacks-save-merged-history)
  (advice-add 'eshell-print-maybe-n :around #'eshell-snacks--suppress-ui-result)
  (advice-add 'eshell-write-aliases-list :override #'ignore)
  (advice-add 'eshell-write-history :override #'ignore)
  (advice-add 'eshell/cat :around #'eshell-snacks-cat-syntax-highlight)
  (advice-add 'eshell/cd :around #'eshell-snacks-cd-zoxide-fallback))

(defun eshell-snacks--disable ()
  "Undo `eshell-snacks--enable'."
  (eshell-snacks--restore-editors)
  (eshell-snacks--restore-prompt)
  (remove-hook 'term-mode-hook #'eshell-snacks-term-reset-scrolling)
  (remove-hook 'eshell-mode-hook #'eshell-snacks--setup-display)
  (remove-hook 'eshell-mode-hook #'eshell-snacks--setup-environment)
  (remove-hook 'eshell-mode-hook #'eshell-snacks-set-aliases)
  (remove-hook 'eshell-mode-hook #'eshell-snacks-load-history)
  (remove-hook 'eshell-mode-hook #'eshell-snacks--setup-validate)
  (remove-hook 'eshell-mode-hook #'eshell-snacks--setup-autosuggest)
  (remove-hook 'eshell-exit-hook #'eshell-snacks-save-merged-history)
  (remove-hook 'eshell-post-command-hook #'eshell-snacks--zoxide-track)
  (remove-hook 'kill-emacs-hook #'eshell-snacks-save-merged-history)
  (advice-remove 'eshell-print-maybe-n #'eshell-snacks--suppress-ui-result)
  (advice-remove 'eshell-write-aliases-list #'ignore)
  (advice-remove 'eshell-write-history #'ignore)
  (advice-remove 'eshell/cat #'eshell-snacks-cat-syntax-highlight)
  (advice-remove 'eshell/cd #'eshell-snacks-cd-zoxide-fallback))

;;;###autoload
(define-minor-mode eshell-snacks-mode
  "Toggle the Eshell enhancements globally."
  :global t
  :group 'eshell-snacks
  (if eshell-snacks-mode
      (eshell-snacks--enable)
    (eshell-snacks--disable)))

(provide 'eshell-snacks)
;;; eshell-snacks.el ends here
