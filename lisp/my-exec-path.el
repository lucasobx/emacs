;;; my-exec-path.el --- exec path from shell  -*- lexical-binding: t; -*-
;;; Commentary:
;;; Code:

(defun my/exec-path-from-shell ()
  "Sync `exec-path' and PATH with the login shell asynchronously."
  (interactive)
  (let* ((shell (file-name-nondirectory (or (getenv "SHELL") "")))
         (command (pcase shell
                    ("fish" "fish -c 'string join : $PATH'")
                    ("bash" "bash --login -c 'printenv PATH'")
                    ("zsh"  "zsh -i -c 'printenv PATH'")
                    (_ nil))))
    (if (not command)
        (message ">>> exec-path: unsupported shell `%s'" shell)
      (let ((output ""))
        (make-process
         :name "my-exec-path"
         :buffer nil
         :noquery t
         :connection-type 'pipe
         :command (list shell-file-name shell-command-switch command)
         :filter (lambda (_proc chunk) (setq output (concat output chunk)))
         :sentinel
         (lambda (_proc event)
           (when (string-prefix-p "finished" event)
             (let ((path (string-trim output)))
               (unless (string-empty-p path)
                 (setenv "PATH" path)
                 (setq exec-path (append (parse-colon-path path)
                                         (list exec-directory)))
                 (setq-default eshell-path-env path))))))))))
(add-hook 'after-init-hook #'my/exec-path-from-shell)

(provide 'my-exec-path)
;;; my-exec-path.el ends here
