;;; init.el --- Emacs --- -*- lexical-binding: t; no-byte-compile: t; -*-
;;; Commentary:
;;; Code:

(require 'package)

(setq package-archives
      '(("gnu"    . "https://elpa.gnu.org/packages/")
        ("nongnu" . "https://elpa.nongnu.org/nongnu/")
        ("melpa"  . "https://melpa.org/packages/")))

(setq use-package-vc-prefer-newest t)
(require 'use-package)

;; ===============================================================
;;; MODULES

(add-to-list 'load-path (locate-user-emacs-file "lisp"))
(byte-recompile-directory (expand-file-name "lisp" user-emacs-directory) 0)
(require 'my-cache)
(require 'my-exec-path)
(require 'my-load-theme)
(require 'my-keybindings)
(require 'my-move-text)
(require 'my-text-ops)

;; ===============================================================
;;; EMACS

(use-package emacs
  :ensure nil
  :init
  (defun display-startup-echo-area-message () (message ""))

  :custom
  ;; startup & ui
  (display-fill-column-indicator-warning nil)
  (warning-minimum-level :emergency)
  (mode-line-percent-position nil)
  (ring-bell-function 'ignore)
  (initial-scratch-message "")
  (inhibit-startup-message t)
  (echo-keystrokes 0.1)
  (use-short-answers t)
  (use-dialog-box nil)

  ;; line numbers
  (display-line-numbers-type 'relative)
  (display-line-numbers-width 4)

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
  (undo-no-redo t)
  (tab-width 2)

  ;; treesit
  (treesit-auto-install-grammar 'always)
  (treesit-font-lock-level 4)
  (treesit-enabled-modes t)

  ;; files
  (find-file-suppress-same-file-warnings t)
  (kill-buffer-delete-auto-save-files t)
  (uniquify-buffer-name-style 'forward)
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

  ;; misc
  (native-comp-async-query-on-exit t)
  (ibuffer-show-empty-filter-groups nil)
  (ibuffer-human-readable-size t)
  (ibuffer-use-other-window t)

  :config
  ;; custom file and directories
  (setq custom-file (locate-user-emacs-file "custom-vars.el"))
  (load custom-file 'noerror 'nomessage)

  ;; modes
  (minibuffer-electric-default-mode 1)
  (minibuffer-depth-indicate-mode 1)
  (global-visual-line-mode 1)
  (global-auto-revert-mode 1)
  (delete-selection-mode 1)
  (file-name-shadow-mode 1)
  (electric-indent-mode 1)
  (global-hl-line-mode -1)
  (save-place-mode 1)
  (tooltip-mode -1)
  (savehist-mode 1)
  (recentf-mode 1)

  ;; hooks
  (add-hook 'emacs-startup-hook
          (lambda ()
            (message "Loaded in %s with %d packages."
                     (emacs-init-time) (length package-activated-list))))
  (add-hook 'minibuffer-setup-hook #'cursor-intangible-mode)
  (add-hook 'prog-mode-hook #'display-line-numbers-mode)

  ;; faces
  (defvar my/font "TX-02 Condensed")
  (set-face-attribute 'tooltip nil :font my/font)
  (set-face-attribute 'default nil :font my/font :height 115)
  (set-face-attribute 'minibuffer-nonselected nil :background 'unspecified)

  ;; misc
  (setq redisplay-skip-fontification-on-input nil)
  (put 'narrow-to-region 'disabled nil)
  (setq message-truncate-lines t)

  ;; skip internal buffers in switch-to-prev/next-buffer
  (defun skip-these-buffers (_window buffer _bury-or-kill)
    "Function for `switch-to-prev-buffer-skip'."
    (string-match "\\*[^*]+\\*" (buffer-name buffer)))
  (setq switch-to-prev-buffer-skip 'skip-these-buffers)

  ;; smart context clearing and quit handler
  (keymap-set key-translation-map "ESC" "C-g")
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

  :bind
  ("M-d"       . dired-jump)
  ("M-<right>" . end-of-line)
  ("M-<left>"  . my/beginning-of-line)
  ("RET"       . newline-and-indent))

;; ===============================================================
;;; THEMES

;; (use-package pixel-themes
;;   :ensure nil
;;   :load-path "~/.config/emacs/lisp/pixel-themes"
;;   :config
;;   (pixel-themes-load-theme 'pixel-themes-psygnosia))

(use-package pixel-themes
  :vc (:url "https://github.com/lucasobx/pixel-themes"))

;; ===============================================================
;;; KEYBINDINGS

(use-package which-key
  :ensure nil
  :hook
  (after-init . which-key-mode)
  :config
  (setopt which-key-max-description-length 28
          which-key-add-column-padding 1
          which-key-min-display-lines 5
          which-key-prefix-prefix ""
          which-key-separator " → "
          which-key-idle-delay 0.3)
  (set-face-attribute 'which-key-note-face nil :height 1.0)
  (setopt which-key-sort-order 'which-key-local-then-key-order))

(use-package devil
  :vc (:url "https://github.com/lucasobx/devil" :branch "dev")
  :custom
  (devil-highlight-repeatable t)
  (devil-prompt " %t")
  :config
  (global-devil-mode)
  (assoc-delete-all "%k z" devil-translations)
  (add-to-list 'devil-translations '("%k z" . "C-z"))
  (add-to-list 'devil-repeatable-keys
               '("%k . ." "%k . /"))
  (add-to-list 'devil-repeatable-keys
               '("%k d s" "%k d d" "%k d p" "%k d f"
                 "%k d w" "%k d (" "%k d [" "%k d {"))
  (add-to-list 'devil-repeatable-keys
               '("%k ; ;" "%k ; p" "%k ; f")))

;; ===============================================================
;;; UI

(use-package my-modeline
  :ensure nil
  :load-path "~/.config/emacs/lisp")

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
      (window-height . 0.35))
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
  (popper-window-height 16)
  (popper-mode-line "")
  (popper-reference-buffers
   '("\\*eldoc\\*"
     "\\*marginal notes\\*"
     "\\*Ibuffer\\*"
     "\\*eshell\\*"
     compilation-mode
     inf-ruby-mode
     ibuffer-mode
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
  (setopt spacious-padding-widths
          '(:internal-border-width 10
            :right-divider-width 1
            :mode-line-width 1
            :fringe-width 2))
  (spacious-padding-mode 1))

(use-package rainbow-delimiters
  :ensure t
  :hook
  (prog-mode . rainbow-delimiters-mode))

(use-package colorful-mode
  :ensure t
  :custom
  (colorful-prefix-string "■ ")
  (colorful-only-strings nil)
  (css-fontify-colors nil)
  (colorful-use-prefix t)
  :config
  (setcdr (assq 'colorful-mode minor-mode-map-alist)
          (make-sparse-keymap))
  (global-colorful-mode t)
  (add-to-list 'global-colorful-modes 'helpful-mode))

(use-package ansi-color
  :ensure nil
  :init
  (setenv "MANROFFOPT" "-P-c")
  :hook
  (compilation-filter . ansi-color-compilation-filter))

(use-package whitespace
  :ensure nil
  :defer t
  :hook (before-save . whitespace-cleanup))

;; ===============================================================
;;; NAVIGATION

(use-package bookmark
  :ensure nil
  :defer t
  :custom
  (bookmark-fringe-mark nil)
  (bookmark-save-flag 1))

(use-package dired
  :ensure nil
  :custom
  (dired-listing-switches "-lah --almost-all --group-directories-first --sort=extension")
  (dired-kill-when-opening-new-dired-buffer t)
  (dired-movement-style 'bounded-files)
  (dired-recursive-deletes 'always)
  (dired-recursive-copies 'always)
  (dired-auto-revert-buffer t)
  (hl-line-sticky-flag nil)
  (dired-omit-files "^\\.")
  (dired-omit-verbose nil)
  (dired-free-space nil)
  (dired-dwim-target t)
  :hook
  (dired-mode . dired-hide-details-mode)
  (dired-mode . dired-omit-mode)
  (dired-mode . hl-line-mode))

(use-package wdired
  :ensure nil
  :commands (wdired-change-to-wdired-mode))

(use-package dired-snacks
  :ensure nil
  :load-path "~/.config/emacs/lisp"
  :custom
  (dired-snacks-subtree-line-prefix "  ")
  (dired-snacks-mode-line-show-time nil)
  (dired-snacks-mode-line-show-omit nil)
  (dired-snacks-mode-line-show-size t)
  (dired-snacks-open-full-window t)
  (dired-snacks-external-app-alist
   '((("mkv" "mp4" "webm" "avi" "mov" "mpg" "m4v") "vlc")
     (("mp3" "flac" "wav" "ogg" "opus" "m4a" "aac") "vlc")
     ("pdf" "zen-browser")
     ;; no app specified: use gio/xdg-open (system default).
     (("png" "jpg" "jpeg" "gif" "bmp" "webp" "tiff" "svg" "ico" "avif"))
     (("xcf" "kra" "psd" "blend" "cbz" "cbr"))))
  :config
  (dired-snacks-mode 1))

;; ===============================================================
;;; COMPLETION

(use-package corfu
  :ensure t
  :init
  (global-corfu-mode)
  :custom
  (corfu-popupinfo-margin-width 0)
  (corfu-right-margin-width 0)
  (corfu-left-margin-width 0)
  (corfu-popupinfo-delay 1.0)
  (corfu-quit-no-match t)
  (corfu-scroll-margin 0)
  (corfu-auto-prefix 1)
  (corfu-min-width 40)
  (corfu-max-width 40)
  (corfu-bar-width 0)
  (corfu-auto nil)
  (corfu-count 5)
  :config
  (advice-add #'lsp-completion-at-point
              :around #'cape-wrap-noninterruptible)
  (defun my/corfu-popupinfo-once (&rest _)
    (corfu-popupinfo-mode 1)
    (advice-remove 'corfu--exhibit #'my/corfu-popupinfo-once))
  (advice-add 'corfu--exhibit :before #'my/corfu-popupinfo-once))

(use-package completion-preview
  :ensure nil
  :hook (after-init . global-completion-preview-mode)
  :bind
  ( :map completion-preview-active-mode-map
    ("M-n" . completion-preview-next-candidate))
  :custom
  (completion-preview-minimum-symbol-length 1)
  (completion-preview-exact-match-only nil)
  (completion-preview-idle-delay 0.3)
  :config
  (with-eval-after-load 'org
    (push 'org-self-insert-command completion-preview-commands))
  (defun my/detect-org-table ()
    "Return true if point in Org table."
    (and (derived-mode-p 'org-mode) (org-at-table-p)))
  (add-hook 'completion-preview-inhibit-functions
            #'my/detect-org-table))

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
  (setopt consult-fd-args
          '("fd" "--color=auto" "--full-path" "--hidden"))
  (setopt consult-buffer-sources '(consult-source-buffer))
  :config
  (setopt consult-buffer-filter
          (append consult-buffer-filter
                  '("\\*Async Shell Command\\*" "Output\\*$" "\\*Help\\*" "\\*Messages\\*"
                    "\\*eldoc\\*" "\\*helpful.*\\*" "\\*Ibuffer\\*" "\\*Warnings\\*"
                    "\\*eshell\\*" "\\*Compile-Log\\*" "*scratch*"
                    "\\*Async-native-compile-log\\*")))
  ;; prevent dired buffer from surfacing in consult-buffer when hidden by popper.
  (advice-add
   #'consult--buffer-query :filter-return
   (lambda (buffers)
     (seq-remove
      (lambda (buf)
        (with-current-buffer (if (consp buf) (cdr buf) buf)
          (derived-mode-p 'dired-mode)))
      buffers))))

;; ===============================================================
;;; LANGUAGES

(use-package lua-ts-mode
  :ensure nil
  :mode ("\\.lua\\'")
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
  (set-keymap-parent ruby-ts-mode-map prog-mode-map))

(use-package markdown-mode
  :ensure t
  :mode ("README\\.md\\'" . gfm-mode))

;; (use-package markdown-ts-mode
;;   :ensure nil)

(use-package glsl-mode
  :ensure t
  :mode ("\\.glsl\\'" . glsl-mode))

;; ===============================================================
;;; IDE

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
  ((lua-ts-mode ruby-ts-mode) . eglot-ensure))

(use-package consult-eglot
  :ensure t
  :after (consult eglot))

(use-package flycheck
  :ensure t
  :hook
  (prog-mode . flycheck-mode)
  ;; (prog-mode . flycheck-annotate-mode)
  :custom
  (flycheck-check-syntax-automatically '(save mode-enabled idle-change))
  (flycheck-display-errors-function #'flycheck-display-error-messages)
  (flycheck-idle-change-delay 0.5)
  (flycheck-indication-mode nil)
  (flycheck-eglot-exclusive nil)
  :config
  (setcdr (assq 'flycheck-mode minor-mode-map-alist)
          (make-sparse-keymap))
  (add-hook 'lisp-interaction-mode-hook (lambda () (flycheck-mode -1)))
  (add-hook 'glsl-mode-hook (lambda () (flycheck-mode -1)))
  (global-flycheck-eglot-mode 1))

(use-package consult-flycheck
  :ensure t
  :after (consult flycheck))

(use-package apheleia
  :ensure t
  :hook (ruby-ts-mode . apheleia-mode)
  :config
  (setf (alist-get 'ruby-ts-mode apheleia-mode-alist)
        'rubocop))

(use-package eldoc
  :ensure nil
  :init
  (global-eldoc-mode)
  :custom
  (eldoc-help-at-pt t)
  (eldoc-idle-delay 0.5)
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
               (get-buffer-process (current-buffer)) nil))))

;; ===============================================================
;;; GAMEDEV

(use-package livelove
  :ensure nil
  :load-path "~/.config/emacs/lisp/livelove"
  :hook (lua-ts-mode . global-livelove-mode)
  :custom
  (livelove-align-max-width 8)
  (livelove-align-values 'decimal)
  (livelove-auto-start-server t))

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
  :defer t
  :custom
  (shr-use-fonts nil))

;; ==============================================================
;;; EDITING

(use-package multiple-cursors
  :ensure t
  :config
  ;; prevent multiple-cursors from prompting about devil
  (add-to-list 'mc/cmds-to-run-once 'devil))

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
  (org-mode . turn-off-auto-fill)
  (org-mode . visual-line-mode)
  (org-mode . org-indent-mode)
  (org-mode . hl-line-mode)
  :config
  (set-face-attribute 'org-ellipsis nil :underline nil))

(use-package org-appear
  :vc (:url "https://github.com/awth13/org-appear")
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
  (eshell-visual-subcommands
   '(("git" "log" "diff" "show" "help")
     ("sudo" "dnf")
     ("docker" "run" "exec" "attach" "top" "logs" "stats" "compose")
     ("podman" "run" "exec" "attach" "top" "logs" "stats" "compose")))
  (eshell-scroll-to-bottom-on-input 'this)
  (eshell-scroll-show-maximum-output nil)
  (eshell-hist-ignoredups 'erase)
  (eshell-history-size 100000)
  (eshell-banner-message ""))

(use-package eshell-snacks
  :ensure nil
  :load-path "~/.config/emacs/lisp"
  :config
  (eshell-snacks-mode 1))

(use-package ghostel
  :ensure t
  :config
  (add-to-list 'ghostel-eval-cmds '("magit-status-setup-buffer" magit-status-setup-buffer)))

(use-package ghostel-eshell
  :hook (eshell-load . ghostel-eshell-visual-command-mode))

(use-package ghostel-compile
  :hook (after-init . ghostel-compile-global-mode))

;; ===============================================================
;;; VERSION CONTROL

(use-package magit
  :ensure t
  :defer t
  :init
  (setq magit-define-global-key-bindings nil)
  :preface
  (defun my/magit-kill-buffers ()
    "Restore window configuration and kill all Magit buffers."
    (interactive)
    (let ((buffers (magit-mode-get-buffers)))
      (magit-restore-window-configuration)
      (mapc #'kill-buffer buffers)))
  :bind
  (:map magit-status-mode-map ("q" . my/magit-kill-buffers))
  :custom
  (magit-section-visibility-indicators nil)
  :config
  (magit-process-apply-ansi-colors t)
  (keymap-set transient-map "<escape>" #'transient-quit-one))

(use-package diff-hl
  :ensure t
  :custom
  (diff-hl-draw-borders nil)
  :config
  (setcdr (assq 'diff-hl-mode minor-mode-map-alist)
          (make-sparse-keymap))
  (global-diff-hl-mode 1))

;;; init.el ends here
