;;; my-keybindings.el --- Keybindings  -*- lexical-binding: t; -*-

;; Author: Lucas
;; Keywords: convenience

;;; Commentary:

;; Personal keybindings: a global override keymap, region-aware
;; prefixes with which-key labels, and per-mode bindings.

;;; Code:

(defvar winner-mode-map)
(defvar ruby-ts-mode-map)
(defvar dired-mode-map)
(defvar org-mode-map)
(defvar completion-preview-active-mode-map)
(defvar ghostel-semi-char-mode-map)
(defvar magit-status-mode-map)
(defvar transient-map)

(declare-function ghostel-send-key "ghostel")
(declare-function magit-mode-get-buffers "magit-mode")
(declare-function magit-restore-window-configuration "magit-mode")

;; ===============================================================
;;; SETUP

(require 'which-key)
(defalias 'my/wk-add #'which-key-add-key-based-replacements)

(defvar my/override-map (make-sparse-keymap))
(define-minor-mode my/override-mode
  "Global minor mode holding my override keybindings."
  :global t :group 'convenience :keymap my/override-map)
(add-to-list 'emulation-mode-map-alists
             `((my/override-mode . ,my/override-map)))
(my/override-mode 1)

;; ===============================================================
;;; HELPERS
;;
;; a binding is (KEY COMMAND [DESC]).  DESC labels it in which-key,
;; and DESC t hides it.  each binder takes a batch of bindings:
;;   (my/bind '("C-t t" eshell "eshell")
;;            '("C-t m" magit-status "magit"))

(defun my/wk-hide (&rest keys)
  "Hide each of KEYS from the which-key popup."
  (dolist (key keys)
    (let ((kd (key-description (kbd key))))
      (push (cons (cons (concat "\\`" (regexp-quote kd) "\\'") nil) t)
            which-key-replacement-alist))))

(defun my/bind (&rest bindings)
  "Bind each (KEY COMMAND [DESC]) in BINDINGS in `my/override-map'."
  (declare (indent 0))
  (apply #'my/bind-sub my/override-map nil bindings))

(defun my/bind-prefix (prefix label &rest bindings)
  "Bind each (KEY COMMAND [DESC]) in BINDINGS under PREFIX, labeled LABEL."
  (declare (indent 2))
  (my/wk-add prefix label)
  (apply #'my/bind
         (mapcar (lambda (binding)
                   (cons (concat prefix " " (car binding)) (cdr binding)))
                 bindings)))

(defun my/bind-local (keymap &rest bindings)
  "Bind each (KEY COMMAND [DESC]) in BINDINGS in KEYMAP."
  (declare (indent 1))
  (dolist (binding bindings)
    (seq-let (key command desc) binding
      (keymap-set keymap key (if desc (cons desc command) command)))))

(defun my/bind-sub (map prefix &rest bindings)
  "Bind each (KEY COMMAND [DESC]) in BINDINGS in MAP.
Each which-key label is registered under PREFIX + KEY.  DESC t hides it."
  (declare (indent 2))
  (dolist (binding bindings)
    (seq-let (key command desc) binding
      (keymap-set map key command)
      (let ((full (if prefix (concat prefix " " key) key)))
        (cond ((eq desc t) (my/wk-hide full))
              (desc         (my/wk-add full desc)))))))

(defun my/region-aware-prefix (map command)
  "Return a binding giving COMMAND on an active region, else prefix MAP."
  `(menu-item "" ,map
              :filter ,(lambda (real) (if (use-region-p) command real))))

;; ===============================================================
;;; COMMANDS

(defun my/find-init-file ()
  "Open the user init file."
  (interactive)
  (find-file (locate-user-emacs-file "init.el")))

(defun my/kill-buffer-and-window ()
  "Kill the current buffer, and its window when that can be deleted."
  (interactive)
  (if (eq (window-deletable-p) t)
      (kill-buffer-and-window)
    (kill-current-buffer)))

(defun my/system-buffers ()
  "Switch to a system buffer."
  (interactive)
  (let ((bufs (seq-filter
               (lambda (b) (string-match-p "\\`\\*" (buffer-name b)))
               (buffer-list))))
    (switch-to-buffer
     (completing-read "System buffer: "
                      (mapcar #'buffer-name bufs)
                      nil t))))

(defun isearch-copy-selected-word ()
  "Copy the current `isearch` selection to the kill ring."
  (interactive)
  (when isearch-other-end
    (copy-region-as-kill isearch-other-end (point))
    (isearch-exit)))

(defun my/ghostel-backward-delete ()
  "Send M-<backspace> to the terminal."
  (interactive)
  (ghostel-send-key "backspace" "meta"))

(defun my/magit-kill-buffers ()
  "Restore window configuration and kill all Magit buffers."
  (interactive)
  (let ((buffers (magit-mode-get-buffers)))
    (magit-restore-window-configuration)
    (mapc #'kill-buffer buffers)))

;; ===============================================================
;;; UNBINDINGS

(keymap-unset key-translation-map "C-x 8" t)

(dolist (key '("C-<wheel-down>" "C-<wheel-up>" "C-c ^" "C-z" "C-h" "C-x" "M-g"))
  (keymap-global-unset key t))

;; ===============================================================
;;; GLOBAL

;; escape quits like C-g
(keymap-set key-translation-map "ESC" "C-g")

;; tools
(my/bind
  '("<f1>" scratch-buffer)
  '("<f3>" diff-hl-show-hunk)
  '("<f4>" my/rotate-theme)
  '("C-z"  dired-snacks-zoxide)
  '("C-f"  dired-snacks-find)
  '("C-t"  ghostel))

;; buffers and windows
(my/bind
  '("C-b"     consult-buffer)
  '("C-k"     my/kill-buffer-and-window)
  '("C-<tab>" other-window)
  '("C-,"     popper-toggle)
  '("C-<"     popper-cycle))

;; editing
(my/bind
  '("C-v"           yank)
  '("C-<backspace>" my/backward-delete)
  '("M-u"           upcase-dwim)
  '("M-c"           capitalize-dwim)
  '("M-<up>"        my/move-text-up)
  '("M-<down>"      my/move-text-down)
  '("C-0"           my/wrap-parens)
  '("C-]"           my/wrap-brackets))

;; text size
(my/bind
  '("C-=" text-scale-increase)
  '("C--" text-scale-decrease))

;; overridable by modes
(my/bind-local global-map
  '("<f2>"      magit-status)
  '("M-d"       dired-jump)
  '("M-m"       mark-paragraph)
  '("M-l"       downcase-dwim)
  '("C-o"       my/open-line-below)
  '("M-k"       kill-line)
  '("M-p"       duplicate-dwim)
  '("M-<right>" my/end-of-line)
  '("M-<left>"  my/beginning-of-line)
  '("RET"       newline-and-indent))

;; ===============================================================
;;; PREFIX GROUPS
;;
;; with an active region, bare C-d/C-y act as kill-region/kill-ring-save.
;; with no region they behave as ordinary prefix maps.

(defvar my/delete-map (make-sparse-keymap)
  "Prefix map for `C-d' delete operations.")

(defvar my/copy-map (make-sparse-keymap)
  "Prefix map for `C-y' copy operations.")

(keymap-set my/override-map "C-d"
            (my/region-aware-prefix my/delete-map #'kill-region))
(keymap-set my/override-map "C-y"
            (my/region-aware-prefix my/copy-map #'kill-ring-save))

(my/wk-add "C-d" "delete")
(my/bind-sub my/delete-map "C-d"
  '("p" my/delete-paragraph       "paragraph")
  '("d" my/delete-line            "line")
  '("w" my/delete-word            "word")
  '("s" my/delete-symbol          "symbol")
  '("0" my/delete-inside-parens   "inside ()")
  '("]" my/delete-inside-brackets "inside []")
  '("." my/delete-all             "all"))

(my/wk-add "C-y" "copy")
(my/bind-sub my/copy-map "C-y"
  '("p" my/copy-paragraph       "paragraph")
  '("y" my/copy-line            "line")
  '("w" my/copy-word            "word")
  '("s" my/copy-symbol          "symbol")
  '("0" my/copy-inside-parens   "inside ()")
  '("]" my/copy-inside-brackets "inside []")
  '("." my/copy-all             "all"))

(my/bind-prefix "C-;" "comment"
  '("p" my/toggle-comment-paragraph "paragraph")
  '(";" my/toggle-comment-line      "line")
  '("." my/toggle-comment-all       "all"))

(my/bind-prefix "C-q" "select"
  '("p" my/select-paragraph     "paragraph")
  '("q" my/select-line          "line")
  '("s" my/select-symbol        "symbol")
  '("0" my/select-inside-parens "inside ()")
  '("." mark-whole-buffer       "all"))

;; line-block counts (1-9): delete/copy/comment/select, below or above (<up> N)
(dotimes (i 9)
  (let ((n (1+ i)))
    (pcase-dolist (`(,key ,name) '(("" "") ("<up> " "up-")))
      (my/bind
        (list (format "C-; %s%d" key n)
              (intern (format "my/comment-lines-%s%d" name n))))
      (my/bind
        (list (format "C-q %s%d" key n)
              (intern (format "my/select-lines-%s%d" name n))))
      (my/bind-sub my/delete-map "C-d"
        (list (format "%s%d" key n)
              (intern (format "my/delete-lines-%s%d" name n))))
      (my/bind-sub my/copy-map "C-y"
        (list (format "%s%d" key n)
              (intern (format "my/copy-lines-%s%d" name n)))))))
(push '(("\\`C-[;qdy] \\(?:<up>\\|\\(?:<up> \\)?[1-9]\\)\\'" . nil) . t)
      which-key-replacement-alist)
(push "\\`C-[;qdy] <up>\\'" which-key-inhibit-regexps)

(my/bind-prefix "C-r" "replace"
  '("r" replace-string "replace string")
  '("q" query-replace  "query replace"))

(my/bind-prefix "C-." "cursors"
  '("m" mc/mark-all-in-region      "cursor region")
  '("l" mc/edit-lines              "cursor lines")
  '("." mc/mark-next-like-this     "cursor next")
  '("/" mc/mark-previous-like-this "cursor prev"))

(my/bind-prefix "C-s" "search"
  '("g" consult-ripgrep     "ripgrep")
  '("f" isearch-forward     "isearch")
  '("r" consult-recent-file "recent")
  '("i" consult-imenu       "imenu")
  '("s" consult-line        "line"))

(my/bind-prefix "C-w" "window"
  '("w" split-window-below         "new window ↓")
  '("v" split-window-right         "new window →")
  '("f" window-layout-flip-topdown "flip window ↑↓")
  '("d" delete-window              "close window"))

(my/bind-prefix "C-x" ""
  '("<right>" next-buffer         t)
  '("<left>"  previous-buffer     t)
  '("m"       rectangle-mark-mode "rectangle mark")
  '("e"       eval-last-sexp      "eval sexp"))

(my/bind-prefix "C-e" "emacs"
  '("e" save-buffer                   "save buffer")
  '("s" tramp-revert-buffer-with-sudo "sudo edit")
  '("t" visual-line-mode              "truncate")
  '("i" my/find-init-file             "init.el")
  '("r" restart-emacs                 "restart"))

(my/bind-prefix "C-h" "help"
  '("h" helpful-at-point "help at point")
  '("f" helpful-function "desc function")
  '("v" helpful-variable "desc variable")
  '("k" describe-key     "desc key")
  '("K" describe-keymap  "desc keymap")
  '("d" devdocs-lookup   "devdocs"))

;; ===============================================================
;;; MODE MAPS

(my/bind-local isearch-mode-map
  '("<down>" isearch-repeat-forward)
  '("<up>"   isearch-repeat-backward)
  '("M-w"    isearch-copy-selected-word))

(with-eval-after-load 'dired
  (my/bind-local dired-mode-map
    '("RET"      dired-snacks-open)
    '("TAB"      dired-snacks-subtree-toggle)
    '("M-<left>" dired-up-directory)
    '("M-."      dired-omit-mode)
    '("<f2>"     wdired-change-to-wdired-mode)
    '("M-f"      dired-create-empty-file)
    '("M-d"      dired-snacks-duplicate)
    '("M-s"      dired-snacks-split))
  (my/bind-local dired-mode-map
    '("M-w"            dired-snacks-clip)
    '("<remap> <yank>" dired-snacks-paste)
    '("M-m"            dired-snacks-paste-move)
    '("M-l"            dired-snacks-paste-symlink)
    '("M-q"            dired-snacks-paste-cancel)
    '("M-y"            dired-snacks-copy-file-uri)))

(with-eval-after-load 'completion-preview
  (my/bind-local completion-preview-active-mode-map
    '("M-n" completion-preview-next-candidate)))

(keymap-set prog-mode-map "C-l" (cons "lsp" (make-sparse-keymap)))
(my/bind-local prog-mode-map
  '("C-l n" eglot-rename     "rename symbol")
  '("C-l e" consult-flycheck "list errors"))

(with-eval-after-load 'elisp-mode
  (dolist (map (list emacs-lisp-mode-map lisp-interaction-mode-map))
    (dolist (key '("C-c C-b" "C-c C-e" "C-c C-f"))
      (keymap-unset map key t))))

(with-eval-after-load 'ruby-ts-mode
  (my/bind-local ruby-ts-mode-map
    '("C-l b" ruby-send-buffer "send buffer")
    '("C-l s" ruby-send-region "send region")
    '("C-l l" ruby-send-line   "send line")
    '("C-l r" inf-ruby         "open repl")))

(with-eval-after-load 'org
  (dolist (key '("M-<left>" "M-<right>"))
    (keymap-unset org-mode-map key t))
  (my/bind-local org-mode-map
    '("C-c t" org-hide-drawers-toggle "toggle drawers")))

(with-eval-after-load 'ghostel
  ;; `keymap-set' rejects a slash in the command name of a <remap> key.
  (define-key ghostel-semi-char-mode-map [remap my/backward-delete]
              #'my/ghostel-backward-delete))

(with-eval-after-load 'magit-status
  (my/bind-local magit-status-mode-map
    '("q" my/magit-kill-buffers)))

(with-eval-after-load 'transient
  (my/bind-local transient-map
    '("<escape>" transient-quit-one)))

(with-eval-after-load 'winner
  (dolist (key '("C-c <left>" "C-c <right>"))
    (keymap-unset winner-mode-map key t)))

(provide 'my-keybindings)
;;; my-keybindings.el ends here
