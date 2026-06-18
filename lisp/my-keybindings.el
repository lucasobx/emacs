;;; my-keybindings.el --- keybindings  -*- lexical-binding: t; -*-
;;; Commentary:
;;; Code:

(require 'which-key)

(defvar my/override-map (make-sparse-keymap))
(define-minor-mode my/override-mode
  "Global minor mode holding my override keybindings."
  :global t :group 'convenience :keymap my/override-map)
(add-to-list 'emulation-mode-map-alists `((my/override-mode . ,my/override-map)))
(my/override-mode 1)

(defun my/bind (key command &optional desc)
  "Bind KEY to COMMAND with override precedence, optionally labeling it DESC."
  (keymap-set my/override-map key command)
  (when desc (which-key-add-key-based-replacements key desc)))

(defun my/bind-local (keymap key command &optional desc)
  "Bind KEY to COMMAND in KEYMAP, optionally labeling it DESC in which-key."
  (keymap-set keymap key command)
  (when desc (which-key-add-keymap-based-replacements keymap key desc)))

;; unbind
(dolist (key '("C-<wheel-down>" "C-<wheel-up>" "C-x C-z" "C-c ^" "C-z" "C-h"))
  (keymap-global-unset key t))
(with-eval-after-load 'elisp-mode
  (dolist (key '("C-c C-b" "C-c C-e" "C-c C-f"))
    (keymap-unset emacs-lisp-mode-map key t)))
(with-eval-after-load 'winner
  (dolist (key '("C-c <left>" "C-c <right>"))
    (keymap-unset winner-mode-map key t)))

;; global
(my/bind "<f1>"          #'scratch-buffer)
(my/bind "<f5>"          #'my/select-theme)
(my/bind "<f6>"          #'my/rotate-theme)
(my/bind "C-<backspace>" #'my/backward-delete)
(my/bind "C-<tab>"       #'other-window)
(my/bind "C-k"           #'kill-buffer-and-window)
(my/bind "C-="           #'er/expand-region)
(my/bind "C-_"           #'text-scale-decrease)
(my/bind "C-+"           #'text-scale-increase)
(my/bind "C-b"           #'consult-buffer)
(my/bind "C-,"           #'popper-toggle)
(my/bind "C-<"           #'popper-cycle)
(my/bind "C-p"           #'yank)
(my/bind "C-z"           #'my/zoxide-dired)
(my/bind "M-o"           #'my/open-line-below)
(my/bind "M-<down>"      #'move-text-down)
(my/bind "M-<up>"        #'move-text-up)
(my/bind "M-j"           #'avy-goto-char-2)
(my/bind "M-k"           #'kill-line)
(my/bind "M-u"           #'upcase-dwim)
(my/bind "M-m"           #'mark-paragraph)
(my/bind "M-l"           #'downcase-dwim)
(my/bind "M-p"           #'duplicate-dwim)
(my/bind "M-c"           #'capitalize-dwim)

(which-key-add-key-based-replacements "C-y" "copy")
(my/bind "C-y w" #'my/copy-word            "copy word")
(my/bind "C-y s" #'my/copy-symbol          "copy symbol")
(my/bind "C-y y" #'my/copy-line            "copy line")
(my/bind "C-y p" #'my/copy-paragraph       "copy paragraph")
(my/bind "C-y (" #'my/copy-inside-parens   "inside ()")
(my/bind "C-y [" #'my/copy-inside-brackets "inside []")
(my/bind "C-y {" #'my/copy-inside-braces   "inside {}")

(which-key-add-key-based-replacements "C-d" "delete")
(my/bind "C-d w" #'my/delete-word        "delete word")
(my/bind "C-d s" #'my/delete-symbol      "delete symbol")
(my/bind "C-d d" #'my/delete-line        "delete line")
(my/bind "C-d p" #'my/delete-paragraph   "delete paragraph")
(my/bind "C-d (" #'my/delete-in-parens   "delete inside ()")
(my/bind "C-d [" #'my/delete-in-brackets "delete inside []")
(my/bind "C-d {" #'my/delete-in-braces   "delete inside {}")

(which-key-add-key-based-replacements "C-;" "comment")
(my/bind "C-; ;" #'my/toggle-comment-line      "line")
(my/bind "C-; p" #'my/toggle-comment-paragraph "paragraph")

(which-key-add-key-based-replacements "C-r" "replace")
(my/bind "C-r r" #'replace-string "replace string")
(my/bind "C-r q" #'query-replace  "query replace")

(which-key-add-key-based-replacements "C-." "cursors")
(my/bind "C-. ." #'mc/mark-next-like-this     "cursor next")
(my/bind "C-. /" #'mc/mark-previous-like-this "cursor prev")
(my/bind "C-. m" #'mc/mark-all-in-region      "cursor region")
(my/bind "C-. l" #'mc/edit-lines              "cursor lines")

(which-key-add-key-based-replacements "C-s" "search")
(my/bind "C-s r" #'consult-recent-file "recent files")
(my/bind "C-s b" #'consult-bookmark    "bookmarks")
(my/bind "C-s g" #'consult-ripgrep     "ripgrep")
(my/bind "C-s t" #'consult-outline     "heading")
(my/bind "C-s i" #'consult-imenu       "imenu")
(my/bind "C-s s" #'consult-line        "line")

(which-key-add-key-based-replacements "C-f" "file")
(my/bind "C-f r" #'rename-visited-file "rename file")
(my/bind "C-f f" #'find-file           "find file")
(my/bind "C-f d" #'consult-fd          "fd-find")
(my/bind "C-f s" #'save-buffer         "save")

(which-key-add-key-based-replacements "C-h" "help")
(my/bind "C-h h" #'devdocs-lookup   "devdocs")
(my/bind "C-h c" #'helpful-callable "describe callable")
(my/bind "C-h v" #'helpful-variable "describe variable")
(my/bind "C-h K" #'describe-keymap  "describe keymap")
(my/bind "C-h m" #'describe-mode    "describe mode")
(my/bind "C-h k" #'helpful-key      "describe key")

(which-key-add-key-based-replacements "C-e" "emacs")
(my/bind "C-e i" (lambda () (interactive)
                   (find-file (locate-user-emacs-file "init.el")))
         "open init.el")
(my/bind "C-e s" #'sudo-edit        "edit with sudo")
(my/bind "C-e v" #'visual-line-mode "truncate lines")
(my/bind "C-e r" #'restart-emacs    "restart emacs")

(which-key-add-key-based-replacements "C-q" "mark")
(my/bind "C-q q" #'org-remark-mark   "highlight region")
(my/bind "C-q d" #'org-remark-delete "highlight delete")
(my/bind "C-q c" #'org-remark-change "highlight change")
(my/bind "C-q o" #'org-remark-open   "open notes")

(which-key-add-key-based-replacements "C-t" "tools")
(my/bind "C-t t" #'eshell       "terminal")
(my/bind "C-t i" #'ibuffer      "ibuffer")
(my/bind "C-t m" #'magit-status "magit")

(which-key-add-key-based-replacements "C-w" "windows")
(my/bind "C-w w" #'split-window-vertically    "vertical split")
(my/bind "C-w f" #'window-layout-flip-topdown "vertical flip")
(my/bind "C-w d" #'delete-window              "delete window")

(which-key-add-keymap-based-replacements prog-mode-map "C-l" "lsp")
(my/bind-local prog-mode-map "C-l d" #'consult-flymake "jump to diagnostic")
(my/bind-local prog-mode-map "C-l n" #'eglot-rename    "rename symbol")

;; ruby (C-l)
(with-eval-after-load 'inf-ruby
  (my/bind-local ruby-ts-mode-map "C-l b" #'ruby-send-buffer "send buffer")
  (my/bind-local ruby-ts-mode-map "C-l s" #'ruby-send-region "send region")
  (my/bind-local ruby-ts-mode-map "C-l l" #'ruby-send-line   "send line")
  (my/bind-local ruby-ts-mode-map "C-l r" #'inf-ruby         "open repl"))

;; dired (M-d)
(with-eval-after-load 'dired
  (my/bind-local dired-mode-map "RET"      #'my/dired-find-file)
  (my/bind-local dired-mode-map "<f2>"     #'wdired-change-to-wdired-mode)
  (my/bind-local dired-mode-map "M-f"      #'dired-create-empty-file)
  (my/bind-local dired-mode-map "M-d"      #'dired-create-directory)
  (my/bind-local dired-mode-map "M-<left>" #'dired-up-directory)
  (my/bind-local dired-mode-map "M-."      #'dired-omit-mode))

;; org (C-o)
(with-eval-after-load 'org
  (which-key-add-keymap-based-replacements org-mode-map "C-o" "org")
  (my/bind-local org-mode-map "C-o t" #'org-hide-drawers-toggle "toggle drawers"))

(provide 'my-keybindings)
;;; my-keybindings.el ends here
