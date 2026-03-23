;;; init.el --- Emacs --- -*- lexical-binding: t; no-byte-compile: t; -*-
;;; ===============================================================
;;; Commentary:
;;; Code:

;; elpaca package manager
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

;;; ===============================================================
;;; Core settings

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
  (warning-minimum-level :emergency)
  (display-line-numbers-width 3)
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

;;; ===============================================================
;;; Custom functions

(defun my/jump-to-end-of-block ()
  (interactive)
  (beginning-of-defun)
  (forward-sexp))

(defun my/vterm-only ()
  (interactive)
  (require 'vterm)
  (let ((display-buffer-alist nil)) 
    (vterm)
    (delete-other-windows)
    (let ((proc (get-buffer-process (current-buffer))))
          (when proc (set-process-query-on-exit-flag proc nil)))))

(defun my/kill-buffer-and-window ()
  (interactive)
  (let ((buffer (current-buffer)))
    (when (and (> (count-windows) 1)
               (not (one-window-p)))
      (delete-window))
    (kill-buffer buffer)))

;;; ===============================================================
;;; Keybindings

(use-package which-key
  :ensure nil
  :hook
  (after-init . which-key-mode)
  :config
  (setopt which-key-idle-delay 0.2
          which-key-add-column-padding 1
          which-key-min-display-lines 5
          which-key-separator " → ")
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
    "k"     '(my/kill-buffer-and-window :wk "kill buffer")
    "["     '(evil-beginning-of-line :wk "beg-line")
    "]"     '(evil-end-of-line :wk "end-line")
    "/"     '(flash-jump :wk "flash")
    
    ;; --- buffers
    "b"         '(:ignore t :wk "buffer")
    "b r"       '(revert-buffer :wk "reload buffer")
    "b b"       '(consult-buffer :wk "switch buffer")
    "b <left>"  '(previous-buffer :wk "previous buffer")
    "b <right>" '(next-buffer :wk "next buffer")

    ;; --- dired
    "d"   '(:ignore t :wk "dired")
    "d d" '(dired :wk "open directory")
    "d j" '(dired-jump :wk "jump to directory")
    
    ;; --- emacs
    "e"   '(:ignore t :wk "emacs")
    "e s" '(sudo-edit :wk "sudo edit file")
    "e p" '(check-parens :wk "check parens")
    "e r" '(restart-emacs :wk "restart emacs")
    "e f" '(eval-last-sexp :wk "eval expression")
    "e m" '(consult-mode-command :wk "mode commands")
    "e e" '(my/jump-to-end-of-block :wk "jump to end of block")
    "e c" '((lambda () (interactive)
              (find-file (locate-user-emacs-file "init.el")))
            :wk "edit config")
    
    ;; --- help
    "h"   '(:ignore t :wk "help")
    "h d" '(devdocs-lookup :wk "devdocs")
    "h h" '(helpful-at-point :wk "at point")
    "h v" '(helpful-variable :wk "variable")
    "h f" '(helpful-function :wk "function")

    ;; --- search
    "s"   '(:ignore t :wk "search")
    "s s" '(consult-line :wk "line")
    "s i" '(consult-imenu :wk "imenu")
    "s f" '(consult-find :wk "find file")
    "s g" '(consult-ripgrep :wk "ripgrep")
    "s l" '(consult-line-multi :wk "line-multi")
    "s d" '(consult-dir :wk "recent directories")
    "s r" '(consult-recent-file :wk "recent files")

    ;; --- toggles
    "t"   '(:ignore t :wk "toggle")
    "t t" '(vterm-toggle :wk "vterm")
    "t f" '(focus-mode :wk "focus mode")
    "t l" '(visual-line-mode :wk "truncated lines")
    
    ;; --- windows
    "w"         '(:ignore t :wk "windows")
    "w w"       '(evil-window-split :wk "horizontal split")
    "w v"       '(evil-window-vsplit :wk "vertical split")
    "w c"       '(evil-window-delete :wk "close window")
    "w n"       '(evil-window-new :wk "new window")
    "w <right>" '(buf-move-right :wk "move right")
    "w <left>"  '(buf-move-left :wk "move left")
    "w <down>"  '(buf-move-down :wk "move down")
    "w <up>"    '(buf-move-up :wk "move up"))
  (my/keys
    :keymaps 'org-mode-map
    "o"   '(:ignore t :wk "org")
    "o o" '(org-toggle-checkbox :wk "toggle checkbox")
    "o p" '(org-tidy-untidy-buffer :wk "edit property")
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

(use-package evil-commentary
  :ensure t
  :after evil
  :config
  (evil-commentary-mode))

(use-package evil-surround
  :ensure t
  :config
  (global-evil-surround-mode 1))

;; (use-package evil-tutor
;;   :ensure t
;;   :defer t)

;;; ===============================================================
;;; UI

(use-package nerd-icons 
  :ensure t)

(use-package rg-themes
  :ensure t
  :config
  (add-to-list 'custom-theme-load-path "~/.config/emacs/themes")
  (rg-themes-set 'rg-themes-custom)
  (window-divider-mode -1))

(use-package rainbow-delimiters
  :ensure t
  :hook
  (prog-mode . rainbow-delimiters-mode))

(use-package doom-modeline
  :ensure t
  :custom
  (doom-modeline-height 25)
  (doom-modeline-modal t)
  (doom-modeline-modal-icon t)
  (doom-modeline-icon t)
  (doom-modeline-major-mode-icon t)
  (doom-modeline-buffer-encoding nil)
  (doom-modeline-total-line-number t)
  (nerd-icons-scale-factor 1.0)
  :config
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
                      :foreground "#758672"))

;;; ===============================================================
;;; Navigation

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
    (flash-evil-setup t))
  :config
  (require 'flash-isearch)
  (flash-isearch-mode 1))

(use-package dired
  :ensure nil
  :hook
  (dired-mode . dired-hide-details-mode)
  (dired-mode . hl-line-mode)
  :custom
  (dired-listing-switches "-lah --group-directories-first")
  (dired-dwim-target t)
  (dired-kill-when-opening-new-dired-buffer t)
  (dired-recursive-deletes 'top)
  (dired-recursive-copies 'always))

(use-package nerd-icons-dired
  :ensure t
  :hook
  (dired-mode . nerd-icons-dired-mode))

(use-package buffer-move
  :ensure t
  :defer t)

(use-package restart-emacs
  :ensure t
  :defer t)

;;; ===============================================================
;;; LSP

(use-package exec-path-from-shell
  :ensure t
  :config
  (exec-path-from-shell-initialize))

(use-package lua-ts-mode
  :ensure nil
  :mode "\\.lua\\'")

;;; ===============================================================
;;; Completion

(use-package vertico
  :ensure t
  :custom
  (vertico-count 7)
  :init
  (vertico-mode))

(use-package marginalia
  :ensure t
  :defer
  :after vertico
  :init
  (marginalia-mode))

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
  :defer t)

(use-package consult-dir
  :ensure t
  :defer t)

;;; ===============================================================
;;; Editing

(use-package move-text
  :ensure t
  :bind
  (("M-<up>"   . move-text-up)
   ("M-<down>" . move-text-down)))

(use-package sudo-edit
  :ensure t
  :defer t)

(use-package org
  :ensure nil
  :hook 
  ((org-mode . visual-line-mode)
   (org-mode . org-indent-mode)
   (org-mode . (lambda () (auto-fill-mode 0))))
  :custom
  (org-hide-emphasis-markers t)
  (org-hide-leading-stars t)
  (org-ellipsis " ∷")
  (org-auto-align-tags nil)
  (org-tags-column 0)
  (org-catch-invisible-edits 'show-and-error)
  (org-special-ctrl-a/e t)
  (org-insert-heading-respect-content t)
  (org-cycle-hide-drawer-startup t)
  (org-return-follows-link t)
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

;;; ===============================================================
;;; Misc

(use-package helpful
  :ensure t
  :defer t) 

(use-package devdocs
  :ensure t
  :defer t)

(use-package vterm
  :ensure t
  :commands vterm
  :defer t
  :config
  (add-to-list 'vterm-keymap-exceptions "M-w")
  (define-key vterm-mode-map (kbd "M-w") #'kill-ring-save)
  (evil-define-key 'emacs vterm-mode-map (kbd "C-c") #'vterm--self-insert))
  
(use-package vterm-toggle
  :ensure t
  :after vterm
  :commands vterm-toggle
  :config
  (setopt vterm-toggle-fullscreen-p nil)
  (add-to-list 'display-buffer-alist
             '((lambda (buffer-or-name _)
                   (let ((buffer (get-buffer buffer-or-name)))
                     (with-current-buffer buffer
                       (or (equal major-mode 'vterm-mode)
                           (string-prefix-p vterm-buffer-name (buffer-name buffer))))))
                (display-buffer-reuse-window display-buffer-at-bottom)
                (reusable-frames . visible)
                (window-height . 0.3))))

;;; init.el ends here
