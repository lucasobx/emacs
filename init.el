;;; init.el --- Emacs --- -*- lexical-binding: t; no-byte-compile: t; -*-
;; ===============================================================
;;; Commentary:
;;; Code:

(defvar elpaca-installer-version 0.12)
(defvar elpaca-directory (expand-file-name "elpaca/" user-emacs-directory))
(defvar elpaca-builds-directory (expand-file-name "builds/" elpaca-directory))
(defvar elpaca-sources-directory (expand-file-name "sources/" elpaca-directory))
(defvar elpaca-order '(elpaca :repo "https://github.com/progfolio/elpaca.git"
                              :ref nil :depth 1 :inherit ignore
                              :files (:defaults "elpaca-test.el" (:exclude "extensions"))
                              :build (:not elpaca-activate)))
(let* ((repo  (expand-file-name "elpaca/" elpaca-sources-directory))
       (build (expand-file-name "elpaca/" elpaca-builds-directory))
       (order (cdr elpaca-order))
       (default-directory repo))
  (add-to-list 'load-path (if (file-exists-p build) build repo))
  (unless (file-exists-p repo)
    (make-directory repo t)
    (when (<= emacs-major-version 28) (require 'subr-x))
    (condition-case-unless-debug err
        (if-let* ((buffer (pop-to-buffer-same-window "*elpaca-bootstrap*"))
                  ((zerop (apply #'call-process `("git" nil ,buffer t "clone"
                                                  ,@(when-let* ((depth (plist-get order :depth)))
                                                      (list (format "--depth=%d" depth) "--no-single-branch"))
                                                  ,(plist-get order :repo) ,repo))))
                  ((zerop (call-process "git" nil buffer t "checkout"
                                        (or (plist-get order :ref) "--"))))
                  (emacs (concat invocation-directory invocation-name))
                  ((zerop (call-process emacs nil buffer nil "-Q" "-L" "." "--batch"
                                        "--eval" "(byte-recompile-directory \".\" 0 'force)")))
                  ((require 'elpaca))
                  ((elpaca-generate-autoloads "elpaca" repo)))
            (progn (message "%s" (buffer-string)) (kill-buffer buffer))
          (error "%s" (with-current-buffer buffer (buffer-string))))
      ((error) (warn "%s" err) (delete-directory repo 'recursive))))
  (unless (require 'elpaca-autoloads nil t)
    (require 'elpaca)
    (elpaca-generate-autoloads "elpaca" repo)
    (let ((load-source-file-function nil)) (load "./elpaca-autoloads"))))
(add-hook 'after-init-hook #'elpaca-process-queues)
(elpaca `(,@elpaca-order))

(elpaca elpaca-use-package
  (elpaca-use-package-mode))

;; ===============================================================
;;; EMACS

(defvar my/font "TX-02")

(use-package emacs
  :ensure nil
  :init
  (defun display-startup-echo-area-message () (message ""))

  :custom
  ;; startup & ui
  (display-fill-column-indicator-warning nil)
  (warning-minimum-level :emergency)
  (ring-bell-function 'ignore)
  (initial-scratch-message "")
  (inhibit-startup-message t)
  (echo-keystrokes 0.1)
  (use-short-answers t)
  (use-dialog-box nil)

  ;; line numbers
  (display-line-numbers-type 'relative)
  (display-line-numbers-width 4)

  ;; windows & buffer
  (uniquify-buffer-name-style 'forward)
  (ibuffer-show-empty-filter-groups nil)
  (ibuffer-human-readable-size t)

  ;; minibuffer & completion
  (minibuffer-prompt-properties
   '(read-only t cursor-intangible t face minibuffer-prompt))
  (read-extended-command-predicate
   #'command-completion-default-include-p)
  (enable-recursive-minibuffers t)
  (lazy-highlight-initial-delay 0)
  (resize-mini-windows 'grow-only)
  (completion-eager-display 'auto)
  (completion-eager-update t)
  (history-length 25)

  ;; editing
  (save-interprogram-paste-before-kill t)
  (kill-do-not-save-duplicates t)
  (sentence-end-double-space nil)
  (tab-always-indent 'complete)
  (delete-pair-push-mark t)
  (indent-tabs-mode nil)
  (truncate-lines t)
  (undo-no-redo t)
  (tab-width 2)

  ;; treesit
  (treesit-auto-install-grammar 'always)
  (treesit-font-lock-level 4)
  (treesit-enabled-modes t)

  ;; files
  (auto-save-file-name-transforms
   `((".*" ,(expand-file-name "auto-saves/" user-emacs-directory) t)))
  (find-file-suppress-same-file-warnings t)
  (kill-buffer-delete-auto-save-files t)
  (delete-by-moving-to-trash t)
  (auto-save-no-message t)
  (make-backup-files nil)
  (create-lockfiles nil)

  ;; autorevert
  (global-auto-revert-non-file-buffers t)
  (auto-revert-check-vc-info t)

  ;; scroll
  (pixel-scroll-precision-use-momentum nil)
  (mouse-wheel-progressive-speed nil)
  (scroll-preserve-screen-position t)
  (scroll-conservatively 101)
  (scroll-margin 10)
  (scroll-step 1)

  ;; native-comp
  (native-comp-async-query-on-exit t)

  :config
  ;; custom file and directories
  (make-directory (expand-file-name "auto-saves/" user-emacs-directory) t)
  (setq custom-file (locate-user-emacs-file "custom-vars.el"))
  (load custom-file 'noerror 'nomessage)

  ;; modes
  (minibuffer-electric-default-mode 1)
  (minibuffer-depth-indicate-mode 1)
  (global-auto-revert-mode 1)
  (delete-selection-mode 1)
  (file-name-shadow-mode 1)
  (electric-indent-mode 1)
  (global-hl-line-mode -1)
  (electric-pair-mode 1)
  (save-place-mode 1)
  (tooltip-mode -1)
  (savehist-mode 1)
  (recentf-mode 1)

  ;; hooks
  (add-hook 'emacs-startup-hook
          (lambda ()
            (message "Loaded in %s with %d packages."
                     (emacs-init-time) (length (elpaca--queued)))))
  (add-hook 'minibuffer-setup-hook #'cursor-intangible-mode)
  (add-hook 'prog-mode-hook #'display-line-numbers-mode)

  ;; faces
  (set-face-attribute 'tooltip nil :family my/font)
  (set-face-attribute 'default nil :family my/font :height 115 :width 'condensed)
  (set-face-attribute 'minibuffer-nonselected nil :background 'unspecified)

  ;; misc
  (setq redisplay-skip-fontification-on-input t)
  (put 'narrow-to-region 'disabled nil)
  (setq message-truncate-lines t)

  ;; skip internal buffers in switch-to-prev/next-buffer
  (defun skip-these-buffers (_window buffer _bury-or-kill)
    "Function for `switch-to-prev-buffer-skip'."
    (string-match "\\*[^*]+\\*" (buffer-name buffer)))
  (setq switch-to-prev-buffer-skip 'skip-these-buffers)

  ;; smart context clearing and quit handler
  (define-key key-translation-map (kbd "ESC") (kbd "C-g"))
  (define-advice keyboard-quit (:around (quit) quit-context-dwim)
    (cond
     ((and (region-active-p)
           (not (active-minibuffer-window)))
      (funcall quit))
     ((derived-mode-p 'completion-list-mode)
      (delete-completion-window))
     ((active-minibuffer-window)
      (if (minibufferp)
          (minibuffer-keyboard-quit)
        (abort-recursive-edit)))
     (t
      (unless (or defining-kbd-macro executing-kbd-macro)
        (funcall quit)))))

  ;; ensure emacs uses the same path as the login shell
  (defun my/exec-path-from-shell ()
    "Sync `exec-path' and PATH with the login shell asynchronously."
    (interactive)
    (let* ((shell (file-name-nondirectory (or (getenv "SHELL") "")))
           (command (pcase shell
                      ("fish" "fish -c 'string join : $PATH'")
                      ("bash" "bash --login -c 'printenv PATH'")
                      ("zsh"  "zsh -i -c 'printenv PATH'")
                      (_ nil))))
      (if (not command)
          (message ">>> exec-path: unsupported shell `%s'" shell)
        (let ((output ""))
          (make-process
           :name "my-exec-path"
           :buffer nil
           :noquery t
           :connection-type 'pipe
           :command (list shell-file-name shell-command-switch command)
           :filter (lambda (_proc chunk) (setq output (concat output chunk)))
           :sentinel
           (lambda (_proc event)
             (when (string-prefix-p "finished" event)
               (let ((path (string-trim output)))
                 (unless (string-empty-p path)
                   (setenv "PATH" path)
                   (setq exec-path (append (parse-colon-path path)
                                           (list exec-directory)))
                   (setq-default eshell-path-env path))))))))))
  (add-hook 'after-init-hook #'my/exec-path-from-shell)

  :bind
  ("M-d"       . dired-jump)
  ("M-<right>" . end-of-line)
  ("M-<left>"  . my/beginning-of-line)
  ("RET"       . newline-and-indent))

;; ===============================================================
;;; THEMES

;; (use-package pixel-themes
;;   :ensure nil
;;   :load-path "~/.config/emacs/pixel-themes-local"
;;   :config
;;   (pixel-themes-load-theme 'pixel-themes-psygnosia))

(use-package pixel-themes
  :ensure (:host github :repo "lucasobx/pixel-themes"))

(defvar my/theme nil
  "Currently active theme.")

(defun my/theme-list ()
  "Return the available themes, excluding the built-in ones."
  (let ((builtin (expand-file-name "themes" data-directory)))
    (cl-remove-if (lambda (theme)
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
         (current (or (cl-position my/theme themes) -1))
         (next (mod (1+ current) (length themes))))
    (my/load-theme (nth next themes))))

;; restore the saved theme after startup, and persist it on exit.
(add-hook 'elpaca-after-init-hook
          (lambda () (when my/theme (my/load-theme my/theme))))
(add-hook 'kill-emacs-hook
          (lambda () (when my/theme (customize-save-variable 'my/theme my/theme))))

;; ===============================================================
;;; CUSTOM-OPS

;; movement & editing
(defun my/delete-dont-kill ()
  "Delete word backward without adding to kill ring."
  (delete-region (point) (progn (backward-word 1) (point))))

(defun my/backward-delete ()
  "Delete a word, a character, or whitespace."
  (interactive)
  (cond
   ((looking-back (rx (char word)) 1)
    (my/delete-dont-kill))
   ((looking-back (rx (seq (char word) (= 1 blank))) 1)
    (my/delete-dont-kill))
   ((looking-back (rx (char blank)) 1)
    (delete-horizontal-space t))
   (t
    (backward-delete-char-untabify 1))))

(defun my/open-line-below ()
  "Create a new line below and move to it."
  (interactive)
  (end-of-line)
  (newline-and-indent))

(defun my/beginning-of-line ()
  "Go to first non-whitespace char, or column 0 if already there."
  (interactive "^")
  (let ((origin (point)))
    (back-to-indentation)
    (when (= origin (point))
      (beginning-of-line))))

;; delimiter bounds
(defmacro my/define-inside (suffix open)
  "Define an inside-bounds function named from SUFFIX for the OPEN delimiter."
  `(defun ,(intern (format "my/inside-%s" suffix)) ()
     ,(format "Return bounds of content inside %s." suffix)
     (when (or (looking-at ,(regexp-quote open))
               (ignore-errors (backward-up-list 1) t))
       (let ((start (1+ (point)))
             (end   (1- (progn (forward-sexp) (point)))))
         (cons start end)))))

(my/define-inside parens   "(")
(my/define-inside brackets "[")
(my/define-inside braces   "{")

;; generic operations
(defun my/delete-thing (thing)
  "Delete THING at point and save to kill ring with visual feedback."
  (let ((bounds (bounds-of-thing-at-point thing)))
    (when bounds
      (pulse-momentary-highlight-region (car bounds) (cdr bounds))
      (sit-for 0.15)
      (kill-region (car bounds) (cdr bounds)))))

(defun my/delete-inside (bounds-fn)
  "Delete content inside delimiter using BOUNDS-FN with visual feedback."
  (let ((bounds (save-excursion (funcall bounds-fn))))
    (when bounds
      (pulse-momentary-highlight-region (car bounds) (cdr bounds))
      (kill-region (car bounds) (cdr bounds)))))

(defun my/copy-thing (thing)
  "Copy THING at point to kill ring with visual feedback."
  (let ((bounds (bounds-of-thing-at-point thing)))
    (when bounds
      (pulse-momentary-highlight-region (car bounds) (cdr bounds))
      (kill-ring-save (car bounds) (cdr bounds))
      (message "Copied %s" (symbol-name thing)))))

(defun my/copy-inside (bounds-fn)
  "Copy content inside delimiter using BOUNDS-FN with visual feedback."
  (let ((bounds (save-excursion (funcall bounds-fn))))
    (when bounds
      (pulse-momentary-highlight-region (car bounds) (cdr bounds))
      (kill-ring-save (car bounds) (cdr bounds))
      (message "Copied region"))))

(defun my/toggle-comment-thing (thing)
  "Toggle comment on THING at point with visual feedback."
  (let ((bounds (bounds-of-thing-at-point thing)))
    (when bounds
      (let ((start (save-excursion
                     (goto-char (car bounds))
                     (line-beginning-position)))
            (end (save-excursion
                   (goto-char (cdr bounds))
                   (line-end-position))))
        (pulse-momentary-highlight-region start end)
        (sit-for 0.05)
        (comment-or-uncomment-region start end)))))

(defmacro my/define-ops (helper &rest specs)
  "Define interactive commands from SPECS, each calling HELPER with one argument."
  `(progn
     ,@(mapcar
        (lambda (spec)
          (pcase-let ((`(,name ,arg ,doc) spec))
            `(defun ,name ()
               ,doc
               (interactive)
               (,helper ,arg))))
        specs)))

(defmacro my/define-delete-cleanup (name thing)
  "Define command NAME deleting THING at point and clean up whitespace."
  `(defun ,name ()
     ,(format "Delete %s at point, cleaning up leftover whitespace." thing)
     (interactive)
     (let ((bounds (bounds-of-thing-at-point ',thing)))
       (when bounds
         (pulse-momentary-highlight-region (car bounds) (cdr bounds))
         (sit-for 0.15)
         (let ((preceded-by-space (save-excursion
                                    (goto-char (car bounds))
                                    (looking-back "\\s-" 1)))
               (followed-by-space (save-excursion
                                    (goto-char (cdr bounds))
                                    (looking-at "\\s-"))))
           (delete-region (car bounds) (cdr bounds))
           (cond
            (followed-by-space (delete-char 1))
            (preceded-by-space (delete-char -1))))))))

;; delete commands
(my/define-delete-cleanup my/delete-word   word)
(my/define-delete-cleanup my/delete-symbol symbol)

(defun my/delete-line ()
  "Delete line at point, or active region if one exists."
  (interactive)
  (if (use-region-p)
      (progn
        (pulse-momentary-highlight-region (region-beginning) (region-end))
        (sit-for 0.15)
        (kill-region (region-beginning) (region-end))
        (deactivate-mark))
    (my/delete-thing 'line)))

(my/define-ops my/delete-thing
  (my/delete-paragraph 'paragraph "Delete paragraph at point.")
  (my/delete-defun     'defun     "Delete defun at point."))

(my/define-ops my/delete-inside
  (my/delete-in-parens   #'my/inside-parens   "Delete text inside parentheses.")
  (my/delete-in-brackets #'my/inside-brackets "Delete text inside brackets.")
  (my/delete-in-braces   #'my/inside-braces   "Delete text inside braces."))

;; copy commands
(defun my/copy-line ()
  "Copy line at point, or active region if one exists."
  (interactive)
  (if (use-region-p)
      (progn
        (pulse-momentary-highlight-region (region-beginning) (region-end))
        (kill-ring-save (region-beginning) (region-end))
        (deactivate-mark)
        (message "Copied region"))
    (my/copy-thing 'line)))

(my/define-ops my/copy-thing
  (my/copy-paragraph 'paragraph "Copy paragraph at point.")
  (my/copy-word      'word      "Copy word at point.")
  (my/copy-symbol    'symbol    "Copy symbol at point.")
  (my/copy-defun     'defun     "Copy defun at point."))

(my/define-ops my/copy-inside
  (my/copy-inside-parens   #'my/inside-parens   "Copy text inside parentheses.")
  (my/copy-inside-brackets #'my/inside-brackets "Copy text inside brackets.")
  (my/copy-inside-braces   #'my/inside-braces   "Copy text inside braces."))

;; comment commands
(defun my/toggle-comment-line ()
  "Toggle comment on current line."
  (interactive)
  (comment-line 1))

(my/define-ops my/toggle-comment-thing
  (my/toggle-comment-paragraph 'paragraph "Toggle comment on paragraph at point.")
  (my/toggle-comment-defun     'defun     "Toggle comment on defun at point."))

;; ===============================================================
;;; KEYBINDINGS

(use-package which-key
  :ensure nil
  :hook
  (after-init . which-key-mode)
  :config
  (setopt which-key-max-description-length 28
          which-key-add-column-padding 1
          which-key-min-display-lines 6
          which-key-prefix-prefix ""
          which-key-separator " → "
          which-key-idle-delay 0.3)
  (set-face-attribute 'which-key-note-face nil :height 1.0)
  (setopt which-key-sort-order 'which-key-local-then-key-order))

(use-package devil
  :ensure (:host github :repo "fbrosda/devil" :branch "dev")
  :custom
  (devil-highlight-repeatable t)
  (devil-prompt " %t")
  :config
  (global-devil-mode)
  (assoc-delete-all "%k z" devil-translations)
  (add-to-list 'devil-translations '("%k z" . "C-z"))
  (add-to-list 'devil-repeatable-keys
               '("%k . ." "%k . /"))
  (add-to-list 'devil-repeatable-keys ;; delete
               '("%k d s" "%k d d" "%k d p" "%k d f"
                 "%k d w" "%k d (" "%k d [" "%k d {"))
  (add-to-list 'devil-repeatable-keys ;; comment
               '("%k ; ;" "%k ; p" "%k ; f")))

;; --
(defvar my/override-map (make-sparse-keymap))
(define-minor-mode my/override-mode
  "Global minor mode holding my override keybindings."
  :global t :keymap my/override-map)
(add-to-list 'emulation-mode-map-alists `((my/override-mode . ,my/override-map)))
(my/override-mode 1)

(defun my/bind (key command &optional desc)
  "Bind KEY to COMMAND with override precedence, optionally labeling it DESC."
  (keymap-set my/override-map key command)
  (when desc (which-key-add-key-based-replacements key desc)))

(defun my/bind-local (keymap key command &optional desc)
  "Bind KEY to COMMAND in KEYMAP, optionally labeling it DESC in which-key."
  (keymap-set keymap key command)
  (when desc (which-key-add-keymap-based-replacements keymap key desc)))

;; unbind
(dolist (key '("C-<wheel-down>" "C-<wheel-up>" "C-x C-z" "C-c ^" "C-z"))
  (keymap-global-unset key t))
(with-eval-after-load 'elisp-mode
  (dolist (key '("C-c C-b" "C-c C-e" "C-c C-f"))
    (keymap-unset emacs-lisp-mode-map key t)))
(with-eval-after-load 'winner
  (dolist (key '("C-c <left>" "C-c <right>"))
    (keymap-unset winner-mode-map key t)))

;; global (override)
(my/bind "<f1>"          #'scratch-buffer)
(my/bind "<f5>"          #'my/select-theme)
(my/bind "<f6>"          #'my/rotate-theme)
(my/bind "C-<backspace>" #'my/backward-delete)
(my/bind "C-<tab>"       #'other-window)
(my/bind "C-k"           #'kill-buffer-and-window)
(my/bind "C-="           #'er/expand-region)
(my/bind "C-_"           #'text-scale-decrease)
(my/bind "C-+"           #'text-scale-increase)
(my/bind "C-b"           #'consult-buffer)
(my/bind "C-,"           #'popper-toggle)
(my/bind "C-<"           #'popper-cycle)
(my/bind "C-p"           #'yank)
(my/bind "C-z"           #'my/zoxide-dired)
(my/bind "M-o"           #'my/open-line-below)
(my/bind "M-<down>"      #'move-text-down)
(my/bind "M-<up>"        #'move-text-up)
(my/bind "M-j"           #'avy-goto-char-2)
(my/bind "M-k"           #'kill-line)
(my/bind "M-u"           #'upcase-dwim)
(my/bind "M-m"           #'mark-paragraph)
(my/bind "M-l"           #'downcase-dwim)
(my/bind "M-p"           #'duplicate-dwim)
(my/bind "M-c"           #'capitalize-dwim)

;; copy (C-y)
(which-key-add-key-based-replacements "C-y" "copy")
(my/bind "C-y w" #'my/copy-word            "copy word")
(my/bind "C-y s" #'my/copy-symbol          "copy symbol")
(my/bind "C-y y" #'my/copy-line            "copy line")
(my/bind "C-y p" #'my/copy-paragraph       "copy paragraph")
(my/bind "C-y (" #'my/copy-inside-parens   "inside ()")
(my/bind "C-y [" #'my/copy-inside-brackets "inside []")
(my/bind "C-y {" #'my/copy-inside-braces   "inside {}")

;; delete (C-d)
(which-key-add-key-based-replacements "C-d" "delete")
(my/bind "C-d w" #'my/delete-word        "delete word")
(my/bind "C-d s" #'my/delete-symbol      "delete symbol")
(my/bind "C-d d" #'my/delete-line        "delete line")
(my/bind "C-d p" #'my/delete-paragraph   "delete paragraph")
(my/bind "C-d (" #'my/delete-in-parens   "delete inside ()")
(my/bind "C-d [" #'my/delete-in-brackets "delete inside []")
(my/bind "C-d {" #'my/delete-in-braces   "delete inside {}")

;; comment (C-;)
(which-key-add-key-based-replacements "C-;" "comment")
(my/bind "C-; ;" #'my/toggle-comment-line      "line")
(my/bind "C-; p" #'my/toggle-comment-paragraph "paragraph")

;; replace (C-r)
(which-key-add-key-based-replacements "C-r" "replace")
(my/bind "C-r r" #'replace-string "replace string")
(my/bind "C-r q" #'query-replace  "query replace")

;; cursors (C-.)
(which-key-add-key-based-replacements "C-." "cursors")
(my/bind "C-. ." #'mc/mark-next-like-this     "cursor next")
(my/bind "C-. /" #'mc/mark-previous-like-this "cursor prev")
(my/bind "C-. m" #'mc/mark-all-in-region      "cursor region")
(my/bind "C-. l" #'mc/edit-lines              "cursor lines")

;; search (C-s)
(which-key-add-key-based-replacements "C-s" "search")
(my/bind "C-s r" #'consult-recent-file "recent files")
(my/bind "C-s b" #'consult-bookmark    "bookmarks")
(my/bind "C-s g" #'consult-ripgrep     "ripgrep")
(my/bind "C-s t" #'consult-outline     "heading")
(my/bind "C-s i" #'consult-imenu       "imenu")
(my/bind "C-s s" #'consult-line        "line")

;; file (C-f)
(which-key-add-key-based-replacements "C-f" "file")
(my/bind "C-f r" #'rename-visited-file "rename file")
(my/bind "C-f f" #'find-file           "find file")
(my/bind "C-f d" #'consult-fd          "fd-find")
(my/bind "C-f s" #'save-buffer         "save")

;; emacs (C-e)
(which-key-add-key-based-replacements "C-e" "emacs")
(my/bind "C-e i" (lambda () (interactive)
                   (find-file (locate-user-emacs-file "init.el")))
         "open init.el")
(my/bind "C-e s" #'sudo-edit        "edit with sudo")
(my/bind "C-e v" #'visual-line-mode "truncate lines")
(my/bind "C-e r" #'restart-emacs    "restart emacs")

;; remark (C-q)
(which-key-add-key-based-replacements "C-q" "mark")
(my/bind "C-q q" #'org-remark-mark   "highlight region")
(my/bind "C-q d" #'org-remark-delete "highlight delete")
(my/bind "C-q c" #'org-remark-change "highlight change")
(my/bind "C-q o" #'org-remark-open   "open notes")

;; tools (C-t)
(which-key-add-key-based-replacements "C-t" "tools")
(my/bind "C-t t" #'eshell       "terminal")
(my/bind "C-t i" #'ibuffer      "ibuffer")
(my/bind "C-t m" #'magit-status "magit")

;; LSP/prog-mode (C-l)
(which-key-add-keymap-based-replacements prog-mode-map "C-l" "lsp")
(my/bind-local prog-mode-map "C-l d" #'consult-flymake "jump to diagnostic")
(my/bind-local prog-mode-map "C-l n" #'eglot-rename    "rename symbol")

;; dired (M-d)
(with-eval-after-load 'dired
  (my/bind-local dired-mode-map "RET"      #'my/dired-find-file)
  (my/bind-local dired-mode-map "<f2>"     #'wdired-change-to-wdired-mode)
  (my/bind-local dired-mode-map "M-f"      #'dired-create-empty-file)
  (my/bind-local dired-mode-map "M-d"      #'dired-create-directory)
  (my/bind-local dired-mode-map "M-<left>" #'dired-up-directory)
  (my/bind-local dired-mode-map "M-."      #'dired-omit-mode))

;; org (C-o)
(with-eval-after-load 'org
  (which-key-add-keymap-based-replacements org-mode-map "C-o" "org")
  (my/bind-local org-mode-map "C-o t" #'org-hide-drawers-toggle "toggle drawers"))

;; ===============================================================
;;; UI

(use-package window
  :ensure nil
  :custom
  (display-buffer-alist
   '(((derived-mode . magit-mode)
      (display-buffer-in-side-window)
      (side . bottom)
      (slot . 0)
      (window-height . 0.5))
     ((derived-mode . dired-mode)
      (display-buffer-in-side-window)
      (side . bottom)
      (slot . 0)
      (window-height . 0.4))
     ("\\*Ibuffer\\*"
      (display-buffer-in-side-window)
      (side . bottom)
      (slot . 0)
      (window-height . 0.4))
     ("\\*Diff\\*"
      (display-buffer-pop-up-frame)
      (reusable-frames . nil)))))

(use-package popper
  :ensure t
  :defer t
  :init
  (popper-mode +1)
  :custom
  (popper-window-height 13)
  (popper-mode-line "")
  (popper-reference-buffers
   '("\\*eldoc\\*"
     "\\*marginal notes\\*"
     "\\*eshell\\*"
     compilation-mode
     inf-ruby-mode
     devdocs-mode
     helpful-mode
     help-mode)))

(use-package nerd-icons
  :ensure t
  :custom
  (nerd-icons-scale-factor 1.0))

(use-package nerd-icons-dired
  :ensure t
  :hook
  (dired-mode . nerd-icons-dired-mode))

(use-package nerd-icons-ibuffer
  :ensure t
  :hook
  (ibuffer-mode . nerd-icons-ibuffer-mode))

(use-package nerd-icons-completion
  :ensure t
  :after (:all nerd-icons marginalia)
  :config
  (nerd-icons-completion-mode)
  (add-hook 'marginalia-mode-hook #'nerd-icons-completion-marginalia-setup))

(use-package nerd-icons-corfu
  :ensure t
  :after corfu
  :config
  (add-to-list 'corfu-margin-formatters #'nerd-icons-corfu-formatter))

(use-package spacious-padding
  :ensure t
  :config
  (advice-add
   'spacious-padding-set-faces :after
   (lambda (&rest _)
     (set-face-attribute 'mode-line-active nil
                         :inherit 'mode-line)))
  (setopt spacious-padding-widths
          '(:internal-border-width 10
            :right-divider-width 1
            :mode-line-width 1
            :fringe-width 4))
  (spacious-padding-mode 1))

(use-package rainbow-delimiters
  :ensure t
  :hook
  (prog-mode . rainbow-delimiters-mode))

(use-package doom-modeline
  :ensure t
  :custom
  (doom-modeline-buffer-file-name-style 'buffer-name)
  (doom-modeline-project-detection 'project)
  (mode-line-right-align-edge 'right-fringe)
  (doom-modeline-window-width-limit 0)
  (doom-modeline-percent-position nil)
  (doom-modeline-total-line-number t)
  (doom-modeline-buffer-encoding nil)
  (doom-modeline-major-mode-icon t)
  (doom-modeline-check-icon nil)
  (doom-modeline-persp-icon nil)
  (doom-modeline-persp-name nil)
  (doom-modeline-modal-icon t)
  (doom-modeline-height 25)
  (doom-modeline-time nil)
  (doom-modeline-modal t)
  (doom-modeline-icon t)
  :config
  (defun doom-modeline-check-icon (_icon _unicode _text &optional _face) "")
  (setopt doom-modeline-always-show-macro-register t)
  (setopt doom-modeline-buffer-modification-icon nil)
  (add-hook 'doom-modeline-mode-hook
            (lambda ()
              (dolist (face (face-list))
                (when (string-prefix-p "doom-modeline" (symbol-name face))
                  (set-face-attribute face nil :weight 'normal :slant 'normal)))))
  (doom-modeline-mode 1)
  ;; fix doom-modeline leaking mode-line-inactive background into active window.
  (advice-add 'doom-modeline-display-text :override
            (lambda (text)
              (string-replace "%" "%%" text))))

;; (use-package emacs-goose
;;   :ensure nil
;;   :load-path "~/.config/emacs/emacs-goose"
;;   :demand t
;;   :config
;;   (emacs-goose-mode))

(use-package emacs-goose
  :ensure (:host github :repo "lucasobx/emacs-goose" :files ("*.el" "sprites"))
  :demand t
  :config
  (emacs-goose-mode))

(use-package colorful-mode
  :ensure t
  :custom
  (colorful-use-prefix t)
  (colorful-prefix-string "■ ")
  (colorful-only-strings nil)
  (css-fontify-colors nil)
  :config
  (global-colorful-mode t)
  (add-to-list 'global-colorful-modes 'helpful-mode))

(use-package ansi-color
  :ensure nil
  :init
  (setenv "MANROFFOPT" "-P-c")
  :hook
  (compilation-filter . ansi-color-compilation-filter))

(use-package line-reminder
  :ensure t
  :hook
  (prog-mode . line-reminder-mode)
  :config
  (add-hook 'minibuffer-setup-hook (lambda () (line-reminder-mode -1)))
  (setopt line-reminder-show-option 'indicators)
  (setopt line-reminder-bitmap 'vertical-bar)
  (set-face-attribute 'line-reminder-modified-sign-face nil
                      :foreground (face-attribute 'line-number-current-line :foreground))
  (set-face-attribute 'line-reminder-saved-sign-face nil
                      :foreground (face-attribute 'default :background)))

(use-package whitespace
  :ensure nil
  :defer t
  :hook (before-save . whitespace-cleanup))

;; ===============================================================
;;; NAVIGATION

(use-package bookmark
  :ensure nil
  :custom
  (bookmark-fringe-mark nil)
  (bookmark-save-flag 1))

(use-package avy
  :ensure t
  :defer t)

(use-package dired
  :ensure nil
  :custom
  (dired-listing-switches "-lah --almost-all --group-directories-first --sort=extension")
  (dired-hide-details-hide-absolute-location t)
  (dired-kill-when-opening-new-dired-buffer t)
  (dired-recursive-deletes 'always)
  (dired-recursive-copies 'always)
  (dired-auto-revert-buffer t)
  (dired-omit-files "^\\.")
  (dired-free-space nil)
  (dired-dwim-target t)
  :hook
  (dired-mode . dired-hide-details-mode)
  (dired-mode . dired-omit-mode)
  (dired-mode . hl-line-mode)
  :config
  (defun my/dired-find-file ()
    "Open file from dired in full window, closing dired."
    (interactive)
    (let ((file (dired-get-file-for-visit)))
      (kill-buffer (current-buffer))
      (find-file file))))

(use-package wdired
  :ensure nil
  :commands (wdired-change-to-wdired-mode))

(defun my/zoxide-dired (query)
  "Prompt for QUERY, jump to the best zoxide match and open Dired there."
  (interactive "szoxide: ")
  (with-temp-buffer
    (if (zerop (call-process "zoxide" nil t nil "query" "--" query))
        (let ((dir (string-trim (buffer-string))))
          (if (file-directory-p dir)
              (dired dir)
            (user-error "Zoxide returned a non-directory: %s" dir)))
      (user-error "No zoxide match for: %s" query))))

;; ===============================================================
;;; TREESITTER

(use-package json-ts-mode
  :ensure nil
  :mode "\\.json\\'")

(use-package yaml-ts-mode
  :ensure nil
  :mode "\\.ya?ml\\'")

(use-package markdown-mode
  :ensure t
  :mode ("README\\.md\\'" . gfm-mode)
  :init (setq markdown-command "multimarkdown")
  :bind (:map markdown-mode-map
         ("C-c C-e" . markdown-do)))

(use-package lua-ts-mode
  :ensure nil
  :mode "\\.lua\\'"
  :custom
  (lua-ts-indent-offset 2)
  :config
  (setq lua-ts-mode-map (make-sparse-keymap)))

(use-package ruby-ts-mode
  :ensure nil
  :mode ("\\.rb\\'" "Rakefile\\'" "Gemfile\\'")
  :custom
  (ruby-indent-level 2)
  :config
  (setq ruby-ts-mode-map (make-sparse-keymap))
  (add-to-list 'treesit-language-source-alist
               '(ruby "https://github.com/tree-sitter/tree-sitter-ruby" "master" "src")))

;; ===============================================================
;;; PROG-MODE

(use-package eldoc
  :ensure nil
  :init
  (global-eldoc-mode)
  :custom
  (eldoc-help-at-pt t)
  (eldoc-idle-delay 0.5)
  (eldoc-echo-area-display-truncation-message nil)
  (eldoc-echo-area-use-multiline-p nil))

(use-package eldoc-box
  :ensure t
  :hook
  (prog-mode . eldoc-box-hover-mode)
  :custom
  (eldoc-box-max-pixel-height 200)
  (eldoc-box-max-pixel-width 400))

(use-package inf-ruby
  :ensure t
  :hook
  (ruby-ts-mode . inf-ruby-minor-mode)
  :config
  (setcdr (assq 'inf-ruby-minor-mode minor-mode-map-alist)
          (make-sparse-keymap))
  (when (executable-find "pry")
    (add-to-list 'inf-ruby-implementations '("pry" . "pry"))
    (setopt inf-ruby-default-implementation "pry"))
  (add-hook 'inf-ruby-mode-hook
            (lambda ()
              (set-process-query-on-exit-flag
               (get-buffer-process (current-buffer)) nil)))
  (my/lsp
    :keymaps 'ruby-ts-mode-map
    "b" '(ruby-send-buffer :wk "send buffer")
    "s" '(ruby-send-region :wk "send region")
    "l" '(ruby-send-line   :wk "send line")
    "r" '(inf-ruby         :wk "open repl")))

(use-package eglot
  :ensure nil
  :custom
  (eglot-ignored-server-capabilities '(:inlayHintProvider))
  (eglot-events-buffer-config '(:size 0 :format full))
  (eglot-code-action-indications nil)
  (eglot-prefer-plaintext nil)
  (jsonrpc-event-hook nil)
  (eglot-autoshutdown t)
  :init
  (fset #'jsonrpc--log-event #'ignore)
  :hook
  (ruby-ts-mode . eglot-ensure)
  (lua-ts-mode  . eglot-ensure)
  :config
  (add-to-list 'eglot-server-programs
               '((ruby-mode lua-ts-mode) "sumneko")
               '((ruby-mode ruby-ts-mode) "solargraph")))

(use-package flymake
  :ensure nil
  :hook
  (prog-mode . flymake-mode)
  :custom
  (flymake-show-diagnostics-at-end-of-line nil)
  (flymake-indicator-type 'margins)
  (flymake-margin-indicators-string
   '((error "" compilation-error)
     (warning "" compilation-warning)
     (note "" compilation-info))))

(use-package corfu
  :ensure t
  :defer t
  :custom
  (corfu-popupinfo-margin-width 0)
  (corfu-right-margin-width 0)
  (corfu-left-margin-width 0)
  (corfu-popupinfo-delay 1.0)
  (corfu-popupinfo-mode t)
  (corfu-quit-no-match t)
  (corfu-scroll-margin 0)
  (corfu-auto-prefix 1)
  (corfu-min-width 40)
  (corfu-max-width 40)
  (corfu-bar-width 0)
  (corfu-auto nil)
  (corfu-count 7)
  :config
  (global-corfu-mode)
  (advice-add #'lsp-completion-at-point
              :around #'cape-wrap-noninterruptible))

(use-package cape
  :ensure t
  :init
  (add-hook 'completion-at-point-functions #'cape-file)
  (add-hook 'completion-at-point-functions #'cape-dabbrev)
  :hook
  (eglot-managed-mode . (lambda ()
    (setq-local completion-at-point-functions
                (list #'eglot-completion-at-point
                      #'cape-file
                      #'cape-dabbrev)))))

;; ===============================================================
;;; COMPLETION

(use-package vertico
  :ensure t
  :init
  (vertico-mode)
  :custom
  (vertico-cycle nil)
  (vertico-count 5)
  :config
  ;; add a visual indicator to the currently selected candidate
  (advice-add #'vertico--format-candidate :around
              (lambda (orig cand prefix suffix index _start)
                (setq cand (funcall orig cand prefix suffix index _start))
                (concat
                 (if (= vertico--index index)
                     (propertize "» " 'face '(:foreground "#768c9c" :weight bold))
                   "  ")
                 cand))))

(use-package marginalia
  :ensure t
  :defer t
  :after vertico
  :init
  (marginalia-mode)
  :config
  ;; restrict annotations to 'face' category only
  (setopt marginalia-annotators
          (mapcar (lambda (pair)
                    (if (eq (car pair) 'face)
                        pair
                      (cons (car pair) '(none))))
                  marginalia-annotators)))

(use-package orderless
  :ensure t
  :custom
  (completion-styles '(orderless basic))
  (completion-category-overrides '((file (styles partial-completion))))
  (completion-category-defaults nil)
  (completion-pcm-leading-wildcard t))

(use-package consult
  :ensure t
  :after vertico
  :defer t
  :init
  (advice-add #'register-preview :override #'consult-register-window)
  (setopt xref-show-xrefs-function #'consult-xref
          xref-show-definitions-function #'consult-xref)
  (setopt completion-in-region-function #'consult-completion-in-region)
  :config
  (setopt consult-fd-args
          '("fd" "--color=auto" "--full-path" "--hidden"))
  (setopt consult-buffer-sources '(consult-source-buffer))
  (setopt consult-buffer-filter
          (append consult-buffer-filter
                  '("\\*Async Shell Command\\*" "Output\\*$" "\\*Help\\*" "\\*Messages\\*"
                    "\\*eldoc\\*" "\\*helpful.*\\*" "annotations.org" "\\*Ibuffer\\*"
                    "\\*Warnings\\*" "\\*eshell\\*")))
  ;; prevent dired buffer from surfacing in consult-buffer when hidden by popper.
  (advice-add
   #'consult--buffer-query :filter-return
   (lambda (buffers)
     (seq-remove
      (lambda (buf)
        (with-current-buffer (if (consp buf) (cdr buf) buf)
          (derived-mode-p 'dired-mode)))
      buffers))))

;; ==============================================================
;;; EDITING

(use-package expand-region
  :ensure t)

(use-package move-text
  :ensure t)

(use-package multiple-cursors
  :ensure t
  :custom
  (mc/list-file (locate-user-emacs-file "mc-lists.el"))
  :config
  ;; prevent multiple-cursors from prompting about devil
  (add-to-list 'mc/cmds-to-run-once 'devil))

(use-package sudo-edit
  :ensure t
  :defer t)

;; ===============================================================
;;; ORG

(use-package org
  :ensure nil
  :custom
  (org-src-content-indentation 2)
  (org-hide-emphasis-markers t)
  (org-hide-block-startup t)
  (org-catch-invisible-edits 'show-and-error)
  (org-agenda-files '("~/Documents/org"))
  (org-insert-heading-respect-content t)
  (org-cycle-hide-drawer-startup t)
  (org-return-follows-link t)
  (org-hide-leading-stars t)
  (org-auto-align-tags nil)
  (org-special-ctrl-a/e t)
  (org-tags-column 0)
  (org-ellipsis " ∷")
  :hook
  ((org-mode . turn-off-auto-fill)
   (org-mode . visual-line-mode)
   (org-mode . org-indent-mode)
   (org-mode . hl-line-mode))
  :config
  (set-face-attribute 'org-ellipsis nil :underline nil))

(use-package org-appear
  :ensure (:host github :repo "awth13/org-appear")
  :custom
  (org-appear-autoemphasis t)
  :hook
  (org-mode . org-appear-mode))

(use-package org-modern
  :ensure t
  :custom
  (org-modern-star 'replace)
  (org-modern-replace-stars '("◉" "○" "◈" "◇" "•"))
  (org-modern-checkbox nil)
  (org-modern-list '((?- . "›") (?+ . "»") (?* . "»»")))
  :hook
  (org-mode . org-modern-mode))

(use-package org-remark
  :ensure t
  :init
  (org-remark-global-tracking-mode +1)
  :custom
  (org-remark-notes-file-name "~/.config/emacs/org/annotations.org")
  (org-remark-icon-notes nil)
  :config
  (with-eval-after-load 'org-remark
    (setq org-remark-notes-display-buffer-action
          nil))
  (org-remark-create "custom1"
    'mode-line-active
    '(CATEGORY "custom")))

(use-package org-hide-drawers
  :ensure t
  :custom
  (org-hide-drawers-display-strings'((all " ⚙")))
  :hook
  (org-mode . org-hide-drawers-mode))

;; ===============================================================
;;; TERMINAL

(use-package eshell
  :ensure nil
  :defer t
  :custom
  (eshell-banner-message "")
  (eshell-history-size 100000)
  (eshell-hist-ignoredups t)
  :config
  (with-eval-after-load 'em-alias
    (eshell/alias "clear" "clear-scrollback")))

;; ===============================================================
;;; DOCS

(use-package helpful
  :ensure t
  :defer t)

(use-package devdocs
  :ensure t
  :defer t
  :config
  (setopt devdocs-header-line nil))

(use-package shr
  :ensure nil
  :config
  (setopt shr-use-fonts nil))

;; ===============================================================
;;; VERSION CONTROL

(use-package magit
  :ensure t
  :defer t
  :bind
  ("C-c M-g" . nil)
  :preface
  (defun my/magit-kill-buffers ()
    "Restore window configuration and kill all Magit buffers."
    (interactive)
    (let ((buffers (magit-mode-get-buffers)))
      (magit-restore-window-configuration)
      (mapc #'kill-buffer buffers)))
  :bind
  (:map magit-status-mode-map ("q" . my/magit-kill-buffers))
  :config
  (magit-process-apply-ansi-colors t)
  (keymap-set transient-map "<escape>" #'transient-quit-one))

;;; init.el ends here
