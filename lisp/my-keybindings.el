;;; my-keybindings.el --- keybindings  -*- lexical-binding: t; -*-
;;; Commentary:
;;; Code:

(require 'which-key)
(defalias 'wk-add #'which-key-add-key-based-replacements)
(defalias 'wk-add-map #'which-key-add-keymap-based-replacements)

(defvar my/override-map (make-sparse-keymap))
(define-minor-mode my/override-mode
  "Global minor mode holding my override keybindings."
  :global t :group 'convenience :keymap my/override-map)
(add-to-list 'emulation-mode-map-alists `((my/override-mode . ,my/override-map)))
(my/override-mode 1)

(defun my/wk-hide (&rest keys)
  "Hide each of KEYS from the which-key popup."
  (dolist (key keys)
    (let ((kd (key-description (kbd key))))
      (push (cons (cons (concat "\\`" (regexp-quote kd) "\\'") nil) t)
            which-key-replacement-alist))))

(defun my/bind (key command &optional desc)
  "Bind KEY to COMMAND with override precedence.
DESC labels it in which-key. DESC t hides KEY from which-key."
  (keymap-set my/override-map key command)
  (cond ((eq desc t) (my/wk-hide key))
        (desc          (wk-add key desc))))

(defun my/bind-local (keymap key command &optional desc)
  "Bind KEY to COMMAND in KEYMAP, optionally labeling it DESC in which-key."
  (keymap-set keymap key command)
  (when desc (wk-add-map keymap key desc)))

;; unbind
(dolist (key '("C-<wheel-down>" "C-<wheel-up>" "C-x C-z" "C-c ^" "C-z" "C-h" "C-x"))
  (keymap-global-unset key t))

(with-eval-after-load 'elisp-mode
  (dolist (map (list emacs-lisp-mode-map lisp-interaction-mode-map))
    (dolist (key '("C-c C-b" "C-c C-e" "C-c C-f"))
      (keymap-unset map key t))))

(with-eval-after-load 'winner
  (dolist (key '("C-c <left>" "C-c <right>"))
    (keymap-unset winner-mode-map key t)))

;; global
(my/bind "<f1>"          #'scratch-buffer)
(my/bind "<f2>"          #'my/rotate-theme)
(my/bind "C-<backspace>" #'my/backward-delete)
(my/bind "C-<tab>"       #'other-window)
(my/bind "C-0"           #'my/wrap-parens)
(my/bind "C-]"           #'my/wrap-brackets)
(my/bind "C-k"           #'kill-buffer-and-window)
(my/bind "C-="           #'text-scale-increase)
(my/bind "C--"           #'text-scale-decrease)
(my/bind "C-,"           #'popper-toggle)
(my/bind "C-<"           #'popper-cycle)
(my/bind "C-p"           #'yank)
(my/bind "C-z"           #'my/zoxide-dired)
(my/bind "C-f"           #'my/dired-find-name)
(my/bind "C-o"           #'my/open-line-below)
(my/bind "M-<down>"      #'my/move-text-down)
(my/bind "M-<up>"        #'my/move-text-up)
(my/bind "M-k"           #'kill-line)
(my/bind "M-u"           #'upcase-dwim)
(my/bind "M-m"           #'mark-paragraph)
(my/bind "M-l"           #'downcase-dwim)
(my/bind "M-p"           #'duplicate-dwim)
(my/bind "M-c"           #'capitalize-dwim)

(wk-add  "C-y" "copy")
(my/bind "C-y p" #'my/copy-paragraph       "copy paragraph")
(my/bind "C-y s" #'my/copy-symbol          "copy symbol")
(my/bind "C-y w" #'my/copy-word            "copy word")
(my/bind "C-y y" #'my/copy-line            "copy line")
(my/bind "C-y 0" #'my/copy-inside-parens   "inside ()")
(my/bind "C-y ]" #'my/copy-inside-brackets "inside []")

(wk-add  "C-d" "delete")
(my/bind "C-d p" #'my/delete-paragraph   "delete paragraph")
(my/bind "C-d 0" #'my/delete-in-parens   "delete inside ()")
(my/bind "C-d ]" #'my/delete-in-brackets "delete inside []")
(my/bind "C-d s" #'my/delete-symbol      "delete symbol")
(my/bind "C-d d" #'my/delete-line        "delete line")
(my/bind "C-d w" #'my/delete-word        "delete word")

(wk-add  "C-;" "comment")
(my/bind "C-; p" #'my/toggle-comment-paragraph "paragraph")
(my/bind "C-; ;" #'my/toggle-comment-line      "line")

(wk-add  "C-r" "replace")
(my/bind "C-r r" #'replace-string "replace string")
(my/bind "C-r q" #'query-replace  "query replace")

(wk-add  "C-." "cursors")
(my/bind "C-. m" #'mc/mark-all-in-region      "cursor region")
(my/bind "C-. l" #'mc/edit-lines              "cursor lines")
(my/bind "C-. ." #'mc/mark-next-like-this     "cursor next")
(my/bind "C-. /" #'mc/mark-previous-like-this "cursor prev")

(wk-add  "C-s" "search")
(my/bind "C-s f" #'find-file           "find-file")
(my/bind "C-s h" #'consult-outline     "heading")
(my/bind "C-s d" #'consult-fd          "fd-find")
(my/bind "C-s g" #'consult-ripgrep     "ripgrep")
(my/bind "C-s r" #'consult-recent-file "recent")
(my/bind "C-s i" #'imenu               "imenu")
(my/bind "C-s n" #'nerd-icons-insert   "icons")
(my/bind "C-s s" #'consult-line        "line")

(wk-add  "C-e" "emacs")
(my/bind "C-e i" (lambda ()
                   (interactive) (find-file (locate-user-emacs-file "init.el"))) "init.el")
(my/bind "C-e s" #'tramp-revert-buffer-with-sudo "sudo edit")
(my/bind "C-e e" #'save-buffer      "save buffer")
(my/bind "C-e t" #'visual-line-mode "truncate")
(my/bind "C-e r" #'restart-emacs    "restart")

(wk-add  "C-h" "help")
(my/bind "C-h f" #'helpful-function   "describe function")
(my/bind "C-h v" #'helpful-variable   "describe variable")
(my/bind "C-h h" #'helpful-at-point   "help at point")
(my/bind "C-h k" #'devil-describe-key "describe key")
(my/bind "C-h d" #'devdocs-lookup     "devdocs")

(wk-add  "C-q" "select")
(my/bind "C-q p" #'my/select-paragraph "select paragraph")
(my/bind "C-q 0" #'my/select-in-parens "select in parens")
(my/bind "C-q s" #'my/select-symbol    "select symbol")
(my/bind "C-q q" #'my/select-line      "select line")
(my/bind "C-q a" #'mark-whole-buffer   "select all")

;; line-block counts (1-9): delete / copy / comment / select
(dotimes (i 9)
  (let ((n (1+ i)))
    (my/bind (format "C-; %d" n) (intern (format "my/comment-lines-%d" n)) t)
    (my/bind (format "C-q %d" n) (intern (format "my/select-lines-%d" n))  t)
    (my/bind (format "C-d %d" n) (intern (format "my/delete-lines-%d" n))  t)
    (my/bind (format "C-y %d" n) (intern (format "my/copy-lines-%d" n))    t)))

(wk-add  "C-t" "tools")
(my/bind "C-t t" #'eshell       "eshell")
(my/bind "C-t m" #'magit-status "magit")

(wk-add  "C-b" "buffer")
(my/bind "C-b b" #'consult-buffer "switch to buffer")
(my/bind "C-b k" #'kill-buffer    "kill buffer")

(wk-add  "C-x" "")
(my/bind "C-x <right>" #'next-buffer     t)
(my/bind "C-x <left>"  #'previous-buffer t)
(my/bind "C-x m"       #'rectangle-mark-mode "rectangle mark")
(my/bind "C-x b"       #'switch-to-buffer    "switch to buffer")
(my/bind "C-x 1"       #'split-window-below  "split window ↓")
(my/bind "C-x 2"       #'split-window-right  "split window →")
(my/bind "C-x 0"       #'delete-window       "delete window")
(my/bind "C-x e"       #'eval-last-sexp      "eval sexp")

(wk-add-map
  prog-mode-map "C-l" "lsp")
(my/bind-local prog-mode-map "C-l d" #'consult-flymake "jump to diagnostic")
(my/bind-local prog-mode-map "C-l n" #'eglot-rename    "rename symbol")

(with-eval-after-load 'inf-ruby
  (my/bind-local ruby-ts-mode-map "C-l b" #'ruby-send-buffer "send buffer")
  (my/bind-local ruby-ts-mode-map "C-l s" #'ruby-send-region "send region")
  (my/bind-local ruby-ts-mode-map "C-l l" #'ruby-send-line   "send line")
  (my/bind-local ruby-ts-mode-map "C-l r" #'inf-ruby         "open repl"))

(with-eval-after-load 'dired
  (my/bind-local dired-mode-map "RET"      #'my/dired-find-file)
  (my/bind-local dired-mode-map "<f2>"     #'wdired-change-to-wdired-mode)
  (my/bind-local dired-mode-map "M-f"      #'dired-create-empty-file)
  (my/bind-local dired-mode-map "M-d"      #'dired-create-directory)
  (my/bind-local dired-mode-map "M-y"      #'my/dired-copy-file-uri)
  (my/bind-local dired-mode-map "M-<left>" #'dired-up-directory)
  (my/bind-local dired-mode-map "M-."      #'dired-omit-mode))

(with-eval-after-load 'org
  (wk-add-map
    org-mode-map "C-o" "org")
  (my/bind-local org-mode-map "C-o t" #'org-hide-drawers-toggle "toggle drawers"))

(provide 'my-keybindings)
;;; my-keybindings.el ends here
