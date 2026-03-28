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
;;; CORE SETTINGS

(defvar my/font "PragmataPro Liga")
(defvar my/size 132)
(defvar my/line-spacing 0.15)

;; (defvar my/font "Berkeley Mono ExtraCondensed Retina")
;; (defvar my/line-spacing 1)
;; (defvar my/size 140)

(set-face-attribute 'default nil :font my/font :height my/size)
(setq-default line-spacing my/line-spacing)

(use-package emacs
  :ensure nil
  :init
  (defun display-startup-echo-area-message () (message ""))
  (global-auto-revert-mode t)
  (file-name-shadow-mode 1)
  (delete-selection-mode 1)
  (global-hl-line-mode -1)
  (electric-indent-mode 1)
  (electric-pair-mode 1)
  (column-number-mode 1)
  (save-place-mode 1)
  (tooltip-mode -1)
  (savehist-mode 1)
  (recentf-mode 1)
  (winner-mode 1)

  :custom
  ;; ui
  (redisplay-skip-fontification-on-input t)
  (uniquify-buffer-name-style 'forward)
  (display-line-numbers-type 'relative)
  (display-line-numbers-width-start t)
  (warning-minimum-level :emergency)
  ;; (display-line-numbers-width 3)
  (initial-major-mode 'org-mode)
  (initial-scratch-message "")
  (ring-bell-function 'ignore)
  (split-width-threshold 100)
  (inhibit-startup-message t)
  (treesit-font-lock-level 4)
  (message-truncate-lines t)
  (echo-keystrokes 0.1)
  (use-short-answers t)
  (use-dialog-box nil)
  (truncate-lines t)
  ;; minibuffer
  (minibuffer-prompt-properties
    '(read-only t cursor-intangible t face minibuffer-prompt))
  (read-extended-command-predicate
   #'command-completion-default-include-p)
  (switch-to-buffer-obey-display-actions t)
  (enable-recursive-minibuffers t)
  (lazy-highlight-initial-delay 0)
  (resize-mini-windows 'grow-only)
  (history-length 25)
  ;; editing
  (kill-do-not-save-duplicates t)
  (sentence-end-double-space nil)
  (tab-always-indent 'complete)
  (indent-tabs-mode nil)
  (tab-width 2)
  ;; files
  (auto-save-file-name-transforms
   '((".*" "~/.config/emacs/auto-saves/" t)))
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
  ;; buffers
  (defun skip-these-buffers (_window buffer _bury-or-kill)
    "Function for `switch-to-prev-buffer-skip'."
    (string-match "\\*[^*]+\\*" (buffer-name buffer)))
  (setq switch-to-prev-buffer-skip 'skip-these-buffers)
  ;; benchmark
  (add-hook 'emacs-startup-hook
            (lambda () (message "Booted in %s." (emacs-init-time))))
  ;; system
  (setq custom-file (locate-user-emacs-file "custom-vars.el"))
  (add-hook 'prog-mode-hook 'display-line-numbers-mode)
  (setopt native-comp-async-query-on-exit t)
  (load custom-file 'noerror 'nomessage)
  (put 'narrow-to-region 'disabled nil)
  ;; bindings
  (define-advice keyboard-quit
      (:around (quit) quit-current-context)
    (if (active-minibuffer-window)
        (if (minibufferp)
            (minibuffer-keyboard-quit) (abort-recursive-edit))
      (unless (or defining-kbd-macro executing-kbd-macro)
        (funcall-interactively quit))))
  (define-key key-translation-map (kbd "ESC") (kbd "C-g"))
  (global-unset-key (kbd "C-<wheel-down>"))
  (global-unset-key (kbd "C-<wheel-up>"))
  (global-unset-key (kbd "C-x C-z"))
  (global-unset-key (kbd "C-z"))
  ;; ui
  (set-face-attribute 'help-key-binding nil :box nil
                      :background nil :font my/font
                      :height 0.95)
  (add-hook 'minibuffer-setup-hook
            (lambda () (setq-local face-remapping-alist
                                   '((default :height 0.95)))))

  :bind
  ("C-="     . text-scale-increase)
  ("C--"     . text-scale-decrease)
  ("C-<tab>" . other-window))

;; ===============================================================
;;; CUSTOM FUNCTIONS

(defun my/jump-to-end-of-block ()
  "Jump to the end of the current block."
  (interactive)
  (beginning-of-defun)
  (forward-sexp))

(defun my/vterm-only ()
  "Open vterm in full screen and disable exit query."
  (interactive)
  (require 'vterm)
  (let ((popper-mode nil)
        (display-buffer-alist nil))
    (vterm)
    (delete-other-windows)
    (let ((proc (get-buffer-process (current-buffer))))
          (when proc (set-process-query-on-exit-flag proc nil)))))

(defun my/kill-buffer-and-window ()
  "Kill the current buffer and close its window."
  (interactive)
  (let ((buffer (current-buffer)))
    (when (and (> (count-windows) 1)
               (not (one-window-p)))
      (delete-window))
    (kill-buffer buffer)))

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
          which-key-idle-delay 0.2)
  (set-face-attribute 'which-key-note-face nil :height 1.0)
  (setopt which-key-sort-order 'which-key-local-then-key-order))

(use-package general
  :ensure (:wait t)
  :demand t
  :config
  (general-evil-setup)
  (general-create-definer my/keys
    :states '(normal insert visual emacs)
    :keymaps 'override
    :prefix "SPC"
    :global-prefix "M-SPC")
  (my/keys
    ;; --- navigation
    "k" '(my/kill-buffer-and-window :wk "kill buffer")
    "[" '(evil-beginning-of-line :wk "beg of line")
    "]" '(evil-end-of-line :wk "end of line")
    "<" '(previous-buffer :wk "previ buffer")
    "b" '(consult-buffer :wk "search buffer")
    ">" '(next-buffer :wk "next buffer")
    "d" '(dired-jump :wk "file manager")
    "." '(embark-act :wk "context menu")
    "/" '(flash-jump :wk "search jump")

    ;; --- emacs
    "e"   '(:ignore t :wk "emacs")
    "e s" '(sudo-edit :wk "sudo edit file")
    "e p" '(check-parens :wk "check parens")
    "e r" '(restart-emacs :wk "restart emacs")
    "e f" '(eval-last-sexp :wk "eval expression")
    "e m" '(consult-mode-command :wk "mode commands")
    "e e" '(my/jump-to-end-of-block :wk "end of block")
    "e c" '((lambda () (interactive)
              (find-file (locate-user-emacs-file "init.el")))
            :wk "edit config")

    ;; --- help
    "h"   '(:ignore t :wk "help")
    "h h" '(helpful-at-point :wk "at point")
    "h v" '(helpful-variable :wk "variable")
    "h f" '(helpful-function :wk "function")
    "h d" '(devdocs-lookup :wk "devdocs")
    "h e" '(eldoc :wk "eldoc")

    ;; --- popper
    "p"   '(:ignore t :wk "popper")
    "p t" '(popper-toggle-type :wk "toggle type")
    "p p" '(popper-toggle :wk "toggle popup")
    "p l" '(popper-cycle :wk "next popup")

    ;; --- search
    "s"   '(:ignore t :wk "search")
    "s r" '(consult-recent-file :wk "recent files")
    "s l" '(consult-line-multi :wk "line in files")
    "s d" '(consult-dir :wk "recent directories")
    "s g" '(consult-ripgrep :wk "ripgrep")
    "s i" '(consult-imenu :wk "imenu")
    "s s" '(consult-line :wk "line")
    "s f" '(consult-find :wk "file")

    ;; --- toggles
    "t"   '(:ignore t :wk "toggle")
    "t w" '(my/toggle-whitespace-cleanup :wk "whitespace cleanup")
    "t l" '(visual-line-mode :wk "truncated lines")
    "t f" '(focus-mode :wk "focus mode")
    "t t" '(vterm :wk "vterm")

    ;; --- windows
    "w"   '(:ignore t :wk "windows")
    "w w" '(evil-window-split :wk "horizontal split")
    "w v" '(evil-window-vsplit :wk "vertical split")
    "w c" '(evil-window-delete :wk "close window")
    "w n" '(evil-window-new :wk "new window")
    "w l" '(buf-move-right :wk "move right")
    "w h" '(buf-move-left :wk "move left")
    "w j" '(buf-move-down :wk "move down")
    "w k" '(buf-move-up :wk "move up"))
  (my/keys
    :keymaps 'org-mode-map
    "o"   '(:ignore t :wk "org")
    "o p" '(org-tidy-untidy-buffer :wk "edit property")
    "o o" '(org-toggle-checkbox :wk "toggle checkbox")
    "o l" '(org-insert-link :wk "insert link")
    "o f" '((lambda () (interactive)
              (dired "~/documents/org"))
            :wk "open org folder")))

(use-package evil
  :ensure (:wait t)
  :demand t
  :init
  (setopt evil-undo-system 'undo-redo
          evil-want-fine-undo t
          evil-want-integration t
          evil-want-keybinding nil
          evil-vsplit-window-right t
          evil-split-window-below t
          evil-shift-width 2)
  :config
  (define-key evil-normal-state-map (kbd "<escape>") #'keyboard-quit)
  (define-key evil-insert-state-map (kbd "C-y") 'yank)
  (define-key evil-normal-state-map (kbd "C-y") 'yank)
  (evil-set-initial-state 'vterm-mode 'emacs)
  (evil-mode 1))

(use-package evil-collection
  :ensure t
  :after evil
  :config
  (setopt evil-collection-mode-list '(dashboard dired ibuffer magit))
  (evil-collection-init))

(use-package evil-matchit
  :ensure t
  :after evil-collection
  :config
  (global-evil-matchit-mode 1))

(use-package evil-commentary
  :ensure t
  :after evil
  :config
  (evil-commentary-mode))

(use-package evil-surround
  :ensure t
  :config
  (global-evil-surround-mode 1))

(use-package evil-goggles
  :ensure t
  :custom
  (evil-goggles-duration 0.100)
  (evil-goggles-enable-paste nil)
  :config
  (evil-goggles-mode)
  (evil-goggles-use-diff-faces))

(use-package evil-tutor
  :ensure t
  :defer t)

(use-package transient
  :ensure t
  :defer t)

;; ===============================================================
;;; UI

(use-package nerd-icons
  :ensure t)

(use-package nerd-icons-dired
  :ensure t
  :hook
  (dired-mode . nerd-icons-dired-mode))

(use-package nerd-icons-completion
  :ensure t
  :after(:all nerd-icons marginalia)
  :config
  (nerd-icons-completion-mode)
  (add-hook 'marginalia-mode-hook #'nerd-icons-completion-marginalia-setup))

(use-package rg-themes
  :ensure t
  :config
  (add-to-list 'custom-theme-load-path "~/.config/emacs/themes")
  (rg-themes-set 'rg-themes-custom)
  (window-divider-mode -1)
  (custom-set-faces
   '(font-lock-comment-face ((t (:slant normal))))
   '(font-lock-comment-delimiter-face ((t (:slant normal))))))

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
  (nerd-icons-scale-factor 1.0)
  (doom-modeline-modal-icon t)
  (doom-modeline-height 16)
  (doom-modeline-modal t)
  (doom-modeline-icon t)
  :config
  (defun doom-modeline-check-icon (_icon _unicode _text &optional _face) "")
  (setopt doom-modeline-always-show-macro-register t)
  (setopt doom-modeline-buffer-modification-icon nil)
  (dolist (face '(mode-line mode-line-inactive))
    (set-face-attribute face nil :font my/font :height 112))
  (add-hook 'doom-modeline-mode-hook
            (lambda ()
              (dolist (face (face-list))
                (when (string-prefix-p "doom-modeline" (symbol-name face))
                  (set-face-attribute face nil
                                      :weight 'normal :slant 'normal)))))
  (doom-modeline-mode 1))

(use-package focus
  :ensure t
  :defer t)

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
                      :foreground "#a67c6a")
  (set-face-attribute 'line-reminder-saved-sign-face nil
                      :foreground "#503f58"))


;; ===============================================================
;;; NAVIGATION

;; d/y/v + gs
(use-package flash
  :ensure (:host github :repo "Prgebish/flash")
  :commands (flash-jump flash-jump-continue flash-treesitter)
  :custom
  (flash-multi-window t)
  (flash-autojump t)
  (flash-nohlsearch t)
  (flash-char-jump-labels t)
  :init
  (with-eval-after-load 'evil
    (require 'flash-evil)
    (flash-evil-setup t)))

(use-package dired
  :ensure nil
  :hook
  (dired-mode . dired-hide-details-mode)
  (dired-mode . dired-omit-mode)
  (dired-mode . hl-line-mode)
  :custom
  (dired-listing-switches "-lah --group-directories-first --sort=extension")
  (dired-dwim-target t)
  (dired-omit-files "^\\.\\.?$")
  (dired-kill-when-opening-new-dired-buffer t)
  (dired-recursive-deletes 'top)
  (dired-recursive-copies 'always)
  (dired-free-space nil))

(use-package popper
  :ensure t
  :defer t
  :init
  (setopt popper-window-height 15)
  (setopt popper-reference-buffers
          '("\\*Async Shell Command\\*"
            "^\\*vterm.*\\*$"
            "\\*eldoc\\*"
            "Output\\*$"
            compilation-mode
            helpful-mode
            vterm-mode
            dired-mode
            help-mode))
  (setopt popper-mode-line "")
  (popper-mode +1))

(use-package buffer-move
  :ensure t
  :defer t)

(use-package restart-emacs
  :ensure t
  :defer t)

;; ===============================================================
;;; LSP

(use-package exec-path-from-shell
  :ensure t
  :config
  (exec-path-from-shell-initialize))

(use-package markdown-mode
  :ensure t
  :defer t
  :config
  (set-face-attribute 'markdown-code-face nil :font my/font)
  (set-face-attribute 'markdown-inline-code-face nil :font my/font))

(use-package lua-ts-mode
  :ensure nil
  :mode "\\.lua\\'")

(use-package ruby-ts-mode
  :ensure nil
  :mode "\\.rb\\'")

(use-package eglot
  :ensure nil
  :custom
  (eglot-autoshutdown t)
  (eglot-events-buffer-config '(:size 0 :format full))
  (eglot-prefer-plaintext nil)
  (jsonrpc-event-hook nil)
  :init
  (fset #'jsonrpc--log-event #'ignore)
  (defun my/eglot-setup ()
    (unless (memq major-mode '(emacs-lisp-mode lisp-mode))
      (eglot-ensure)))
  (add-hook 'prog-mode-hook #'my/eglot-setup)
  (with-eval-after-load 'eglot
    (add-to-list 'eglot-server-programs
                 '((ruby-mode ruby-ts-mode) "ruby-lsp"))
    (add-to-list 'eglot-server-programs
                 '((lua-mode lua-ts-mode) "lua-language-server"))))

(use-package eldoc
  :ensure nil
  :custom
  (eldoc-echo-area-use-multiline-p nil)
  (eldoc-echo-area-prefer-doc-buffer t)
  (eldoc-echo-area-display-truncation-message nil)
  (eldoc-documentation-strategy 'eldoc-documentation-compose)
  :init
  (global-eldoc-mode))

(use-package eldoc-box
  :ensure t
  :defer t)

(use-package flymake
  :ensure nil
  :defer t
  :hook
  (prog-mode . flymake-mode)
  :custom
  (flymake-show-diagnostics-at-end-of-line nil)
  (flymake-indicator-type 'margins)
  (flymake-margin-indicators-string
   '((error "!" compilation-error)
     (warning "?" compilation-warning)
     (note "i" compilation-info))))

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
  (setopt marginalia-annotators
        (assq-delete-all 'file marginalia-annotators)))

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
          xref-show-definitions-function #'consult-xref))

(use-package consult-dir
  :ensure t
  :defer t
  :config
  (defun my/consult-dir--strip-annotations (orig-fn &rest args)
    (let ((consult-dir-sources
           (mapcar (lambda (src)
                     (let ((val (if (symbolp src) (symbol-value src) src)))
                       (plist-put (copy-sequence val) :name nil)))
                   consult-dir-sources)))
      (apply orig-fn args)))
  (advice-add #'consult-dir :around #'my/consult-dir--strip-annotations))

(use-package embark
  :ensure t
  :defer t
  :init
  (setopt prefix-help-command #'embark-prefix-help-command)
  :config
  (defun embark-which-key-indicator ()
    (lambda (&optional keymap targets prefix)
      (if (null keymap)
          (which-key--hide-popup-ignore-command)
        (which-key--show-keymap
         (if (eq (plist-get (car targets) :type) 'embark-become)
             "Become"
           (format "Act on %s '%s'%s"
                   (plist-get (car targets) :type)
                   (embark--truncate-target (plist-get (car targets) :target))
                   (if (cdr targets) "…" "")))
         (if prefix
             (pcase (lookup-key keymap prefix 'accept-default)
               ((and (pred keymapp) km) km)
               (_ (key-binding prefix 'accept-default)))
           keymap)
         nil nil t (lambda (binding)
                     (not (string-suffix-p "-argument" (cdr binding))))))))

  (defun embark-hide-which-key-indicator (fn &rest args)
    "Hide the which-key indicator immediately when using the completing-read prompter."
    (which-key--hide-popup-ignore-command)
    (let ((embark-indicators
           (remq #'embark-which-key-indicator embark-indicators)))
      (apply fn args)))

  (advice-add #'embark-completing-read-prompter
              :around #'embark-hide-which-key-indicator)

  (setq embark-indicators
        '(embark-which-key-indicator
          embark-highlight-indicator
          embark-isearch-highlight-indicator)))

;; ===============================================================
;;; EDITING

(use-package move-text
  :ensure t
  :bind
  (("M-<up>"   . move-text-up)
   ("M-<down>" . move-text-down)))

(use-package sudo-edit
  :ensure t
  :defer t)

(use-package whitespace
  :ensure nil
  :defer t
  :hook
  (before-save . whitespace-cleanup)
  :init
  (defun my/toggle-whitespace-cleanup ()
    (interactive)
    (if (memq #'whitespace-cleanup before-save-hook)
        (progn
          (remove-hook 'before-save-hook #'whitespace-cleanup)
          (message "Whitespace cleanup on save: OFF"))
      (add-hook 'before-save-hook #'whitespace-cleanup)
      (message "Whitespace cleanup on save: ON"))))

;; ===============================================================
;;; WRITING & READING

(use-package org
  :ensure nil
  :hook
  ((org-mode . visual-line-mode)
   (org-mode . org-indent-mode)
   (org-mode . (lambda () (auto-fill-mode 0))))
  :custom
  (org-catch-invisible-edits 'show-and-error)
  (org-insert-heading-respect-content t)
  (org-cycle-hide-drawer-startup t)
  (org-hide-emphasis-markers t)
  (org-return-follows-link t)
  (org-hide-leading-stars t)
  (org-auto-align-tags nil)
  (org-special-ctrl-a/e t)
  (org-tags-column 0)
  (org-ellipsis " ∷")
  :config
  (setopt evil-auto-indent nil)
  (set-face-attribute 'org-ellipsis nil :underline nil))

(use-package olivetti
  :ensure t
  :hook
  (org-mode . olivetti-mode))

(use-package org-modern
  :ensure t
  :after org
  :hook
  (org-mode . org-modern-mode)
  :custom
  (org-modern-star 'replace)
  (org-modern-replace-stars '("◉" "○" "◈" "◇" "•"))
  (org-modern-checkbox '((?X . "☑") (?\s . "☐")))
  (org-modern-list '((?- . "›") (?+ . "»") (?* . "⋙"))))

(use-package org-tidy
  :ensure t
  :hook
  (org-mode . org-tidy-mode))

;; ===============================================================
;;; TERMINAL

(use-package vterm
  :ensure t
  :defer t
  :config
  (add-to-list 'vterm-keymap-exceptions "M-w")
  (define-key vterm-mode-map (kbd "M-w") #'kill-ring-save)
  (evil-define-key 'emacs vterm-mode-map (kbd "C-c") #'vterm--self-insert))

;; ===============================================================
;;; DOCS

(use-package helpful
  :ensure t
  :defer t)

(use-package devdocs
  :ensure t
  :defer t)

;; ===============================================================
;;; VERSION CONTROL

(use-package magit
  :ensure t
  :defer t)

;;; init.el ends here
