;;; early-init.el --- Emacs -*- lexical-binding: t; no-byte-compile: t; -*-
;;; Commentary:
;;; Code:

;; garbage collection
(setq gc-cons-threshold most-positive-fixnum
      gc-cons-percentage 1.0)

(add-hook 'emacs-startup-hook
          (lambda ()
            (setq gc-cons-threshold (* 128 1024 1024)
                  gc-cons-percentage 0.1)))

;; file-name-handler-alist
(defvar my/old-file-name-handler-alist file-name-handler-alist)
(set-default-toplevel-value 'file-name-handler-alist nil)
(add-hook 'emacs-startup-hook
          (lambda ()
            (set-default-toplevel-value
             'file-name-handler-alist
             (delete-dups (append file-name-handler-alist
                                  my/old-file-name-handler-alist)))))

;; native/byte compilation
(setq native-comp-async-report-warnings-errors 'silent)
(setq byte-compile-warnings nil
      byte-compile-verbose nil)
(setq jka-compr-verbose nil)

;; miscellaneous performance
(setq read-process-output-max (* 1024 1024 4))
(setq process-adaptive-read-buffering nil)
(setq auto-mode-case-fold nil) 
(setq ffap-machine-p-known 'reject)
(setq inhibit-x-resources t)

;; pgtk (wayland)
(when (boundp 'pgtk-wait-for-event-timeout)
  (setq pgtk-wait-for-event-timeout 0.001))

;; frame sizing
(setq frame-inhibit-implied-resize t
      frame-resize-pixelwise t)

;; default frame appearance
(setq default-frame-alist
      '((background-color . "#110d12")
        (vertical-scroll-bars . nil)
        (horizontal-scroll-bars . nil)
        (menu-bar-lines . 0)
        (tool-bar-lines . 0)
        (left-fringe . 8)
        (right-fringe . 8)))

;; disable UI elements early
(setq package-enable-at-startup nil)
(setq-default mode-line-format nil)
(setq menu-bar-mode nil)
(setq tool-bar-mode nil)
(setq scroll-bar-mode nil)
(advice-add 'display-startup-screen :override #'ignore)

;; utf-8
(set-language-environment "UTF-8")

;; disable bidi processing
(setq-default bidi-display-reordering 'left-to-right
              bidi-paragraph-direction 'left-to-right)
(setq bidi-inhibit-bpa t)

;; misc
(setq frame-inhibit-implied-resize t
      frame-resize-pixelwise t
      inhibit-compacting-font-caches t)
(setq ad-redefinition-action 'accept)
(setq command-line-ns-option-alist nil)
(setq command-line-x-option-alist nil)
(setenv "LSP_USE_PLISTS" "true")

;;; early-init.el ends here
