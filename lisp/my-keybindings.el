;;; my-keybindings.el --- Keybindings  -*- lexical-binding: t; -*-

;; Author: Lucas
;; Keywords: convenience

;;; Commentary:

;; Personal keybindings: a global override keymap, region-aware
;; prefixes with which-key labels, and mode-local bindings.

;;; Code:

(defvar winner-mode-map)
(defvar ruby-ts-mode-map)
(defvar dired-mode-map)
(defvar org-mode-map)

;; ===============================================================
;;; SETUP

(require 'which-key)
(defalias 'my/wk-add #'which-key-add-key-based-replacements)

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
  (apply #'my/bind-sub my/override-map nil bindings))

(defun my/bind-local (keymap &rest bindings)
  "Bind each (KEY COMMAND [DESC]) in BINDINGS in KEYMAP."
  (dolist (binding bindings)
    (seq-let (key command desc) binding
      (keymap-set keymap key (if desc (cons desc command) command)))))

(defun my/bind-sub (map prefix &rest bindings)
  "Bind each (KEY COMMAND [DESC]) in BINDINGS in MAP.
Each which-key label is registered under PREFIX + KEY.  DESC t hides it."
  (dolist (binding bindings)
    (seq-let (key command desc) binding
      (keymap-set map key command)
      (let ((full (if prefix (concat prefix " " key) key)))
        (cond ((eq desc t) (my/wk-hide full))
              (desc         (my/wk-add full desc)))))))

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

;; ===============================================================
;;; UNBINDINGS

(keymap-unset key-translation-map "C-x 8" t)

(dolist (key '("C-<wheel-down>" "C-<wheel-up>" "C-c ^" "C-z" "C-h" "C-x" "M-g"))
  (keymap-global-unset key t))

(with-eval-after-load 'elisp-mode
  (dolist (map (list emacs-lisp-mode-map lisp-interaction-mode-map))
    (dolist (key '("C-c C-b" "C-c C-e" "C-c C-f"))
      (keymap-unset map key t))))

(with-eval-after-load 'winner
  (dolist (key '("C-c <left>" "C-c <right>"))
    (keymap-unset winner-mode-map key t)))

(with-eval-after-load 'org
  (dolist (key '("M-<left>" "M-<right>"))
    (keymap-unset org-mode-map key t)))

;; ===============================================================
;;; GLOBAL

(my/bind
  '("<f1>"          scratch-buffer)
  '("<f3>"          diff-hl-show-hunk)
  '("<f4>"          my/rotate-theme)
  '("C-<backspace>" my/backward-delete)
  '("C-<tab>"       other-window)
  '("C-b"           consult-buffer)
  '("C-0"           my/wrap-parens)
  '("C-]"           my/wrap-brackets)
  '("C-k"           my/kill-buffer-and-window)
  '("C-="           text-scale-increase)
  '("C--"           text-scale-decrease)
  '("C-,"           popper-toggle)
  '("C-<"           popper-cycle)
  '("C-v"           yank)
  '("C-z"           dired-snacks-zoxide)
  '("C-f"           dired-snacks-find)
  '("C-o"           my/open-line-below)
  '("C-t"           ghostel)
  '("M-<down>"      my/move-text-down)
  '("M-<up>"        my/move-text-up)
  '("M-k"           kill-line)
  '("M-u"           upcase-dwim)
  '("M-p"           duplicate-dwim)
  '("M-c"           capitalize-dwim))

;; in the global map rather than `my/override-map', so modes can rebind them
(my/bind-local global-map
  '("<f2>" magit-status)
  '("M-m"  mark-paragraph)
  '("M-l"  downcase-dwim))

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

(my/wk-add "C-d" "delete")
(my/bind-sub my/delete-map "C-d"
  '("p" my/delete-paragraph   "delete paragraph")
  '("0" my/delete-inside-parens   "delete inside ()")
  '("]" my/delete-inside-brackets "delete inside []")
  '("s" my/delete-symbol      "delete symbol")
  '("d" my/delete-line        "delete line")
  '("w" my/delete-word        "delete word")
  '("." my/delete-all         "delete all"))

(my/wk-add "C-y" "copy")
(my/bind-sub my/copy-map "C-y"
  '("p" my/copy-paragraph       "copy paragraph")
  '("s" my/copy-symbol          "copy symbol")
  '("w" my/copy-word            "copy word")
  '("y" my/copy-line            "copy line")
  '("0" my/copy-inside-parens   "inside ()")
  '("]" my/copy-inside-brackets "inside []")
  '("." my/copy-all             "copy all"))

;; ===============================================================
;;; PREFIX GROUPS

(my/wk-add "C-;" "comment")
(my/bind
  '("C-; p" my/toggle-comment-paragraph "paragraph")
  '("C-; ;" my/toggle-comment-line      "line")
  '("C-; ." my/toggle-comment-all       "all"))

;; line-block counts (1-9): delete/copy/comment/select, below or above (<up> N)
(dotimes (i 9)
  (let ((n (1+ i)))
    (pcase-dolist (`(,key ,name) '(("" "") ("<up> " "up-")))
      (my/bind (list (format "C-; %s%d" key n) (intern (format "my/comment-lines-%s%d" name n))))
      (my/bind (list (format "C-q %s%d" key n) (intern (format "my/select-lines-%s%d" name n))))
      (my/bind-sub my/delete-map "C-d"
                   (list (format "%s%d" key n) (intern (format "my/delete-lines-%s%d" name n))))
      (my/bind-sub my/copy-map "C-y"
                   (list (format "%s%d" key n) (intern (format "my/copy-lines-%s%d" name n)))))))
(push '(("\\`C-[;qdy] \\(?:<up>\\|\\(?:<up> \\)?[1-9]\\)\\'" . nil) . t)
      which-key-replacement-alist)
(push "\\`C-[;qdy] <up>\\'" which-key-inhibit-regexps)

(my/wk-add "C-r" "replace")
(my/bind
  '("C-r r" replace-string "replace string")
  '("C-r q" query-replace  "query replace"))

(my/wk-add "C-." "cursors")
(my/bind
  '("C-. m" mc/mark-all-in-region      "cursor region")
  '("C-. l" mc/edit-lines              "cursor lines")
  '("C-. ." mc/mark-next-like-this     "cursor next")
  '("C-. /" mc/mark-previous-like-this "cursor prev"))

(my/wk-add "C-s" "search")
(my/bind
  '("C-s g" consult-ripgrep     "ripgrep")
  '("C-s f" isearch-forward     "isearch")
  '("C-s r" consult-recent-file "recent")
  '("C-s i" consult-imenu       "imenu")
  '("C-s s" consult-line        "line"))

(my/wk-add "C-e" "emacs")
(my/bind
  '("C-e s" tramp-revert-buffer-with-sudo "sudo edit")
  '("C-e e" save-buffer       "save buffer")
  '("C-e t" visual-line-mode  "truncate")
  '("C-e i" my/find-init-file "init.el")
  '("C-e r" restart-emacs     "restart"))

(my/wk-add "C-h" "help")
(my/bind
  '("C-h h" helpful-at-point "help at point")
  '("C-h f" helpful-function "desc function")
  '("C-h v" helpful-variable "desc variable")
  '("C-h k" describe-key     "desc key")
  '("C-h K" describe-keymap  "desc keymap")
  '("C-h d" devdocs-lookup   "devdocs"))

(my/wk-add "C-q" "select")
(my/bind
  '("C-q p" my/select-paragraph "select paragraph")
  '("C-q 0" my/select-inside-parens "select in parens")
  '("C-q s" my/select-symbol    "select symbol")
  '("C-q q" my/select-line      "select line")
  '("C-q ." mark-whole-buffer   "select all"))

(my/wk-add "C-w" "window")
(my/bind
  '("C-w f" window-layout-flip-topdown "flip window ↑↓")
  '("C-w w" split-window-below "new window ↓")
  '("C-w v" split-window-right "new window →")
  '("C-w d" delete-window      "close window"))

(my/wk-add "C-x" "")
(my/bind
  '("C-x <right>" next-buffer     t)
  '("C-x <left>"  previous-buffer t)
  '("C-x m"       rectangle-mark-mode "rectangle mark")
  '("C-x e"       eval-last-sexp      "eval sexp"))

;; ===============================================================
;;; MODE-LOCAL

(keymap-set prog-mode-map "C-l" (cons "lsp" (make-sparse-keymap)))
(my/bind-local prog-mode-map
  '("C-l n" eglot-rename     "rename symbol")
  '("C-l e" consult-flycheck "list errors"))

(with-eval-after-load 'ruby-ts-mode
  (my/bind-local ruby-ts-mode-map
    '("C-l b" ruby-send-buffer "send buffer")
    '("C-l s" ruby-send-region "send region")
    '("C-l l" ruby-send-line   "send line")
    '("C-l r" inf-ruby         "open repl")))

(with-eval-after-load 'dired
  (my/bind-local dired-mode-map
    '("<f2>"     wdired-change-to-wdired-mode)
    '("M-f"      dired-create-empty-file)
    '("M-<left>" dired-up-directory)
    '("M-."      dired-omit-mode)
    '("<remap> <yank>" dired-snacks-paste)
    '("M-m" dired-snacks-paste-move)
    '("M-w" dired-snacks-clip)
    '("M-l" dired-snacks-paste-symlink)
    '("M-q" dired-snacks-paste-cancel)
    '("TAB" dired-snacks-subtree-toggle)
    '("M-y" dired-snacks-copy-file-uri)
    '("M-d" dired-snacks-duplicate)
    '("M-s" dired-snacks-split)
    '("RET" dired-snacks-open)))

(with-eval-after-load 'org
  (my/bind-local org-mode-map
    '("C-c t" org-hide-drawers-toggle "toggle drawers")))

(provide 'my-keybindings)
;;; my-keybindings.el ends here
