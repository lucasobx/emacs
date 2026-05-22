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

(defvar my/font "Berkeley Mono ExtraCondensed Regular")
(defvar my/font-size 120)

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
  (display-fill-column-indicator-warning nil)
  (redisplay-skip-fontification-on-input t)
  (uniquify-buffer-name-style 'forward)
  (display-line-numbers-type 'relative)
  (warning-minimum-level :emergency)
  (ibuffer-human-readable-size t)
  (initial-major-mode 'text-mode)
  (display-line-numbers-width 4)
  (zone-all-windows-in-frame t)
  (initial-scratch-message "")
  (ring-bell-function 'ignore)
  (split-width-threshold 100)
  (inhibit-startup-message t)
  (treesit-font-lock-level 4)
  (message-truncate-lines t)
  (echo-keystrokes 0.1)
  (use-short-answers t)
  (use-dialog-box nil)
  (zone-all-frames t)
  (truncate-lines t)
  (line-spacing 1)
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
  ;; ui
  (set-face-attribute 'default nil :family my/font :height my/font-size)
  (set-face-attribute 'minibuffer-nonselected nil :background)
  (set-face-attribute 'tooltip nil :family my/font)
  (setq-default line-spacing 0)
  ;; minibuffer
  (add-hook 'minibuffer-setup-hook #'cursor-intangible-mode)
  (add-hook 'minibuffer-setup-hook (lambda () (setq truncate-lines t)))
  (minibuffer-depth-indicate-mode 1)
  (minibuffer-electric-default-mode 1)
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
  ;; smart context clearing and quit handler
  (define-key key-translation-map (kbd "ESC") (kbd "C-g"))
  (define-advice keyboard-quit (:around (quit) quit-context-dwim)
    (cond
    ((and (region-active-p)
          (not (active-minibuffer-window)))
      (keyboard-quit))
    ((derived-mode-p 'completion-list-mode)
      (delete-completion-window))
    ((active-minibuffer-window)
      (if (minibufferp)
          (minibuffer-keyboard-quit)
        (abort-recursive-edit)))
    (t
     (unless (or defining-kbd-macro executing-kbd-macro)
       (apply orig-fun args)))))

  :bind
  ("C-=" . text-scale-increase)
  ("C--" . text-scale-decrease)
  ("RET" . newline-and-indent))

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

(defun my/delete-dont-kill (arg)
  "Delete characters backward until encountering the beginning of a word.
   With argument ARG, do this that many times. Don't add to kill ring."
  (interactive "p")
  (delete-region (point) (progn (backward-word arg) (point))))

(defun my/backward-delete ()
  "Delete a word, a character, or whitespace."
  (interactive)
  (cond
   ((looking-back (rx (char word)) 1)
    (my/delete-dont-kill 1))
   ((looking-back (rx (seq (char word) (= 1 blank))) 1)
	(my/delete-dont-kill 1))
   ((looking-back (rx (char blank)) 1)
    (delete-horizontal-space t))
   (t
    (backward-delete-char-untabify 1))))

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
    "<left>"  '(evil-beginning-of-line :wk ("←" . "beg of line"))
    "<right>" '(evil-end-of-line :wk ("→" . "end of line"))
    "k" '(my/kill-buffer-window :wk "kill buffer")
    "b" '(consult-buffer :wk "search buffer")
    "p" '(consult-yank-pop :wk "copy hist")
    "/" '(flash-jump :wk "jump anywhere")
    "d" '(dired-jump :wk "file manager")
    "h" '(devdocs-lookup :wk "devdocs")
    "c" '(cheat-sh :wk "cheat sheet")
    "f" '(find-file :wk "find file")
    "t" '(ghostel :wk "terminal"))

  (my/keys
    "m"  '(:ignore t :wk "mark text")
    "ml" '(org-remark-mark-line :wk "mark line")
    "md" '(org-remark-delete :wk "mark delete")
    "mc" '(org-remark-change :wk "mark change")
    "mm" '(org-remark-mark :wk "mark region")
    "mo" '(org-remark-open :wk "open note")
    "mv" '(org-remark-view :wk "view note")
    ;; custom
    "mr" '(org-remark-mark-text-red :wk "text red")
    "mb" '(org-remark-mark-blue :wk "mark blue"))

  (my/keys
    "s"   '(:ignore t :wk "search")
    "s r" '(consult-recent-file :wk "recent files")
    "s l" '(consult-line-multi :wk "line in files")
    "s g" '(consult-ripgrep :wk "ripgrep")
    "s i" '(consult-imenu :wk "imenu")
    "s s" '(consult-line :wk "line")
    "s f" '(consult-fd :wk "file"))

  (my/keys
    :keymaps '(prog-mode-map)
    "l"   '(:ignore t :wk "lsp actions")
    "l l" '(lsp-bridge-diagnostic-list :wk "list errors")
    "l r" '(lsp-bridge-find-references :wk "references")
    "l c" '(lsp-bridge-code-action :wk "code actions")
    "l d" '(lsp-bridge-find-def :wk "definition")
    "l n" '(lsp-bridge-rename :wk "rename"))
  
  (my/keys
    :keymaps '(ruby-mode-map ruby-ts-mode-map)
    "r"   '(:ignore t :wk "ruby")
    "r r" '(ruby-send-buffer :wk "send buffer")
    "r s" '(ruby-send-region :wk "send region")
    "r l" '(ruby-send-line :wk "send line")
    "r i" '(inf-ruby :wk "open repl"))
  
  (general-def
    :states  '(normal insert visual emacs)
    :keymaps 'global
    "C-<backspace>" 'my/backward-delete
    "<f2>"  'wdired-change-to-wdired-mode   
    "C-,"   'popper-toggle
    "C-."   'popper-cycle
    "C-o"   'other-window)
  
  (general-def
    :keymaps 'global
    "C-c v" '(visual-line-mode :wk "truncated lines")
    "C-c f" '(magit-file-dispatch :wk "magit file")
    "C-c r" '(restart-emacs :wk "restart emacs")
    "C-c t" '(consult-theme :wk "change theme")
    "C-c h" '(helpful-at-point :wk "helpful")
    "C-c s" '(sudo-edit :wk "edit with sudo")
    "C-c l"   '((lambda () (interactive)
                (find-file (locate-user-emacs-file "init.el")))
              :wk "init.el"))
    
  (general-unbind
    :keymaps 'global
    "C-<wheel-down>" "C-<wheel-up>" "C-x C-z" "C-c ^" "C-z")
  (general-unbind
    :keymaps 'emacs-lisp-mode-map
    "C-c C-b" "C-c C-e" "C-c C-f")
  (general-unbind
    :keymaps 'winner-mode-map
    "C-c <left>" "C-c <right>"))

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
  (evil-mode 1))

(use-package evil-collection
  :ensure t
  :after evil
  :config
  (setopt evil-collection-mode-list '(dired ibuffer magit))
  (evil-collection-init))

(use-package evil-commentary
  :ensure t
  :after evil
  :config
  (evil-commentary-mode))

(use-package evil-goggles
  :ensure t
  :custom
  (evil-goggles-duration 0.100)
  (evil-goggles-enable-paste nil)
  :config
  (evil-goggles-mode)
  (evil-goggles-use-diff-faces))

(use-package transient
  :ensure nil
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

(use-package pixel-themes
  :ensure nil
  :load-path "~/.config/emacs/lisp/pixel-themes"
  :config
  (pixel-themes-set 'pixel-themes-miri16))

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
  (doom-modeline-mode 1))

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
                      :foreground (face-attribute 'line-number-current-line :foreground))
  (set-face-attribute 'line-reminder-saved-sign-face nil
                      :foreground (face-attribute 'default :background)))

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
  (dired-listing-switches "-lah --almost-all --group-directories-first --sort=extension")
  (dired-hide-details-hide-absolute-location t)
  (dired-dwim-target t)
  (dired-omit-files "^\\.")
  (dired-kill-when-opening-new-dired-buffer t)
  (dired-recursive-deletes 'top)
  (dired-recursive-copies 'always)
  (dired-free-space nil))

(use-package wdired
  :ensure nil
  :commands (wdired-change-to-wdired-mode))

(use-package popper
  :ensure t
  :defer t
  :init
  (setopt popper-window-height 15)
  (setopt popper-reference-buffers
          '("\\*Async Shell Command\\*" "^\\*ghostel.*\\*" "\\*eldoc\\*" "Output\\*$"
            "\\*cheat.sh\\*$"
            compilation-mode
            inf-ruby-mode
            devdocs-mode
            helpful-mode
            ghostel-mode
            dired-mode
            help-mode))
  (setopt popper-mode-line "")
  (popper-mode +1))

;; ===============================================================
;;; TREESITTER

(use-package markdown-ts-mode
  :ensure nil)

(use-package lua-ts-mode
  :ensure nil
  :mode "\\.lua\\'"
  :custom
  (lua-ts-indent-offset 2))

(use-package ruby-ts-mode
  :ensure nil
  :mode ("\\.rb\\'" "Rakefile\\'" "Gemfile\\'")
  :custom
  (ruby-indent-level 2)
  :config
  (add-to-list 'treesit-language-source-alist
               '(ruby "https://github.com/tree-sitter/tree-sitter-ruby" "master" "src")))

;; ===============================================================
;;; LSP

(use-package treesit-auto
  :ensure t
  :after emacs
  :custom
  (treesit-auto-install 'prompt)
  :config
  (treesit-auto-add-to-auto-mode-alist 'all)
  (global-treesit-auto-mode t))

(use-package inf-ruby
  :ensure t
  :hook
  (ruby-ts-mode . inf-ruby-minor-mode)
  :config
  (when (executable-find "pry")
    (add-to-list 'inf-ruby-implementations '("pry" . "pry"))
    (setq inf-ruby-default-implementation "pry"))
  (add-hook 'inf-ruby-mode-hook
            (lambda ()
              (set-process-query-on-exit-flag
               (get-buffer-process (current-buffer)) nil))))

(use-package mason
  :ensure t
  :config
  (mason-setup))

(use-package lsp-bridge
  :ensure '(lsp-bridge :type git :host github :repo "manateelazycat/lsp-bridge"
            :files (:defaults "*.el" "*.py" "acm" "core" "langserver" "multiserver" "resources")
            :build (:not compile))
  :custom
  (lsp-bridge-lua-lsp-server "sumneko")
  (lsp-bridge-ruby-lsp-server "ruby-lsp")
  (lsp-bridge-python-lsp-server "pyright")
  (lsp-bridge-enable-document-highlight t)
  (lsp-bridge-enable-auto-format-code t)
  (lsp-bridge-enable-hover-diagnostic t)
  (lsp-bridge-enable-diagnostics t)
  (lsp-bridge-enable-org-babel t)
  (acm-enable-doc nil)
  (acm-menu-length 5)
  :config
  (setopt lsp-bridge-default-mode-hooks
          '(emacs-lisp-mode-hook
            ruby-mode-hook
            ruby-ts-mode-hook
            lua-ts-mode-hook
            org-mode-hook))
  (global-lsp-bridge-mode))

(use-package eldoc
  :ensure nil
  :custom
  (eldoc-help-at-pt t)
  (eldoc-documentation-strategy 'eldoc-documentation-compose)
  (eldoc-echo-area-display-truncation-message nil)
  (eldoc-echo-area-prefer-doc-buffer t)
  (eldoc-echo-area-use-multiline-p nil)
  :init
  (global-eldoc-mode))

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

(use-package consult-dir
  :ensure t
  :defer t
  :bind
  ("C-c c" . consult-dir))

(use-package yasnippet
  :ensure t
  :defer t)

;; ==============================================================
;;; EDITING

(use-package move-text
  :ensure t
  :bind
  (("M-<up>" . move-text-up)
   ("M-<down>" . move-text-down)))

(use-package sudo-edit
  :ensure t
  :defer t)

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
  (org-agenda-files '("~/Documents/org"))
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

(use-package evil-org
  :ensure t
  :after org
  :hook
  (org-mode . evil-org-mode))

(use-package olivetti
  :ensure t
  :hook
  (org-mode . olivetti-mode))

(use-package org-appear
  :ensure (:host github :repo "awth13/org-appear")
  :hook
  (org-mode . org-appear-mode)
  :custom
  (org-appear-autoemphasis t))

(use-package org-modern
  :ensure t
  :hook
  (org-mode . org-modern-mode)
  :custom
  (org-modern-star 'replace)
  (org-modern-replace-stars '("◉" "○" "◈" "◇" "•"))
  (org-modern-checkbox nil)
  (org-modern-list '((?- . "›") (?+ . "»") (?* . "»»"))))

(use-package org-remark
  :ensure t
  :init
  (org-remark-global-tracking-mode +1)
  :custom
  (org-remark-notes-file-name "~/.config/emacs/org/annotations.org")
  :config
  (org-remark-create "custom1"
    'mode-line-active
    '(CATEGORY "custom")))

(use-package org-tidy
  :ensure t
  :hook
  (org-mode . org-tidy-mode))

;; ===============================================================
;;; TERMINAL

(use-package ghostel
  :ensure t
  :defer t
  :hook
  (ghostel-mode . evil-emacs-state))

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
  (setq shr-use-fonts nil))

(use-package cheat-sh
  :load-path "~/.config/emacs/lisp/cheat-sh"
  :custom
  (cheat-sh-server-url "https://cheat.sh")
  (cheat-sh-query-options ""))

;; ===============================================================
;;; VERSION CONTROL

(use-package magit
  :ensure t
  :defer t
  :config
  (keymap-set transient-map "<escape>" 'transient-quit-one))

;;; init.el ends here
