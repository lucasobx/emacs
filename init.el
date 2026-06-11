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
(defvar my/font-size 110)

(use-package emacs
  :ensure nil
  :init
  (defun display-startup-echo-area-message () (message ""))
  (delete-selection-mode 1)
  (global-hl-line-mode -1)
  (save-place-mode 1)
  (tooltip-mode -1)
  (savehist-mode 1)
  (recentf-mode 1)
  (winner-mode 1)

  :custom
  (display-fill-column-indicator-warning nil)
  (uniquify-buffer-name-style 'forward)
  (display-line-numbers-type 'relative)
  (warning-minimum-level :emergency)
  (ibuffer-human-readable-size t)
  (display-line-numbers-width 4)
  (zone-all-windows-in-frame t)
  (initial-scratch-message "")
  (ring-bell-function 'ignore)
  (split-width-threshold 100)
  (inhibit-startup-message t)
  (treesit-font-lock-level 4)
  (echo-keystrokes 0.1)
  (use-short-answers t)
  (use-dialog-box nil)
  (zone-all-frames t)
  (truncate-lines t)
  (line-spacing 1)
  (undo-no-redo t)

  ;; minibuffer
  (minibuffer-prompt-properties
   '(read-only t cursor-intangible t face minibuffer-prompt))
  (read-extended-command-predicate
   #'command-completion-default-include-p)
  (switch-to-buffer-obey-display-actions t)
  (enable-recursive-minibuffers t)
  (lazy-highlight-initial-delay 0)
  (resize-mini-windows 'grow-only)
  (completion-eager-display 'auto)
  (completion-eager-update t)
  (history-length 25)

  ;; editing
  (treesit-auto-install-grammar t)
  (kill-do-not-save-duplicates t)
  (sentence-end-double-space nil)
  (tab-always-indent 'complete)
  (delete-pair-push-mark t)
  (treesit-enabled-modes t)
  (indent-tabs-mode nil)
  (tab-width 2)

  ;; files
  (auto-save-file-name-transforms
   `((".*" ,(expand-file-name "auto-saves/" user-emacs-directory) t)))
  (find-file-suppress-same-file-warnings t)
  (global-auto-revert-non-file-buffers t)
  (kill-buffer-delete-auto-save-files t)
  (auto-save-no-message t)
  (make-backup-files nil)
  (create-lockfiles nil)

  ;; scroll
  (pixel-scroll-precision-use-momentum nil)
  (scroll-preserve-screen-position t)
  (mouse-wheel-progressive-speed nil)
  (delete-by-moving-to-trash t)
  (scroll-conservatively 101)
  (scroll-margin 10)
  (scroll-step 1)
  
  :config
  (make-directory (expand-file-name "auto-saves/" user-emacs-directory) t)
  (setq custom-file (locate-user-emacs-file "custom-vars.el"))
  (load custom-file 'noerror 'nomessage)

  ;; global modes
  (minibuffer-electric-default-mode 1)
  (minibuffer-depth-indicate-mode 1)
  (global-auto-revert-mode 1)
  (file-name-shadow-mode 1)
  (electric-indent-mode 1)
  (electric-pair-mode 1)
  (column-number-mode 1)

  ;; hooks
  (add-hook 'emacs-startup-hook
            (lambda () (message "Booted in %s." (emacs-init-time))))
  (add-hook 'minibuffer-setup-hook #'cursor-intangible-mode)
  (add-hook 'prog-mode-hook 'display-line-numbers-mode)

  ;; faces
  (set-face-attribute 'default nil :family my/font :height my/font-size :width 'condensed)
  (set-face-attribute 'minibuffer-nonselected nil :background 'unspecified)
  (set-face-attribute 'tooltip nil :family my/font)
  (setq-default line-spacing 0)

  ;; misc
  (setq redisplay-skip-fontification-on-input t)
  (setq native-comp-async-query-on-exit t)
  (put 'narrow-to-region 'disabled nil)
  (setq message-truncate-lines t)

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

  ;; add option `d', allowing a quick preview of the diff of what you're asked to save.
  (add-to-list 'save-some-buffers-action-alist
               (list "d"
                     (lambda (buffer) (diff-buffer-with-file (buffer-file-name buffer)))
                     "show diff between the buffer and its file"))

  :bind
  ("RET"       . newline-and-indent)
  ("C-_"       . text-scale-decrease)
  ("C-+"       . text-scale-increase))

;; ===============================================================
;;; CUSTOM FUNCTIONS

(defun my/kill-buffer-window ()
  "Kill the current buffer and close its window."
  (interactive)
  (let ((buffer (current-buffer)))
    (when (and (> (count-windows) 1)
               (not (one-window-p)))
      (delete-window))
    (kill-buffer buffer)))

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
  (interactive)
  (let ((origin (point)))
    (back-to-indentation)
    (when (= origin (point))
      (beginning-of-line))))

;; ===============================================================
;;; TEXT OBJECTS

(defun my/inside-parens ()
  "Return bounds of content inside parentheses."
  (when (or (looking-at "(")
            (ignore-errors (backward-up-list 1) t))
    (let ((start (1+ (point)))
          (end   (1- (progn (forward-sexp) (point)))))
      (cons start end))))

(defun my/inside-brackets ()
  "Return bounds of content inside square brackets."
  (when (or (looking-at "\\[")
            (ignore-errors (backward-up-list 1) t))
    (let ((start (1+ (point)))
          (end   (1- (progn (forward-sexp) (point)))))
      (cons start end))))

(defun my/inside-braces ()
  "Return bounds of content inside curly braces."
  (when (or (looking-at "{")
            (ignore-errors (backward-up-list 1) t))
    (let ((start (1+ (point)))
          (end   (1- (progn (forward-sexp) (point)))))
      (cons start end))))

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

(defun my/delete-paragraph ()
  "Delete paragraph at point."
  (interactive)
  (my/delete-thing 'paragraph))

(defun my/delete-word ()
  "Delete word at point, cleaning up leftover whitespace."
  (interactive)
  (let ((bounds (bounds-of-thing-at-point 'word)))
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
         (preceded-by-space (delete-char -1)))))))

(defun my/delete-symbol ()
  "Delete symbol at point, cleaning up leftover whitespace."
  (interactive)
  (let ((bounds (bounds-of-thing-at-point 'symbol)))
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
         (preceded-by-space (delete-char -1)))))))

(defun my/delete-defun ()
  "Delete defun at point."
  (interactive)
  (my/delete-thing 'defun))

(defun my/delete-line ()
  "Delete line at point."
  (interactive)
  (my/delete-thing 'line))

(defun my/delete-in-brackets ()
  "Delete text inside brackets."
  (interactive)
  (my/delete-inside #'my/inside-brackets))

(defun my/delete-in-parens ()
  "Delete text inside parentheses."
  (interactive)
  (my/delete-inside #'my/inside-parens))

(defun my/delete-in-braces ()
  "Delete text inside braces."
  (interactive)
  (my/delete-inside #'my/inside-braces))

(defun my/copy-paragraph ()
  "Copy paragraph at point."
  (interactive)
  (my/copy-thing 'paragraph))

(defun my/copy-word ()
  "Copy word at point."
  (interactive)
  (my/copy-thing 'word))

(defun my/copy-symbol ()
  "Copy symbol at point."
  (interactive)
  (my/copy-thing 'symbol))

(defun my/copy-defun ()
  "Copy defun at point."
  (interactive)
  (my/copy-thing 'defun))

(defun my/copy-word ()
  "Copy word at point."
  (interactive)
  (my/copy-thing 'word))

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

(defun my/copy-inside-brackets ()
  "Copy text inside brackets."
  (interactive)
  (my/copy-inside #'my/inside-brackets))

(defun my/copy-inside-parens ()
  "Copy text inside parentheses."
  (interactive)
  (my/copy-inside #'my/inside-parens))

(defun my/copy-inside-braces ()
  "Copy text inside braces."
  (interactive)
  (my/copy-inside #'my/inside-braces))

(defun my/toggle-comment-paragraph ()
  "Toggle comment on paragraph at point."
  (interactive)
  (my/toggle-comment-thing 'paragraph))

(defun my/toggle-comment-defun ()
  "Toggle comment on defun at point."
  (interactive)
  (my/toggle-comment-thing 'defun))

(defun my/toggle-comment-line ()
  "Toggle comment on current line."
  (interactive)
  (comment-line 1))

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
  (add-to-list 'devil-repeatable-keys
               '("%k . ." "%k . /"))
  (add-to-list 'devil-repeatable-keys ;; delete
               '("%k d s" "%k d d" "%k d p" "%k d f"
                 "%k d w" "%k d (" "%k d [" "%k d {"))
  (add-to-list 'devil-repeatable-keys ;; comment
               '("%k ; ;" "%k ; p" "%k ; f"))
  (add-to-list 'devil-repeatable-keys ;; C-c
               '("%k c d")))

(use-package general
  :ensure (:wait t)
  :demand t
  :config
  (general-auto-unbind-keys)
  (general-unbind "C-<wheel-down>" "C-<wheel-up>" "C-x C-z" "C-c ^" "C-z")
  (general-unbind :keymaps 'emacs-lisp-mode-map "C-c C-b" "C-c C-e" "C-c C-f")
  (general-unbind :keymaps 'winner-mode-map "C-c <left>" "C-c <right>")
  (general-unbind :keymaps 'ghostel-semi-char-mode-map "C-<tab>")

  ;; definers
  (general-create-definer my/keys    :keymaps 'override)
  (general-create-definer my/dired   :keymaps 'dired-mode-map)
  (general-create-definer my/C-c     :keymaps 'override :prefix "C-c")
  (general-create-definer my/copy    :keymaps 'override :prefix "C-y")
  (general-create-definer my/delete  :keymaps 'override :prefix "C-d")
  (general-create-definer my/comment :keymaps 'override :prefix "C-;")
  (general-create-definer my/replace :keymaps 'override :prefix "C-r")
  (general-create-definer my/cursors :keymaps 'override :prefix "C-.")
  (general-create-definer my/search  :keymaps 'override :prefix "C-s")
  (general-create-definer my/file    :keymaps 'override :prefix "C-f")
  (general-create-definer my/emacs   :keymaps 'override :prefix "C-e")
  (general-create-definer my/lsp     :keymaps 'override :prefix "C-l")
  (general-create-definer my/mark    :keymaps 'override :prefix "C-q")
  (general-create-definer my/tools   :keymaps 'override :prefix "C-t")
  
  (my/keys
    "C-<backspace>" 'my/backward-delete
    "M-<right>" 'end-of-line
    "M-<left>" 'my/beginning-of-line
    "M-<up>"   'move-text-up
    "M-<down>" 'move-text-down
    "M-j"      'flash-jump
    "M-d"      'dired-jump
    "<f1>"     'scratch-buffer
    "<f2>"     'wdired-change-to-wdired-mode
    "<f5>"     'my/select-theme
    "<f6>"     'my/rotate-theme
    "C-<tab>"  'other-window
    "C-k"      'my/kill-buffer-window
    "C-o"      'my/open-line-below
    "C-="      'er/expand-region
    "C-b"      'consult-buffer
    "C-,"      'popper-toggle
    "C-<"      'popper-cycle
    "C-p"      'yank)

  (my/C-c
    "d" '(duplicate-line :wk "duplicate line"))

  (my/C-c ;; org
   :keymaps 'org-mode-map
   "t d" '(org-hide-drawers-toggle :wk "toggle drawers"))

  (my/dired
    "M-<left>" 'dired-up-directory
    "M-."      'dired-omit-mode
    "RET"      'my/dired-find-file)

  (my/copy
    "w" '(my/copy-word            :wk "copy word")
    "s" '(my/copy-symbol          :wk "copy symbol")
    "y" '(my/copy-line            :wk "copy line")
    "p" '(my/copy-paragraph       :wk "copy paragraph")
    "(" '(my/copy-inside-parens   :wk "inside ()")
    "[" '(my/copy-inside-brackets :wk "inside []")
    "{" '(my/copy-inside-braces   :wk "inside {}"))

  (my/delete
    "w" '(my/delete-word        :wk "delete word")
    "s" '(my/delete-symbol      :wk "delete symbol")
    "d" '(my/delete-line        :wk "delete line")
    "p" '(my/delete-paragraph   :wk "delete paragraph")
    "(" '(my/delete-in-parens   :wk "delete inside ()")
    "[" '(my/delete-in-brackets :wk "delete inside []")
    "{" '(my/delete-in-braces   :wk "delete inside {}"))

  (my/comment
    "p" '(my/toggle-comment-paragraph :wk "paragraph")
    ";" '(my/toggle-comment-line      :wk "line"))
  
  (my/replace
    "r" '(replace-string       :wk "replace string")
    "q" '(query-replace        :wk "query replace")
    "m" '(flush-lines          :wk "remove matching lines"))

  (my/cursors
   "." '(mc/mark-next-like-this     :wk "cursor next")
   "/" '(mc/mark-previous-like-this :wk "cursor prev")
   "m" '(mc/mark-all-in-region      :wk "cursor region")
   "l" '(mc/edit-lines              :wk "cursor lines"))
  
  (my/search
    "r" '(consult-recent-file :wk "recent files")
    "b" '(consult-bookmark    :wk "bookmarks")
    "g" '(consult-ripgrep     :wk "ripgrep")
    "s" '(consult-line        :wk "line"))

  (my/file
    "d" '(consult-fd          :wk "fd-find file")
    "r" '(rename-visited-file :wk "rename file")
    "f" '(find-file           :wk "find file")
    "s" '(save-buffer         :wk "save"))

  (my/emacs
    "i" '((lambda () (interactive)
            (find-file (locate-user-emacs-file "init.el")))
          :wk "open init.el")
    "s" '(sudo-edit        :wk "edit with sudo")
    "v" '(visual-line-mode :wk "truncate lines")
    "r" '(restart-emacs    :wk "restart emacs"))

  (my/lsp
    :keymaps 'prog-mode-map
    "d" '(consult-flymake :wk "jump to diagnostic")
    "n" '(eglot-rename    :wk "rename symbol"))
  
  (my/mark
    "q" '(org-remark-mark   :wk "highlight region")
    "d" '(org-remark-delete :wk "highlight delete")
    "c" '(org-remark-change :wk "highlight change")
    "o" '(org-remark-open   :wk "open notes"))
  
  (my/tools
    "h" '(helpful-at-point :wk "helpful at point")
    "m" '(magit-status     :wk "magit status")
    "c" '(cheat-sh         :wk "cheat sheet")
    "t" '(ghostel          :wk "terminal")
    "d" '(devdocs-lookup   :wk "devdocs")))

;; ===============================================================
;;; UI

(use-package window
  :ensure nil
  :custom
  (display-buffer-alist
   '(("\\`magit:"
      (display-buffer-in-side-window)
      (window-height . 0.4)
      (side . bottom)
      (slot . 0))
     ((derived-mode . dired-mode)
      (display-buffer-in-side-window)
      (window-height . 0.4)
      (side . bottom)
      (slot . 0)))))

(use-package popper
  :ensure t
  :defer t
  :init
  (popper-mode +1)
  :custom
  (popper-window-height 16)
  (popper-mode-line "")
  (popper-reference-buffers
   '("\\*eldoc\\*"
     "\\*marginal notes\\*"
     "\\*cheat.sh*\\*$"
     "^\\*ghostel.*\\*"
     compilation-mode
     inf-ruby-mode
     devdocs-mode
     helpful-mode
     ghostel-mode
     help-mode)))

(use-package nerd-icons
  :ensure t
  :custom
  (nerd-icons-scale-factor 1.0))

(use-package nerd-icons-dired
  :ensure t
  :hook
  (dired-mode . nerd-icons-dired-mode))

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

;; ── THEMES

(use-package pixel-themes
  :ensure (:host github :repo "lucasobx/pixel-themes"))

(use-package doric-themes
  :ensure t)

(defvar my/theme nil
  "Currently active theme.")

(defvar my/theme-builtin
  '(adwaita deeper-blue dichromacy leuven leuven-dark light-blue manoj-dark
    misterioso newcomers-presets tango tango-dark tsdh-dark tsdh-light
    wheatgrass whiteboard wombat doric-magma doric-copper)
  "Built-in Emacs themes to exclude from selection.")

(defun my/theme-list ()
  "Return filtered list of available themes."
  (cl-remove-if (lambda (theme)
                  (or (memq theme my/theme-builtin)
                      (string-prefix-p "modus-" (symbol-name theme))
                      (and (boundp 'doric-themes-light-themes)
                           (memq theme doric-themes-light-themes))))
                (custom-available-themes)))

(defun my/load-theme (theme &optional no-save)
  "Load THEME. Do not save configuration if NO-SAVE is non-nil."
  (mapc #'disable-theme custom-enabled-themes)
  (setq my/theme theme)
  (load-theme theme :no-confirm)
  (unless no-save
    (customize-save-variable 'my/theme theme)))

(defun my/select-theme ()
  "Interactively select and load a theme."
  (interactive)
  (let ((choice (completing-read "Theme: " (my/theme-list) nil t)))
    (when (org-string-nw-p choice)
      (my/load-theme (intern choice)))))

(defun my/rotate-theme ()
  "Rotate to the next theme in the filtered list."
  (interactive)
  (let* ((filtered (my/theme-list))
         (curr-idx (or (cl-position (car custom-enabled-themes) filtered) -1))
         (next-idx (mod (1+ curr-idx) (length filtered))))
    (my/load-theme (nth next-idx filtered))))

(add-hook 'elpaca-after-init-hook
          (lambda ()
            (when my/theme
              (my/load-theme my/theme :no-save))))
;; --

;; (use-package pixel-themes
;;   :ensure nil
;;   :load-path "~/.config/emacs/pixel-themes-local"
;;   :config
;;   (pixel-themes-load-theme 'pixel-themes-psygnosia))

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
  (doom-modeline-window-width-limit 0)
  (doom-modeline-total-line-number t)
  (doom-modeline-buffer-encoding nil)
  (doom-modeline-major-mode-icon t)
  (doom-modeline-check-icon nil)
  (doom-modeline-modal-icon t)
  (doom-modeline-height 25)
  (doom-modeline-modal t)
  (doom-modeline-icon t)
  :config
  (defun doom-modeline-check-icon (_icon _unicode _text &optional _face) "")
  (setopt doom-modeline-always-show-macro-register t)
  (setopt doom-modeline-buffer-modification-icon nil)
  (custom-set-faces
   '(mode-line ((t (:inherit default :height 118 :weight normal))))
   '(mode-line-inactive ((t (:inherit default :height 118 :weight normal)))))
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

;; ===============================================================
;;; NAVIGATION

(use-package bookmark
  :ensure nil
  :custom
  (bookmark-fringe-mark nil)
  (bookmark-save-flag 1))

(use-package flash
  :ensure (:host github :repo "Prgebish/flash")
  :commands (flash-jump flash-jump-continue flash-treesitter)
  :custom
  (flash-char-jump-labels t)
  (flash-labels "asdfqwe")
  (flash-multi-window t)
  (flash-nohlsearch t)
  (flash-backdrop nil)
  (flash-autojump t))

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

(use-package python-ts-mode
  :ensure nil
  :mode "\\.py\\'"
  :config
  (setq python-ts-mode-map (make-sparse-keymap))
  (add-to-list 'treesit-language-source-alist
               '(ruby "https://github.com/tree-sitter/tree-sitter-python" "master" "src")))

(use-package treesit-auto
  :ensure t
  :after emacs
  :custom
  (treesit-auto-install t)
  :config
  (global-treesit-auto-mode t))

;; ===============================================================
;;; PROG-MODE

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

(use-package mason
  :ensure t
  :config
  (mason-setup))

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
               '((ruby-mode ruby-ts-mode) "solargraph")
               '((python-mode python-ts-mode) "pyright")))

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
  (global-corfu-mode))

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

(use-package eldoc
  :ensure nil
  :init
  (global-eldoc-mode)
  :custom
  (eldoc-help-at-pt t)
  (eldoc-echo-area-display-truncation-message nil)
  (eldoc-echo-area-prefer-doc-buffer t)
  (eldoc-echo-area-use-multiline-p nil))

;; ===============================================================
;;; COMPLETION

(use-package vertico
  :ensure t
  :init
  (vertico-mode)
  :custom
  (vertico-cycle nil)
  (vertico-count 6)
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
  ;; restrict annotations to 'face' and 'command' categories
  (setopt marginalia-annotators
          (mapcar (lambda (pair)
                    (if (memq (car pair) '(face command))
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
                  '("\\*Async Shell Command\\*" "\\*eldoc\\*" "Output\\*$"
                    "annotations.org" "\\*Messages\\*" "\\*lsp-bridge.*\\*"
                    "\\*helpful.*\\*" "\\*ghostel.*\\*")))
  ;; prevent dired buffer from surfacing in consult-buffer when hidden by popper.
  (defun my/consult-buffer-filter-modes (buffers)
    (cl-remove-if
     (lambda (buf)
       (let ((buffer (if (stringp buf) (get-buffer buf) (cdr buf))))
         (when buffer
           (memq (buffer-local-value 'major-mode buffer) '(dired-mode)))))
     buffers))
  (advice-add #'consult--buffer-query :filter-return #'my/consult-buffer-filter-modes))

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
  (set-face-attribute 'mc/cursor-bar-face nil :underline t))

(use-package sudo-edit
  :ensure t
  :defer t)

;; ===============================================================
;;; WRITING & READING

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

(use-package ghostel
  :ensure t
  :defer t)
  
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
  :config
  (keymap-set transient-map "<escape>" 'transient-quit-one))

;; ===============================================================
;;; TOOLS

(defun cheat-sh ()
  "Query cheat.sh and display the result in a dedicated buffer."
  (interactive)
  (let* ((input (read-string "cheat.sh: "))
         (parts (split-string input " " t))
         (path  (if (cdr parts)
                    (format "%s/%s"
                            (car parts)
                            (url-hexify-string (string-join (cdr parts) " ")))
                  (url-hexify-string (car parts))))
         (buffer (get-buffer-create "*cheat.sh*"))
         (cmd    (format "curl -s 'cheat.sh/%s'" path)))
    (with-current-buffer buffer
      (read-only-mode -1)
      (erase-buffer)
      (insert (concat "cheat.sh: " input "\n"))
      (read-only-mode 1))
    (switch-to-buffer buffer)
    (cheat-sh--fetch cmd buffer)))

(defun cheat-sh--fetch (cmd buffer &optional)
  "Execute CMD as a shell command and stream output into BUFFER."
  (make-process
   :name "cheat-sh-fetch"
   :buffer (generate-new-buffer "*cheat-sh-temp*")
   :command (list "sh" "-c" cmd)
   :sentinel
   (lambda (proc _event)
     (when (eq (process-status proc) 'exit)
       (let ((output (with-current-buffer (process-buffer proc)
                       (buffer-string))))
         (kill-buffer (process-buffer proc))
         (with-current-buffer buffer
           (read-only-mode -1)
           (insert output)
           (ansi-color-apply-on-region (point-min) (point-max))
           (goto-char (point-min))
           (read-only-mode 1)))))))

;;; init.el ends here
