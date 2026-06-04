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
  (initial-major-mode 'text-mode)
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
  (set-face-attribute 'minibuffer-nonselected nil :background)
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
  ("C-+"       . text-scale-increase)
  ("<f2>"      . wdired-change-to-wdired-mode)
  ("<f1>"      . scratch-buffer)
  ("C-<tab>"   . other-window)
  ("M-<left>"  . beginning-of-line)
  ("M-<right>" . end-of-line))

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
  "Execute CMD as a shell command and stream output into buffer."
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

(defun my/open-line-below ()
  "Create a new line below and move to it."
  (interactive)
  (end-of-line)
  (newline-and-indent))

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

(defun my/delete-paragraph () (interactive) (my/delete-thing 'paragraph))
(defun my/delete-symbol () (interactive) (my/delete-thing 'symbol))
(defun my/delete-defun () (interactive) (my/delete-thing 'defun))
(defun my/delete-line () (interactive) (my/delete-thing 'line))

(defun my/delete-in-brackets () (interactive) (my/delete-inside #'my/inside-brackets))
(defun my/delete-in-parens () (interactive) (my/delete-inside #'my/inside-parens))
(defun my/delete-in-braces () (interactive) (my/delete-inside #'my/inside-braces))

(defun my/copy-paragraph () (interactive) (my/copy-thing 'paragraph))
(defun my/copy-symbol () (interactive) (my/copy-thing 'symbol))
(defun my/copy-defun () (interactive) (my/copy-thing 'defun))
(defun my/copy-word () (interactive) (my/copy-thing 'word))
(defun my/copy-line () (interactive) (my/copy-thing 'line))

(defun my/copy-inside-brackets () (interactive) (my/copy-inside #'my/inside-brackets))
(defun my/copy-inside-parens () (interactive) (my/copy-inside #'my/inside-parens))
(defun my/copy-inside-braces () (interactive) (my/copy-inside #'my/inside-braces))

(defun my/toggle-comment-paragraph () (interactive) (my/toggle-comment-thing 'paragraph))
(defun my/toggle-comment-defun () (interactive) (my/toggle-comment-thing 'defun))
(defun my/toggle-comment-line () (interactive) (comment-line 1))

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
  (global-devil-mode))

(use-package general
  :ensure (:wait t)
  :demand t
  :config
  (general-auto-unbind-keys)
  (general-unbind "C-<wheel-down>" "C-<wheel-up>" "C-x C-z" "C-c ^" "C-z")
  (general-unbind :keymaps 'emacs-lisp-mode-map "C-c C-b" "C-c C-e" "C-c C-f")
  (general-unbind :keymaps 'winner-mode-map "C-c <left>" "C-c <right>")
  ;; (general-unbind :keymaps 'inf-ruby-minor-mode-map
    ;; "C-c C-l" "C-c C-b" "C-c C-k" "C-c C-q" "C-c C-r" "C-c C-s" "C-c C-x" "C-c C-z"
    ;; "C-c M-b" "C-c M-r" "C-c M-x")

  ;; definers
  (general-create-definer my/keys    :keymaps 'override)
  (general-create-definer my/delete  :keymaps 'override :prefix "C-d")
  (general-create-definer my/emacs   :keymaps 'override :prefix "C-e")
  (general-create-definer my/file    :keymaps 'override :prefix "C-f")
  (general-create-definer my/lsp     :keymaps 'override :prefix "C-l")
  (general-create-definer my/mark    :keymaps 'override :prefix "C-q")
  (general-create-definer my/search  :keymaps 'override :prefix "C-s")
  (general-create-definer my/tools   :keymaps 'override :prefix "C-t")
  (general-create-definer my/copy    :keymaps 'override :prefix "C-y")
  (general-create-definer my/comment :keymaps 'override :prefix "C-;")

  (general-def ;; dired
    :keymaps 'dired-mode-map
    "M-<left>" 'dired-up-directory)

  (my/keys
    "M-<up>" 'move-text-up
    "M-<down>" 'move-text-down
    "C-<backspace>" 'my/backward-delete
    "M-p" 'mc/mark-previous-like-this
    "M-n" 'mc/mark-next-like-this
    "C-k" 'my/kill-buffer-window
    "C-o" 'my/open-line-below
    "C-=" 'er/expand-region
    "C-," 'popper-toggle
    "C-." 'popper-cycle
    "M-j" 'flash-jump
    "C-p" 'yank)

  (my/delete
    "p" '(my/delete-paragraph       :wk "delete paragraph")
    "y" '(my/delete-symbol          :wk "delete symbol")
    "f" '(my/delete-defun           :wk "delete defun")
    "d" '(my/delete-line            :wk "delete line")
    "(" '(my/delete-in-parens       :wk "delete inside ()")
    "[" '(my/delete-in-brackets     :wk "delete inside []")
    "{" '(my/delete-in-braces       :wk "delete inside {}"))

  (my/emacs
    "i" '((lambda () (interactive)
                (find-file (locate-user-emacs-file "init.el")))
              :wk "open init.el")
    "s" '(sudo-edit           :wk "edit with sudo")
    "v" '(visual-line-mode    :wk "truncate lines")
    "r" '(restart-emacs       :wk "restart emacs")
    "m" '(magit-status        :wk "magit status"))
  
  (my/file
    "b" '(consult-buffer        :wk "switch buffer")
    "p" '(consult-yank-pop      :wk "copy history")
    "F" '(consult-fd            :wk "fd-find file")
    "r" '(rename-visited-file   :wk "rename file")
    "f" '(find-file             :wk "find file")
    "s" '(save-buffer           :wk "save"))

  (my/lsp ;; lsp/prog-mode
    :keymaps '(prog-mode-map)
    "c" '(lsp-bridge-code-action     :wk "code actions")
    "e" '(lsp-bridge-diagnostic-list :wk "list errors")
    "R" '(lsp-bridge-find-references :wk "references")
    "d" '(lsp-bridge-find-def        :wk "definition")
    "n" '(lsp-bridge-rename          :wk "rename"))
  
  (my/lsp ;; ruby/prog-mode
    :keymaps '(ruby-mode-map ruby-ts-mode-map)
    "b" '(ruby-send-buffer :wk "send buffer")
    "s" '(ruby-send-region :wk "send region")
    "l" '(ruby-send-line   :wk "send line")
    "r" '(inf-ruby         :wk "open repl"))

  (my/mark
    "m" '(org-remark-mark             :wk "mark region")
    "d" '(org-remark-delete           :wk "delete mark")
    "c" '(org-remark-change           :wk "change mark")
    "l" '(org-remark-mark-line        :wk "mark line")
    "o" '(org-remark-open             :wk "open note")
    "v" '(org-remark-view             :wk "view note")
    "b" '(org-remark-mark-custom-mark :wk "custom mark")
    "r" '(org-remark-mark-color-text  :wk "color text"))

  (my/search
    "S" '(consult-line-multi  :wk "line in files")
    "r" '(consult-recent-file :wk "recent files")
    "b" '(consult-bookmark    :wk "bookmarks")
    "g" '(consult-ripgrep     :wk "ripgrep")
    "i" '(consult-imenu       :wk "imenu")
    "s" '(consult-line        :wk "line"))

  (my/tools
    "h" '(helpful-at-point :wk "helpful at point")
    "c" '(cheat-sh         :wk "cheat sheet")
    "t" '(ghostel          :wk "terminal")
    "d" '(devdocs-lookup   :wk "devdocs"))

  (my/comment
    "p" '(my/toggle-comment-paragraph :wk "paragraph")
    "f" '(my/toggle-comment-defun     :wk "defun")
    ";" '(my/toggle-comment-line      :wk "line"))
  
  (my/copy
    "p" '(my/copy-paragraph       :wk "copy paragraph")
    "s" '(my/copy-symbol          :wk "copy symbol")
    "f" '(my/copy-defun           :wk "copy defun")
    "y" '(my/copy-line            :wk "copy line")
    "(" '(my/copy-inside-parens   :wk "inside ()")
    "[" '(my/copy-inside-brackets :wk "inside []")
    "{" '(my/copy-inside-braces   :wk "inside {}")))

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
      (window-height . 0.3)
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
   '("^\\*ghostel.*\\*" "\\*eldoc\\*" "\\*cheat.sh*\\*$"
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
  :after(:all nerd-icons marginalia)
  :config
  (nerd-icons-completion-mode)
  (add-hook 'marginalia-mode-hook #'nerd-icons-completion-marginalia-setup))

(use-package pixel-themes
  :ensure (:host github :repo "lucasobx/pixel-themes")
  :config
  (pixel-themes-mode 1)
  (pixel-themes-load-theme 'pixel-themes-psygnosia))

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
  (dired-omit-files "^\\.")
  (dired-free-space nil)
  (dired-dwim-target t)
  :hook
  (dired-mode . dired-hide-details-mode)
  (dired-mode . dired-omit-mode)
  (dired-mode . hl-line-mode))

(use-package wdired
  :ensure nil
  :commands (wdired-change-to-wdired-mode))

;; ===============================================================
;;; TREESITTER

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

(use-package treesit-auto
  :ensure t
  :custom
  (treesit-auto-install t)
  :config
  (global-treesit-auto-mode t))

;; ===============================================================
;;; LSP

(use-package inf-ruby
  :ensure t
  :hook
  (ruby-ts-mode . inf-ruby-minor-mode)
  :config
  (when (executable-find "pry")
    (add-to-list 'inf-ruby-implementations '("pry" . "pry"))
    (setopt inf-ruby-default-implementation "pry"))
  (add-hook 'inf-ruby-mode-hook
            (lambda ()
              (set-process-query-on-exit-flag
               (get-buffer-process (current-buffer)) nil))))

(use-package mason
  :ensure t
  :config
  (mason-setup))

(use-package eldoc
  :ensure nil
  :init
  (global-eldoc-mode)
  :custom
  (eldoc-help-at-pt t)
  (eldoc-documentation-strategy 'eldoc-documentation-compose)
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

(use-package yasnippet
  :ensure t
  :defer t)

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

;;; init.el ends here
