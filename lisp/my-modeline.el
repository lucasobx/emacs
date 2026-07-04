;;; my-modeline.el --- custom modeline  -*- lexical-binding: t; -*-
;;; Commentary:
;;; Code:

(declare-function flycheck-count-errors "flycheck")
(declare-function flycheck-error-level-compilation-level "flycheck")
(defvar flycheck-current-errors)
(defvar flycheck-mode-line)

(declare-function vc-backend "vc-hooks")
(declare-function vc-state "vc-hooks")

(declare-function dired-get-filename "dired")
(defvar dired-re-dir)

(defun my/shorten-vc-mode (vc)
  "Return a shortened VC mode string."
  (let* ((vc (replace-regexp-in-string "^ Git[:@-]"
                                       (if (char-displayable-p ?\uE0A0)
                                           "\uE0A0 " "git: ")
                                       vc)))
    (if (> (length vc) 20)
        (concat (substring vc 0 20)
                (if (char-displayable-p ?…) "…" "..."))
      vc)))

(defvar my/vcs-state-faces
  '((up-to-date   . success)
    (edited       . warning)
    (added        . warning)
    (needs-update . warning)
    (needs-merge  . warning)
    (conflict     . error)
    (removed      . error)
    (missing      . error)
    (unregistered . shadow)
    (ignored      . shadow))
  "Cached vc mode-line segment.")

(defvar-local my/mode-line--vcs nil
  "Cached vc segment for the current buffer.")

(defun my/vcs--in-worktree-p ()
  "Return non-nil if the current file is in a Git worktree."
  (when-let* ((dir (and buffer-file-name
                        (not (file-remote-p buffer-file-name))
                        (locate-dominating-file buffer-file-name ".git"))))
    (file-regular-p (expand-file-name ".git" dir))))

(defun my/mode-line-update-vcs (&rest _)
  "Update the cached vc mode-line segment."
  (setq my/mode-line--vcs
        (when (and vc-mode buffer-file-name)
          (let* ((backend (vc-backend buffer-file-name))
                 (state (and backend (vc-state buffer-file-name backend)))
                 (face (alist-get state my/vcs-state-faces 'success))
                 (branch (propertize (my/shorten-vc-mode vc-mode) 'face face))
                 (worktree (and (my/vcs--in-worktree-p)
                                (propertize " WT" 'face 'warning))))
            (concat branch worktree)))))

(add-hook 'find-file-hook #'my/mode-line-update-vcs 90)
(add-hook 'after-save-hook #'my/mode-line-update-vcs)
(advice-add 'vc-refresh-state :after #'my/mode-line-update-vcs)

(defvar-local my/mode-line--total-lines nil
  "Cached buffer line count.")
(defvar-local my/mode-line--total-lines-tick nil
  "Modification tick for the cached line count.")

(defun my/mode-line-total-lines ()
  "Return the cached buffer line count, updating it if needed."
  (let ((tick (buffer-chars-modified-tick)))
    (unless (eql tick my/mode-line--total-lines-tick)
      (setq my/mode-line--total-lines-tick tick
            my/mode-line--total-lines (line-number-at-pos (point-max))))
    my/mode-line--total-lines))

(setq mode-line-position-line-format
      '(" L%l" (:eval (concat "/" (number-to-string (my/mode-line-total-lines))))))
(put 'mode-line-position-line-format 'risky-local-variable t)

(setq-default mode-line-modified
              '(:eval
                (cond
                 (buffer-read-only " ")
                 ((buffer-modified-p) " *")
                 (t " -"))))

(defvar-local my/flycheck-mode-line nil
  "Cached Flycheck mode-line segment.")

(defun my/flycheck-count-errors ()
  "Return Flycheck error counts."
  (let ((info 0) (warning 0) (error 0))
    (pcase-dolist (`(,level . ,count)
                   (flycheck-count-errors flycheck-current-errors))
      (pcase (flycheck-error-level-compilation-level level)
        (0 (setq info (+ info count)))
        (1 (setq warning (+ warning count)))
        (2 (setq error (+ error count)))))
    (list error warning info)))

(defun my/flycheck-update-mode-line (status)
  "Update the cached Flycheck segment for STATUS."
  (when (and (eq status 'finished) (bound-and-true-p flycheck-mode))
    (pcase-let ((`(,error ,warning ,info) (my/flycheck-count-errors)))
      (setq my/flycheck-mode-line
            `(" ["
              (:propertize ,(number-to-string error)   face flycheck-error-list-error)
              " "
              (:propertize ,(number-to-string warning) face flycheck-error-list-warning)
              " "
              (:propertize ,(number-to-string info)    face flycheck-error-list-info)
              "]")))))

(with-eval-after-load 'flycheck
  (add-hook 'flycheck-status-changed-functions #'my/flycheck-update-mode-line)
  (setq flycheck-mode-line '(:eval my/flycheck-mode-line)))

(defgroup my-modeline nil
  "Personal mode line."
  :group 'mode-line)

(defcustom my/dired-show-file-size t
  "When non-nil, show the size of the Dired entry at point."
  :type 'boolean :group 'my-modeline)

(defcustom my/dired-show-file-time t
  "When non-nil, show the modification time of the Dired entry at point."
  :type 'boolean :group 'my-modeline)

(defcustom my/dired-show-omit t
  "When non-nil, show the `dired-omit-mode' indicator."
  :type 'boolean :group 'my-modeline)

(defvar-local my/dired--mode-line nil
  "Cached file/directory count segment for a Dired buffer.")

(defvar-local my/dired--last-file nil
  "File at point after the last command, used to detect movement.")

(defvar-local my/dired--attr-cache nil
  "Cons of (FILENAME . ATTRIBUTES) for the Dired line at point.")

(defun my/dired-count ()
  "Return the number of files and directories."
  (let ((files 0) (dirs 0))
    (save-excursion
      (goto-char (point-min))
      (while (not (eobp))
        (when-let* ((name (dired-get-filename 'no-dir t)))
          (unless (member name '("." ".."))
            (if (save-excursion (beginning-of-line) (looking-at-p dired-re-dir))
                (setq dirs (1+ dirs))
              (setq files (1+ files)))))
        (forward-line 1)))
    (cons files dirs)))

(defun my/dired-update-mode-line ()
  "Update the cached Dired mode-line segment."
  (let ((count (my/dired-count)))
    (setq my/dired--mode-line
          (concat " " (number-to-string (car count)) "f "
                  (propertize (concat (number-to-string (cdr count)) "d")
                              'face 'dired-directory)))))

(with-eval-after-load 'dired
  (add-hook 'dired-after-readin-hook #'my/dired-update-mode-line))

(defvar my/dired-time-format "%Y-%m-%d %H:%M"
  "Time format for the Dired file timestamp.")

(defun my/dired-file-attrs ()
  "Return cached file attributes for the Dired entry at point, or nil."
  (when-let* ((name (and (derived-mode-p 'dired-mode)
                         (not (file-remote-p default-directory))
                         (dired-get-filename nil t))))
    (unless (equal name (car my/dired--attr-cache))
      (setq my/dired--attr-cache (cons name (file-attributes name))))
    (cdr my/dired--attr-cache)))

(defun my/dired-file-size ()
  "When non-nil, return the file size."
  (when my/dired-show-file-size
    (when-let* ((attrs (my/dired-file-attrs)))
      (concat "  " (propertize (file-size-human-readable (file-attribute-size attrs))
                               'face 'shadow)))))

(defun my/dired-file-time ()
  "When non-nill, return the file modification time."
  (when my/dired-show-file-time
    (when-let* ((attrs (my/dired-file-attrs)))
      (concat "  " (propertize (format-time-string my/dired-time-format
                                                   (file-attribute-modification-time attrs))
                               'face 'shadow)))))

(defun my/dired-omit-indicator ()
  "When non-nil, return the omit indicator."
  (when (and my/dired-show-omit (bound-and-true-p dired-omit-mode))
    (propertize "  omit" 'face 'shadow)))

(defun my/dired--refresh-mode-line ()
  "Refresh the mode-line when point moves to another Dired entry."
  (let ((name (dired-get-filename nil t)))
    (unless (equal name my/dired--last-file)
      (setq my/dired--last-file name)
      (force-mode-line-update))))

(defun my/dired-mode-line-setup ()
  "Set up the Dired mode-line for the current buffer."
  (kill-local-variable 'mode-line-buffer-identification)
  (add-hook 'post-command-hook #'my/dired--refresh-mode-line nil t))

(add-hook 'dired-mode-hook #'my/dired-mode-line-setup)

(setq-default mode-line-format
              '("%e" "  "
                ;; (:propertize " " display (raise +0.1)) ;; top padding
                ;; (:propertize " " display (raise -0.1)) ;; bottom padding
                (:propertize
                 (:eval (if (char-displayable-p ?λ) "λ " " ") face font-lock-keyword-face))
                (:propertize
                 ("" mode-line-client mode-line-modified))
                mode-line-frame-identification
                mode-line-buffer-identification
                "   "
                (:eval (if (derived-mode-p 'dired-mode)
                           my/dired--mode-line
                         mode-line-position))
                (:eval (my/dired-omit-indicator))
                (:eval (my/dired-file-size))
                (:eval (my/dired-file-time))
                mode-line-format-right-align
                "  "
                (project-mode-line project-mode-line-format)
                "  "
                (vc-mode (:eval my/mode-line--vcs))
                "  "
                mode-line-modes
                mode-line-misc-info
                "  ")
              project-mode-line t
              mode-line-buffer-identification '("%b")
              mode-line-modes-delimiters '("" . "")
              mode-line-percent-position nil)

;; hide eglot indicator
(with-eval-after-load 'eglot
  (setq-default mode-line-misc-info
                (assq-delete-all 'eglot--managed-mode mode-line-misc-info)))

;; hide all minor modes except those listed below
(setq mode-line-collapse-minor-modes-to ""
      mode-line-collapse-minor-modes
      '(not flycheck-mode
            ))

;; hide only these minor modes
;; (setq mode-line-collapse-minor-modes-to ""
;;       mode-line-collapse-minor-modes
;;       '(completion-preview-mode nerd-icons-dired-mode eldoc-box-hover-mode
;;         line-reminder-mode smooth-scroll-mode outline-minor-mode
;;         auto-revert-mode which-key-mode flyspell-mode
;;         abbrev-mode eldoc-mode devil-mode))

(provide 'my-modeline)
;;; my-modeline.el ends here
