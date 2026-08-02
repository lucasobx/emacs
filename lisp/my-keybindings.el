;;; my-keybindings.el --- keybindings  -*- lexical-binding: t; -*-
;;; Commentary:
;;; Code:

;; ===============================================================
;;; SETUP

(require 'which-key)
(defalias 'wk-add #'which-key-add-key-based-replacements)
(defalias 'wk-add-map #'which-key-add-keymap-based-replacements)

(defvar my/override-map (make-sparse-keymap))
(define-minor-mode my/override-mode
  "Global minor mode holding my override keybindings."
  :global t :group 'convenience :keymap my/override-map)
(add-to-list 'emulation-mode-map-alists `((my/override-mode . ,my/override-map)))
(my/override-mode 1)

;; ===============================================================
;;; HELPERS
;;
;; a binding is (KEY COMMAND [DESC]). DESC labels it in which-key. DESC t hides it.
;; each binder takes a batch of bindings:
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
  (dolist (binding bindings)
    (seq-let (key command desc) binding
      (keymap-set my/override-map key command)
      (cond ((eq desc t) (my/wk-hide key))
            (desc         (wk-add key desc))))))

(defun my/bind-local (keymap &rest bindings)
  "Bind each (KEY COMMAND [DESC]) in BINDINGS in KEYMAP."
  (dolist (binding bindings)
    (seq-let (key command desc) binding
      (keymap-set keymap key command)
      (when desc (wk-add-map keymap key desc)))))

(defun my/bind-sub (map prefix &rest bindings)
  "Bind each (KEY COMMAND [DESC]) in BINDINGS in prefix MAP.
Each which-key label is registered under PREFIX + KEY. DESC t hides it."
  (dolist (binding bindings)
    (seq-let (key command desc) binding
      (keymap-set map key command)
      (let ((full (concat prefix " " key)))
        (cond ((eq desc t) (my/wk-hide full))
              (desc         (wk-add full desc)))))))

;; ===============================================================
;;; COMMANDS

(defun my/find-init-file ()
  "Open the user init file."
  (interactive)
  (find-file (locate-user-emacs-file "init.el")))

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

;; ===============================================================
;;; UNBINDINGS

(keymap-unset key-translation-map "C-x 8" t)

(dolist (key '("C-<wheel-down>" "C-<wheel-up>" "C-c ^" "C-z" "C-h" "C-x"))
  (keymap-global-unset key t))

(with-eval-after-load 'elisp-mode
  (dolist (map (list emacs-lisp-mode-map lisp-interaction-mode-map))
    (dolist (key '("C-c C-b" "C-c C-e" "C-c C-f"))
      (keymap-unset map key t))))

(with-eval-after-load 'winner
  (dolist (key '("C-c <left>" "C-c <right>"))
    (keymap-unset winner-mode-map key t)))

;; ===============================================================
;;; GLOBAL

(my/bind
  '("<f1>"          scratch-buffer)
  '("<f5>"          my/rotate-theme)
  '("C-<backspace>" my/backward-delete)
  '("C-<tab>"       other-window)
  '("C-0"           my/wrap-parens)
  '("C-]"           my/wrap-brackets)
  '("C-k"           kill-buffer-and-window)
  '("C-="           text-scale-increase)
  '("C--"           text-scale-decrease)
  '("C-,"           popper-toggle)
  '("C-<"           popper-cycle)
  '("C-p"           yank)
  '("C-z"           dired-snacks-zoxide)
  '("C-f"           dired-snacks-find-name)
  '("C-o"           my/open-line-below)
  '("M-<down>"      my/move-text-down)
  '("M-<up>"        my/move-text-up)
  '("M-k"           kill-line)
  '("M-u"           upcase-dwim)
  '("M-m"           mark-paragraph)
  '("M-l"           downcase-dwim)
  '("M-p"           duplicate-dwim)
  '("M-c"           capitalize-dwim))

;; ===============================================================
;;; REGION-AWARE PREFIXES (C-d / C-y)
;;
;; with an active region, bare C-d/C-y act as kill-region/kill-ring-save.
;; with no region they behave as ordinary prefix maps.

(defvar my/delete-map (make-sparse-keymap)
  "Prefix map for `C-d' delete operations.")

(defvar my/copy-map (make-sparse-keymap)
  "Prefix map for `C-y' copy operations.")

(defun my/region-aware-prefix (map command)
  "Return a binding giving COMMAND on an active region, else prefix MAP."
  `(menu-item "" ,map :filter ,(lambda (real) (if (use-region-p) command real))))

(keymap-set my/override-map "C-d" (my/region-aware-prefix my/delete-map #'kill-region))
(keymap-set my/override-map "C-y" (my/region-aware-prefix my/copy-map #'kill-ring-save))

(wk-add "C-d" "delete")
(my/bind-sub my/delete-map "C-d"
  '("p" my/delete-paragraph   "delete paragraph")
  '("0" my/delete-in-parens   "delete inside ()")
  '("]" my/delete-in-brackets "delete inside []")
  '("s" my/delete-symbol      "delete symbol")
  '("d" my/delete-line        "delete line")
  '("w" my/delete-word        "delete word")
  '("a" my/delete-buffer      "delete buffer"))

(wk-add "C-y" "copy")
(my/bind-sub my/copy-map "C-y"
  '("p" my/copy-paragraph       "copy paragraph")
  '("s" my/copy-symbol          "copy symbol")
  '("w" my/copy-word            "copy word")
  '("y" my/copy-line            "copy line")
  '("0" my/copy-inside-parens   "inside ()")
  '("]" my/copy-inside-brackets "inside []")
  '("a" my/copy-buffer          "copy buffer"))

;; ===============================================================
;;; PREFIX GROUPS

(wk-add "C-;" "comment")
(my/bind
  '("C-; p" my/toggle-comment-paragraph "paragraph")
  '("C-; ;" my/toggle-comment-line      "line")
  '("C-; a" my/toggle-comment-buffer    "buffer"))

;; line-block counts (1-9): delete/copy/comment/select
(dotimes (i 9)
  (let ((n (1+ i)))
    (my/bind (list (format "C-; %d" n) (intern (format "my/comment-lines-%d" n)) t))
    (my/bind (list (format "C-q %d" n) (intern (format "my/select-lines-%d" n)) t))
    (my/bind-sub my/delete-map "C-d"
                 (list (number-to-string n) (intern (format "my/delete-lines-%d" n)) t))
    (my/bind-sub my/copy-map "C-y"
                 (list (number-to-string n) (intern (format "my/copy-lines-%d" n)) t))))

(wk-add "C-r" "replace")
(my/bind
  '("C-r r" replace-string "replace string")
  '("C-r q" query-replace  "query replace"))

(wk-add "C-." "cursors")
(my/bind
  '("C-. m" mc/mark-all-in-region      "cursor region")
  '("C-. l" mc/edit-lines              "cursor lines")
  '("C-. ." mc/mark-next-like-this     "cursor next")
  '("C-. /" mc/mark-previous-like-this "cursor prev"))

(wk-add "C-s" "search")
(my/bind
  '("C-s f" find-file           "find-file")
  '("C-s h" consult-outline     "heading")
  '("C-s d" consult-fd          "fd-find")
  '("C-s g" consult-ripgrep     "ripgrep")
  '("C-s r" consult-recent-file "recent")
  '("C-s i" imenu               "imenu")
  '("C-s n" nerd-icons-insert   "icons")
  '("C-s s" consult-line        "line"))

(wk-add "C-e" "emacs")
(my/bind
  '("C-e s" tramp-revert-buffer-with-sudo "sudo edit")
  '("C-e e" save-buffer       "save buffer")
  '("C-e t" visual-line-mode  "truncate")
  '("C-e i" my/find-init-file "init.el")
  '("C-e r" restart-emacs     "restart"))

(wk-add "C-h" "help")
(my/bind
  '("C-h h" helpful-at-point "help at point")
  '("C-h f" helpful-function "desc function")
  '("C-h v" helpful-variable "desc variable")
  '("C-h k" describe-keymap  "desc keymap")
  '("C-h d" devdocs-lookup   "devdocs"))

(wk-add "C-q" "select")
(my/bind
  '("C-q p" my/select-paragraph "select paragraph")
  '("C-q 0" my/select-in-parens "select in parens")
  '("C-q s" my/select-symbol    "select symbol")
  '("C-q q" my/select-line      "select line")
  '("C-q a" mark-whole-buffer   "select all"))

(wk-add "C-t" "tools")
(my/bind
  '("C-t t" eshell       "eshell")
  '("C-t m" magit-status "magit"))

(wk-add "C-b" "buffer")
(my/bind
  '("C-b b" consult-buffer    "switch to buffer")
  '("C-b s" my/system-buffers "system buffers")
  '("C-b k" kill-buffer       "kill buffer"))

(wk-add "C-w" "window")
(my/bind
  '("C-w f" window-layout-flip-topdown "flip window ↑↓")
  '("C-w w" split-window-below "new window ↓")
  '("C-w v" split-window-right "new window →")
  '("C-w d" delete-window      "close window"))

(wk-add "C-x" "")
(my/bind
  '("C-x <right>" next-buffer     t)
  '("C-x <left>"  previous-buffer t)
  '("C-x m"       rectangle-mark-mode "rectangle mark")
  '("C-x e"       eval-last-sexp      "eval sexp"))

;; ===============================================================
;;; MODE-LOCAL

(wk-add-map prog-mode-map "C-l" "lsp")
(my/bind-local prog-mode-map
  '("C-l n" eglot-rename     "rename symbol")
  '("C-l e" consult-flycheck "list errors"))

(with-eval-after-load 'inf-ruby
  (my/bind-local ruby-ts-mode-map
    '("C-l b" ruby-send-buffer "send buffer")
    '("C-l s" ruby-send-region "send region")
    '("C-l l" ruby-send-line   "send line")
    '("C-l r" inf-ruby         "open repl")))

(with-eval-after-load 'dired
  (my/bind-local dired-mode-map
    '("RET"      dired-snacks-find-file)
    '("<f2>"     wdired-change-to-wdired-mode)
    '("TAB"      dired-snacks-subtree-toggle)
    '("M-y"      dired-snacks-copy-file-uri)
    '("M-f"      dired-create-empty-file)
    '("M-d"      dired-create-directory)
    '("M-s"      dired-snacks-split)
    '("M-<left>" dired-up-directory)
    '("M-."      dired-omit-mode)))

(with-eval-after-load 'org
  (wk-add-map org-mode-map "C-o" "org")
  (my/bind-local org-mode-map
    '("C-o t" org-hide-drawers-toggle "toggle drawers")))

(provide 'my-keybindings)
;;; my-keybindings.el ends here
