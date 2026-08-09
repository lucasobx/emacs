;;; early-init.el --- Emacs -*- lexical-binding: t; no-byte-compile: t; -*-
;;; Commentary:
;;; Code:

;; emacs 31
(when (boundp 'load-path-filter-function)
  (setq load-path-filter-function #'load-path-filter-cache-directory-files))

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
(when (fboundp 'startup-redirect-eln-cache)
  (startup-redirect-eln-cache "cache/eln-cache/"))
(setq native-comp-async-report-warnings-errors 'silent)
(setq byte-compile-warnings nil
      byte-compile-verbose nil)
(setq jka-compr-verbose nil)

;; miscellaneous performance
(setq-default cursor-in-non-selected-windows nil)
(setq fast-but-imprecise-scrolling t)
(setq auto-window-vscroll nil)

(setq read-process-output-max (* 1024 1024 4))
(setq process-adaptive-read-buffering nil)
(setq inhibit-compacting-font-caches t)
(setq ffap-machine-p-known 'reject)
(setq vc-handled-backends '(Git))
(setq auto-mode-case-fold nil)
(setq inhibit-x-resources t)
(setq site-run-file nil)

;; pgtk (wayland)
(when (boundp 'pgtk-wait-for-event-timeout)
  (setq pgtk-wait-for-event-timeout 0.001))

;; frame sizing
(setq frame-inhibit-implied-resize t
      frame-resize-pixelwise t)

;; default frame appearance
(setq default-frame-alist
      '((horizontal-scroll-bars . nil)
        (vertical-scroll-bars . nil)
        (menu-bar-lines . 0)
        (tool-bar-lines . 0)))

;; package.el + quickstart
(setq package-enable-at-startup t
      package-quickstart t)

;; disable UI elements early
(advice-add 'display-startup-screen :override #'ignore)
(setq scroll-bar-mode nil)
(setq menu-bar-mode nil)
(setq tool-bar-mode nil)

;; utf-8
(set-language-environment "UTF-8")

;; disable bidi processing
(setq-default bidi-paragraph-direction 'left-to-right)
(setq bidi-inhibit-bpa t)

;; trusted content
(when (boundp 'trusted-content)
  (add-to-list 'trusted-content
               (file-name-as-directory (locate-user-emacs-file "lisp"))))

;; misc
(setq command-line-ns-option-alist nil)
(setq command-line-x-option-alist nil)
(setq ad-redefinition-action 'accept)
(setenv "LSP_USE_PLISTS" "true")

;;; early-init.el ends here
