;;; my-modeline.el --- custom modeline  -*- lexical-binding: t; -*-
;;; Commentary:
;;; Code:

(declare-function flycheck-error-level-compilation-level "flycheck")
(declare-function flycheck-count-errors "flycheck")
(declare-function vc-backend "vc-hooks")
(declare-function vc-state "vc-hooks")
(defvar flycheck-current-errors)
(defvar flycheck-mode-line)

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
            `(" "
              (:propertize ,(number-to-string error)   face flycheck-error-list-error)
              (:propertize " " display (space :width 0.3))
              (:propertize ,(number-to-string warning) face flycheck-error-list-warning)
              (:propertize " " display (space :width 0.3))
              (:propertize ,(number-to-string info)    face flycheck-error-list-info)
              "")))))

(with-eval-after-load 'flycheck
  (add-hook 'flycheck-status-changed-functions #'my/flycheck-update-mode-line)
  (setq flycheck-mode-line '(:eval my/flycheck-mode-line)))

(setq-default mode-line-format
              '("%e" "  "
                (:propertize " " display (raise +0.1)) ;; top padding
                (:propertize " " display (raise -0.1)) ;; bottom padding
                (:propertize
                 (:eval (if (char-displayable-p ?λ) "λ " " ") face font-lock-keyword-face))
                (:propertize
                 ("" mode-line-client mode-line-modified))
                mode-line-frame-identification
                mode-line-buffer-identification
                "  "
                mode-line-position
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
