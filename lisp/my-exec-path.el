;;; my-exec-path.el --- Exec path from shell  -*- lexical-binding: t; -*-

;; Author: Lucas
;; Keywords: unix, processes

;;; Commentary:

;; Get PATH from the login shell on startup, so GUI Emacs
;; can find the same executables as the terminal.

;;; Code:

(defun my/exec-path--command (shell)
  "Return the (PROGRAM . ARGS) list that prints PATH for SHELL, or nil."
  (pcase shell
    ("fish" (list "fish" "-c" "string join : $PATH"))
    ("bash" (list "bash" "-l" "-i" "-c" "printenv PATH"))
    ("zsh"  (list "zsh"  "-l" "-i" "-c" "printenv PATH"))
    (_ nil)))

(defun my/exec-path-from-shell ()
  "Sync the variable `exec-path' and PATH with the login shell, asynchronously."
  (interactive)
  (let* ((shell (file-name-nondirectory (or (getenv "SHELL") "")))
         (command (my/exec-path--command shell)))
    (if (not command)
        (message ">>> exec-path: unsupported shell `%s'" shell)
      (let ((output "")
            (stderr (generate-new-buffer " *my-exec-path-stderr*")))
        ;; `make-process' signals synchronously when the shell is missin,
        ;; clean up the stderr buffer instead of leaking it in that case.
        (condition-case err
            (make-process
             :name "my-exec-path"
             :buffer nil
             :noquery t
             :connection-type 'pipe
             :command command
             :stderr stderr
             :filter (lambda (_proc chunk) (setq output (concat output chunk)))
             :sentinel
             (lambda (_proc event)
               (unwind-protect
                   (cond
                    ((string-prefix-p "finished" event)
                     (let ((path (string-trim output)))
                       (if (string-empty-p path)
                           (lwarn 'my/exec-path :warning "empty PATH from `%s'" shell)
                         (setenv "PATH" path)
                         (setq exec-path (append (remq nil (parse-colon-path path))
                                                 (list exec-directory))))))
                    ((string-match-p "\\`\\(?:exited abnormally\\|failed\\)" event)
                     (lwarn 'my/exec-path :warning
                            "`%s' failed to report PATH: %s" shell (string-trim event))))
                 (when (buffer-live-p stderr) (kill-buffer stderr)))))
          (error
           (when (buffer-live-p stderr) (kill-buffer stderr))
           (signal (car err) (cdr err))))))))

(add-hook 'after-init-hook #'my/exec-path-from-shell)

(provide 'my-exec-path)
;;; my-exec-path.el ends here
