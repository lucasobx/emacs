;;; my-text-ops.el --- text editing operations -*- lexical-binding: t; -*-
;;; Commentary:
;;; Code:

;; ===============================================================
;;; MOVEMENT & EDITING

(defun my/delete-dont-kill ()
  "Delete word backward without adding to kill ring."
  (delete-region (point) (progn (backward-word 1) (point))))

(defun my/backward-delete ()
  "Delete a word, a character, or whitespace."
  (interactive)
  (cond
   ((or (looking-back (rx (char word)) 1)
        (looking-back (rx (seq (char word) (= 1 blank))) 1))
    (my/delete-dont-kill))
   ((looking-back (rx (char blank)) 1)
    (delete-horizontal-space t))
   (t
    (backward-delete-char-untabify 1))))

(defun my/open-line-below ()
  "Create a new line below and move to it."
  (interactive)
  (end-of-line)
  (newline-and-indent))

(defun my/beginning-of-line ()
  "Go to first non-whitespace char, or column 0 if already there."
  (interactive "^")
  (let ((origin (point)))
    (back-to-indentation)
    (when (= origin (point))
      (beginning-of-line))))

;; ===============================================================
;;; DELIMITER BOUNDS

(defmacro my/define-inside (suffix open)
  "Define an inside-bounds function named from SUFFIX for the OPEN delimiter."
  `(defun ,(intern (format "my/inside-%s" suffix)) ()
     ,(format "Return bounds of content inside %s." suffix)
     (when (or (looking-at ,(regexp-quote open))
               (ignore-errors (backward-up-list 1) t))
       (let ((start (1+ (point)))
             (end   (1- (progn (forward-sexp) (point)))))
         (cons start end)))))

(my/define-inside parens   "(")
(my/define-inside brackets "[")
(my/define-inside braces   "{")

;; ===============================================================
;;; SELECTION

(defun my/select-bounds (bounds)
  "Activate a region spanning BOUNDS, a cons cell of (START . END)."
  (when bounds
    (goto-char (car bounds))
    (set-mark (cdr bounds))
    (activate-mark)))

;; select thing at point
(defmacro my/define-select (name thing)
  "Define NAME selecting THING at point as an active region."
  `(defun ,name ()
     ,(format "Select the %s at point." thing)
     (interactive)
     (my/select-bounds (bounds-of-thing-at-point ',thing))))

(my/define-select my/select-word      word)
(my/define-select my/select-symbol    symbol)
(my/define-select my/select-line      line)
(my/define-select my/select-paragraph paragraph)
(my/define-select my/select-defun     defun)
(my/define-select my/select-sexp      sexp)

;; select content inside delimiters
(defmacro my/define-select-inside (name bounds-fn)
  "Define NAME selecting the region returned by BOUNDS-FN."
  `(defun ,name ()
     "Select content inside delimiters at point."
     (interactive)
     (my/select-bounds (,bounds-fn))))

(my/define-select-inside my/select-in-parens   my/inside-parens)
(my/define-select-inside my/select-in-brackets my/inside-brackets)
(my/define-select-inside my/select-in-braces   my/inside-braces)

;; ===============================================================
;;; WRAPPING

(defmacro my/define-wrap (suffix open close)
  "Define a command that wraps text with OPEN and CLOSE, identified by SUFFIX."
  `(defun ,(intern (format "my/wrap-%s" suffix)) ()
     ,(format "Wrap the region, or the symbol at point, with %s%s." open close)
     (interactive)
     (let ((bounds (if (use-region-p)
                       (cons (region-beginning) (region-end))
                     (and (memq (char-syntax (or (char-after) ?\s)) '(?w ?_))
                          (bounds-of-thing-at-point 'symbol)))))
       (when bounds
         (let ((beg (car bounds))
               (end (cdr bounds)))
           (save-excursion
             (goto-char end) (insert ,close)
             (goto-char beg) (insert ,open))
           (pulse-momentary-highlight-region beg (+ end (length ,open) (length ,close)))
           (when (use-region-p) (deactivate-mark)))))))

(my/define-wrap parens   "(" ")")
(my/define-wrap brackets "[" "]")
(my/define-wrap braces   "{" "}")
(my/define-wrap quotes   "\"" "\"")

;; ===============================================================
;;; OPERATION HELPERS

;; region-aware dispatch
(defmacro my/region-or (fallback &rest body)
  "Act on the active region, falling back to FALLBACK when none is active.
When a region is active it is highlighted, BODY runs with `beg' and `end'
bound to the region bounds, and the mark is deactivated afterwards.
Otherwise FALLBACK is evaluated."
  (declare (indent 1))
  `(if (use-region-p)
       (let ((beg (region-beginning))
             (end (region-end)))
         (pulse-momentary-highlight-region beg end)
         ,@body
         (deactivate-mark))
     ,fallback))

;; generic operations
(defun my/delete-thing (thing)
  "Delete THING at point and save to kill ring with visual feedback."
  (let ((bounds (bounds-of-thing-at-point thing)))
    (when bounds
      (pulse-momentary-highlight-region (car bounds) (cdr bounds))
      (sit-for 0.15)
      (kill-region (car bounds) (cdr bounds)))))

(defun my/delete-inside (bounds-fn)
  "Delete content inside delimiter using BOUNDS-FN with visual feedback."
  (let ((bounds (save-excursion (funcall bounds-fn))))
    (when bounds
      (pulse-momentary-highlight-region (car bounds) (cdr bounds))
      (kill-region (car bounds) (cdr bounds)))))

(defun my/copy-thing (thing)
  "Copy THING at point to kill ring with visual feedback."
  (let ((bounds (bounds-of-thing-at-point thing)))
    (when bounds
      (pulse-momentary-highlight-region (car bounds) (cdr bounds))
      (kill-ring-save (car bounds) (cdr bounds))
      (message "Copied %s" (symbol-name thing)))))

(defun my/copy-inside (bounds-fn)
  "Copy content inside delimiter using BOUNDS-FN with visual feedback."
  (let ((bounds (save-excursion (funcall bounds-fn))))
    (when bounds
      (pulse-momentary-highlight-region (car bounds) (cdr bounds))
      (kill-ring-save (car bounds) (cdr bounds))
      (message "Copied region"))))

(defun my/toggle-comment-thing (thing)
  "Toggle comment on THING at point with visual feedback."
  (let ((bounds (bounds-of-thing-at-point thing)))
    (when bounds
      (let ((start (save-excursion
                     (goto-char (car bounds))
                     (line-beginning-position)))
            (end (save-excursion
                   (goto-char (cdr bounds))
                   (line-end-position))))
        (pulse-momentary-highlight-region start end)
        (sit-for 0.05)
        (comment-or-uncomment-region start end)))))

;; command generators
(defmacro my/define-ops (helper &rest specs)
  "Define interactive commands from SPECS, each calling HELPER with one argument."
  `(progn
     ,@(mapcar
        (lambda (spec)
          (pcase-let ((`(,name ,arg ,doc) spec))
            `(defun ,name ()
               ,doc
               (interactive)
               (,helper ,arg))))
        specs)))

(defmacro my/define-delete-cleanup (name thing)
  "Define command NAME deleting THING at point and clean up whitespace."
  `(defun ,name ()
     ,(format "Delete %s at point, cleaning up leftover whitespace." thing)
     (interactive)
     (let ((bounds (bounds-of-thing-at-point ',thing)))
       (when bounds
         (pulse-momentary-highlight-region (car bounds) (cdr bounds))
         (sit-for 0.15)
         (let ((preceded-by-space (save-excursion
                                    (goto-char (car bounds))
                                    (looking-back "\\s-" 1)))
               (followed-by-space (save-excursion
                                    (goto-char (cdr bounds))
                                    (looking-at "\\s-"))))
           (delete-region (car bounds) (cdr bounds))
           (cond
            (followed-by-space (delete-char 1))
            (preceded-by-space (delete-char -1))))))))

;; ===============================================================
;;; DELETE COMMANDS

(my/define-delete-cleanup my/delete-word   word)
(my/define-delete-cleanup my/delete-symbol symbol)

(defun my/delete-line ()
  "Delete line at point, or active region if one exists."
  (interactive)
  (my/region-or (my/delete-thing 'line)
    (sit-for 0.15)
    (kill-region beg end)))

(my/define-ops my/delete-thing
  (my/delete-paragraph 'paragraph "Delete paragraph at point.")
  (my/delete-defun     'defun     "Delete defun at point."))

(my/define-ops my/delete-inside
  (my/delete-in-parens   #'my/inside-parens   "Delete text inside parentheses.")
  (my/delete-in-brackets #'my/inside-brackets "Delete text inside brackets.")
  (my/delete-in-braces   #'my/inside-braces   "Delete text inside braces."))

;; ===============================================================
;;; COPY COMMANDS

(defun my/copy-line ()
  "Copy line at point, or active region if one exists."
  (interactive)
  (my/region-or (my/copy-thing 'line)
    (kill-ring-save beg end)
    (message "Copied region")))

(my/define-ops my/copy-thing
  (my/copy-paragraph 'paragraph "Copy paragraph at point.")
  (my/copy-word      'word      "Copy word at point.")
  (my/copy-symbol    'symbol    "Copy symbol at point.")
  (my/copy-defun     'defun     "Copy defun at point."))

(my/define-ops my/copy-inside
  (my/copy-inside-parens   #'my/inside-parens   "Copy text inside parentheses.")
  (my/copy-inside-brackets #'my/inside-brackets "Copy text inside brackets.")
  (my/copy-inside-braces   #'my/inside-braces   "Copy text inside braces."))

;; ===============================================================
;;; COMMENT COMMANDS

(defun my/toggle-comment-line ()
  "Toggle comment on current line."
  (interactive)
  (comment-line 1))

(my/define-ops my/toggle-comment-thing
  (my/toggle-comment-paragraph 'paragraph "Toggle comment on paragraph at point.")
  (my/toggle-comment-defun     'defun     "Toggle comment on defun at point."))

(provide 'my-text-ops)
;;; my-text-ops.el ends here
