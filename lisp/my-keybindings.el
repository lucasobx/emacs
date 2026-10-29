;;; my-keybindings.el --- Keybindings  -*- lexical-binding: t; -*-

;; Author: Lucas
;; Keywords: convenience

;;; Commentary:

;; Personal keybindings: a global override keymap, region-aware
;; prefixes with which-key labels, and per-mode bindings.

;;; Code:

(defvar completion-preview-active-mode-map)
(defvar ghostel-semi-char-mode-map)
(defvar magit-status-mode-map)
(defvar consult-buffer-filter)
(defvar ruby-ts-mode-map)
(defvar wdired-mode-map)
(defvar eglot-mode-map)
(defvar dired-mode-map)
(defvar transient-map)
(defvar org-mode-map)

(declare-function magit-restore-window-configuration "magit-mode")
(declare-function magit-mode-get-buffers "magit-mode")
(declare-function my/backward-delete "my-text-ops")
(declare-function ghostel-send-key "ghostel")
(declare-function consult-buffer "consult")

;; ===============================================================
;;; SETUP

(require 'bind-key)
(require 'which-key)
(defalias 'my/wk-add #'which-key-add-key-based-replacements)

;; ===============================================================
;;; HELPERS
;;
;; A binding is (KEY COMMAND [DESC]).  DESC labels it in which-key,
;; and DESC t hides it, except in `my/bind-local'.  Each binder takes
;; any number of bindings:
;;   (my/bind-prefix "C-s" "search"
;;     ("r" consult-recent-file "recent files")
;;     ("g" consult-ripgrep     "find in project"))

(defun my/wk-hide (&rest keys)
  "Hide each of KEYS from the which-key popup."
  (dolist (key keys)
    (let ((kd (key-description (kbd key))))
      (push (cons (cons (concat "\\`" (regexp-quote kd) "\\'") nil) t)
            which-key-replacement-alist))))

(defun my/bind--keys (map prefix bindings)
  "Bind each (KEY COMMAND [DESC]) in BINDINGS in MAP.
Each which-key label is registered under PREFIX + KEY.  DESC t hides it."
  (pcase-dolist (`(,key ,command ,desc) bindings)
    (keymap-set map key command)
    (let ((full (if prefix (concat prefix " " key) key)))
      (cond ((eq desc t) (my/wk-hide full))
            (desc         (my/wk-add full desc))))))

(defun my/bind--local (keymap bindings)
  "Bind each (KEY COMMAND [DESC]) in BINDINGS in KEYMAP."
  (pcase-dolist (`(,key ,command ,desc) bindings)
    (keymap-set keymap key (if desc (cons desc command) command))))

(defmacro my/bind (&rest bindings)
  "Bind each (KEY COMMAND [DESC]) in BINDINGS in `override-global-map'."
  (declare (indent 0))
  `(my/bind--keys override-global-map nil ',bindings))

(defmacro my/bind-prefix (prefix label &rest bindings)
  "Bind each (KEY COMMAND [DESC]) in BINDINGS under PREFIX, labeled LABEL."
  (declare (indent 2))
  `(progn
     (my/wk-add ,prefix ,label)
     (my/bind ,@(mapcar (lambda (binding)
                          (cons (concat prefix " " (car binding)) (cdr binding)))
                        bindings))))

(defmacro my/bind-local (keymap &rest bindings)
  "Bind each (KEY COMMAND [DESC]) in BINDINGS in KEYMAP."
  (declare (indent 1))
  `(my/bind--local ,keymap ',bindings))

(defmacro my/bind-sub (map prefix &rest bindings)
  "Bind each (KEY COMMAND [DESC]) in BINDINGS in MAP.
Each which-key label is registered under PREFIX + KEY.  DESC t hides it."
  (declare (indent 2))
  `(my/bind--keys ,map ,prefix ',bindings))

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
  (require 'consult)
  (let ((consult-buffer-filter '("\\`[^*]")))
    (consult-buffer '(consult-source-buffer))))

(defun my/isearch-copy-selected-word ()
  "Copy the current Isearch match to the kill ring."
  (interactive)
  (when isearch-other-end
    (copy-region-as-kill isearch-other-end (point))
    (isearch-exit)))

(defun my/isearch-query-replace ()
  "Run `isearch-query-replace' on the whole buffer."
  (interactive)
  (let* ((origin (copy-marker (min (point) (or isearch-other-end (point))) t))
         (wrapped nil)
         (last nil)
         (replace-search-function
          (lambda (string bound noerror)
            (let ((search (isearch-search-fun-default))
                  (pos (point)))
              (cond
               ((or bound (not isearch-forward))
                (funcall search string bound noerror))
               ((and (not wrapped)
                     (funcall search string nil noerror)
                     (or (< (point) (point-max))
                         (progn (setq last (copy-marker (match-beginning 0) t))
                                nil)))
                (point))
               (t
                (unless wrapped
                  (setq wrapped t)
                  (goto-char (point-min)))
                (or (and (<= (point) origin)
                         (funcall search string origin noerror))
                    (when last
                      (goto-char last)
                      (setq last nil)
                      (funcall search string nil noerror))
                    (progn (goto-char pos) nil)))))))
         (replace-re-search-function replace-search-function))
    (call-interactively #'isearch-query-replace)))

(defun my/isearch-backward-delete ()
  "Delete backward in the search string."
  (interactive)
  (unless (string-empty-p isearch-string)
    (let* ((table (syntax-table))
           (kept (with-temp-buffer
                   (set-syntax-table table)
                   (insert isearch-string)
                   (my/backward-delete)
                   (buffer-size))))
      (isearch-del-char (- (length isearch-string) kept)))))

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

;; C-m and RET are the same key, except in graphical frames
(defun my/decode-C-m (&optional frame)
  "Make Ctrl+m send a separate event in FRAME, if graphical."
  (when (display-graphic-p frame)
    (with-selected-frame (or frame (selected-frame))
      (keymap-set input-decode-map "C-m" [C-m]))))
(my/decode-C-m)
(add-hook 'after-make-frame-functions #'my/decode-C-m)

;; tools
(my/bind
  ("<f1>" scratch-buffer)
  ("<f3>" diff-hl-show-hunk)
  ("<f4>" my/rotate-theme)
  ("C-z"  dired-snacks-zoxide)
  ("C-f"  dired-snacks-find)
  ("C-p"  dired-snacks-drives)
  ("C-t"  ghostel))

;; buffers and windows
(my/bind
  ("C-b"     consult-buffer)
  ("C-k"     my/kill-buffer-and-window)
  ("C-<tab>" other-window)
  ("C-,"     popper-toggle)
  ("C-<"     popper-cycle))

;; editing
(my/bind
  ("C-v"           yank)
  ("C-<backspace>" my/backward-delete)
  ("M-a"           my/select-line)
  ("M-u"           upcase-dwim)
  ("M-c"           capitalize-dwim)
  ("M-<up>"        my/move-text-up)
  ("M-<down>"      my/move-text-down)
  ("C-<m>"         rectangle-mark-mode)
  ("C-a"           mark-whole-buffer)
  ("C-0"           my/wrap-parens)
  ("C-]"           my/wrap-brackets))

;; text size
(my/bind
  ("C-=" text-scale-increase)
  ("C--" text-scale-decrease))

;; overridable by modes
(my/bind-local global-map
  ("<f2>"      magit-status)
  ("M-d"       dired-jump)
  ("M-m"       mark-paragraph)
  ("M-l"       downcase-dwim)
  ("C-o"       my/open-line-below)
  ("M-k"       kill-line)
  ("M-p"       duplicate-dwim)
  ("M-<right>" my/end-of-line)
  ("M-<left>"  my/beginning-of-line)
  ("RET"       newline-and-indent))

;; ===============================================================
;;; PREFIX GROUPS
;;
;; with an active region, bare C-d/C-y act as kill-region/kill-ring-save.
;; with no region they behave as ordinary prefix maps.

(defvar my/delete-map (make-sparse-keymap)
  "Prefix map for `C-d' delete operations.")

(defvar my/copy-map (make-sparse-keymap)
  "Prefix map for `C-y' copy operations.")

(keymap-set override-global-map "C-d"
            (my/region-aware-prefix my/delete-map #'kill-region))
(keymap-set override-global-map "C-y"
            (my/region-aware-prefix my/copy-map #'kill-ring-save))

(my/wk-add "C-d" "delete")
(my/bind-sub my/delete-map "C-d"
  ("p" my/delete-paragraph       "paragraph")
  ("d" my/delete-line            "line")
  ("s" my/delete-symbol          "symbol")
  ("0" my/delete-inside-parens   "inside ()")
  ("]" my/delete-inside-brackets "inside []")
  ("." my/delete-all             "all"))

(my/wk-add "C-y" "copy")
(my/bind-sub my/copy-map "C-y"
  ("p" my/copy-paragraph       "paragraph")
  ("y" my/copy-line            "line")
  ("s" my/copy-symbol          "symbol")
  ("0" my/copy-inside-parens   "inside ()")
  ("]" my/copy-inside-brackets "inside []")
  ("." my/copy-all             "all"))

(my/bind-prefix "C-;" "comment"
  ("p" my/toggle-comment-paragraph "paragraph")
  (";" my/toggle-comment-line      "line")
  ("." my/toggle-comment-all       "all"))

;; line-block counts (1-9): delete/copy/comment, below or above (<up> N)
(dotimes (i 9)
  (let ((n (1+ i)))
    (pcase-dolist (`(,key ,name) '(("" "") ("<up> " "up-")))
      (keymap-set override-global-map (format "C-; %s%d" key n)
                  (intern (format "my/comment-lines-%s%d" name n)))
      (keymap-set my/delete-map (format "%s%d" key n)
                  (intern (format "my/delete-lines-%s%d" name n)))
      (keymap-set my/copy-map (format "%s%d" key n)
                  (intern (format "my/copy-lines-%s%d" name n))))))
(push '(("\\`C-[;dy] \\(?:<up>\\|\\(?:<up> \\)?[1-9]\\)\\'" . nil) . t)
      which-key-replacement-alist)
(push "\\`C-[;dy] <up>\\'" which-key-inhibit-regexps)

(my/bind-prefix "C-." "cursors"
  ("m" mc/mark-all-in-region      "mark matches in region")
  ("l" mc/edit-lines              "mark lines in region")
  ("." mc/mark-next-like-this     "mark next")
  ("/" mc/mark-previous-like-this "mark prev"))

(my/bind-prefix "C-s" "search"
  ("r" consult-recent-file "recent files")
  ("g" consult-ripgrep     "find in project")
  ("i" consult-imenu       "find in outline")
  ("s" isearch-forward     "find in buffer"))

(my/bind-prefix "C-w" "window"
  ("w" split-window-below         "new window ↓")
  ("v" split-window-right         "new window →")
  ("f" window-layout-flip-topdown "flip window ↑↓")
  ("d" delete-window              "close window"))

(my/bind-prefix "C-x" "emacs"
  ("<left>"  previous-buffer t)
  ("<right>" next-buffer     t)
  ("r" tramp-revert-buffer-with-sudo "sudo edit file")
  ("b" my/system-buffers   "system-buffers")
  ("t" visual-line-mode    "truncate lines")
  ("i" my/find-init-file   "go to init.el")
  ("x" restart-emacs       "restart emacs")
  ("s" save-buffer         "save buffer"))

(my/bind-prefix "C-h" "help"
  ("h" describe-symbol   "desc symbol")
  ("k" describe-key      "desc key")
  ("d" devdocs-lookup    "devdocs"))

;; ===============================================================
;;; MODE MAPS

(my/bind-local isearch-mode-map
  ("<down>"        isearch-repeat-forward)
  ("<up>"          isearch-repeat-backward)
  ("C-v"           isearch-yank-kill)
  ("C-<backspace>" my/isearch-backward-delete)
  ("M-w"           my/isearch-copy-selected-word)
  ("M-r"           my/isearch-query-replace))

(with-eval-after-load 'dired
  (my/bind-local dired-mode-map
    ("RET"      dired-snacks-open)
    ("TAB"      dired-snacks-subtree-toggle)
    ("M-<left>" dired-up-directory)
    ("M-."      dired-omit-mode)
    ("s"        dired-snacks-sort-cycle)
    ("<f2>"     wdired-change-to-wdired-mode)
    ("M-f"      dired-create-empty-file)
    ("M-p"      dired-snacks-duplicate)
    ("M-s"      dired-snacks-split))
  (my/bind-local dired-mode-map
    ("M-w"            dired-snacks-clip)
    ("<remap> <yank>" dired-snacks-paste)
    ("M-m"            dired-snacks-paste-move)
    ("M-l"            dired-snacks-paste-symlink)
    ("M-q"            dired-snacks-paste-cancel)
    ("M-y"            dired-snacks-copy-file-uri)))

(with-eval-after-load 'wdired
  (my/bind-local wdired-mode-map
    ("<escape>" wdired-abort-changes)))

(with-eval-after-load 'completion-preview
  (my/bind-local completion-preview-active-mode-map
    ("M-n" completion-preview-next-candidate)))

(with-eval-after-load 'elisp-mode
  (dolist (map (list emacs-lisp-mode-map lisp-interaction-mode-map))
    (dolist (key '("C-c C-b" "C-c C-e" "C-c C-f"))
      (keymap-unset map key t))
    (my/bind-local map
      ("C-x e" eval-last-sexp "eval sexp"))))

(with-eval-after-load 'ruby-ts-mode
  (keymap-set ruby-ts-mode-map "C-l" (cons "lsp" (make-sparse-keymap)))
  (my/bind-local ruby-ts-mode-map
    ("C-l b" ruby-send-buffer "send buffer")
    ("C-l s" ruby-send-region "send region")
    ("C-l l" ruby-send-line   "send line")
    ("C-l r" inf-ruby         "open repl")))

(with-eval-after-load 'eglot
  (keymap-set eglot-mode-map "C-l" (cons "lsp" (make-sparse-keymap)))
  (my/bind-local eglot-mode-map
    ("C-l n" eglot-rename     "rename symbol")
    ("C-l e" consult-flycheck "list errors")))

(with-eval-after-load 'org
  (dolist (key '("M-<left>" "M-<right>" "C-S-<up>" "C-S-<down>"))
    (keymap-unset org-mode-map key t))
  (my/bind-local org-mode-map
    ("C-c t" org-hide-drawers-toggle "toggle drawers")))

(with-eval-after-load 'ghostel
  ;; `keymap-set' rejects a slash in the command name of a <remap> key.
  (define-key ghostel-semi-char-mode-map [remap my/backward-delete]
              #'my/ghostel-backward-delete))

(with-eval-after-load 'magit-status
  (my/bind-local magit-status-mode-map
    ("q" my/magit-kill-buffers)))

(with-eval-after-load 'transient
  (my/bind-local transient-map
    ("<escape>" transient-quit-one)))

(provide 'my-keybindings)
;;; my-keybindings.el ends here
