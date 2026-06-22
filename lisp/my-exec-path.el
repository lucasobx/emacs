;;; my-exec-path.el --- exec path from shell  -*- lexical-binding: t; -*-
;;; Commentary:
;;; Code:

(defun my/exec-path--command (shell)
  "Return the (PROGRAM . ARGS) list that prints PATH for SHELL, or nil."
  (pcase shell
    ("fish" (list "fish" "-c" "string join : $PATH"))
    ("bash" (list "bash" "-l" "-i" "-c" "printenv PATH"))
    ("zsh"  (list "zsh"  "-l" "-i" "-c" "printenv PATH"))
    (_ nil)))

(defun my/exec-path-from-shell ()
  "Sync `exec-path' and PATH with the login shell asynchronously."
  (interactive)
  (let* ((shell (file-name-nondirectory (or (getenv "SHELL") "")))
         (command (my/exec-path--command shell)))
    (if (not command)
        (message ">>> exec-path: unsupported shell `%s'" shell)
      (let ((output ""))
        (make-process
         :name "my-exec-path"
         :buffer nil
         :noquery t
         :connection-type 'pipe
         :command command
         :filter (lambda (_proc chunk) (setq output (concat output chunk)))
         :sentinel
         (lambda (_proc event)
           (cond
            ((string-prefix-p "finished" event)
             (let ((path (string-trim output)))
               (if (string-empty-p path)
                   (lwarn 'my/exec-path :warning "empty PATH from `%s'" shell)
                 (setenv "PATH" path)
                 (setq exec-path (append (parse-colon-path path)
                                         (list exec-directory)))
                 (setq-default eshell-path-env path))))
            ((string-match-p "\\`\\(?:exited abnormally\\|failed\\)" event)
             (lwarn 'my/exec-path :warning
                    "`%s' failed to report PATH: %s" shell (string-trim event))))))))))

(add-hook 'after-init-hook #'my/exec-path-from-shell)

(provide 'my-exec-path)
;;; my-exec-path.el ends here
