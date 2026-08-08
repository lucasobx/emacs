;;; my-move-text.el --- Move lines and regions up/down  -*- lexical-binding: t; -*-

;; Author: Lucas
;; Keywords: convenience

;;; Commentary:

;; Two commands that move the current line, or every line the region touches,
;; one line up or down. Point and the region stay on the moved text.

;;; Code:

(defun my/move-text--move (n)
  "Move the current line or selected lines by N lines."
  (let* ((region (use-region-p))
         (rbeg (if region (region-beginning) (point)))
         (rend (if region (region-end) (point)))
         (col (current-column))
         (final-newline (or (= (point-min) (point-max))
                            (eq (char-before (point-max)) ?\n)))
         (beg (save-excursion (goto-char rbeg) (pos-bol)))
         (end (save-excursion
                (goto-char rend)
                (if (and region (= (point) (pos-bol)))
                    (point)
                  (pos-bol 2)))))
    ;; BEG equals END on the empty last line, where there is nothing to move.
    (when (and (< beg end)
               (if (< n 0) (> beg (point-min)) (< end (point-max))))
      (let* ((text (delete-and-extract-region beg end))
             (text (if (string-suffix-p "\n" text) text (concat text "\n")))
             (target (save-excursion (goto-char beg) (forward-line n) (point))))
        (goto-char target)
        ;; A last line with no newline of its own does not end at a line
        ;; beginning, and inserting there would join it to the moved text.
        (unless (bolp)
          (insert "\n")
          (setq target (point)))
        (insert text)
        (unless final-newline
          (save-excursion
            (goto-char (point-max))
            (when (bolp) (delete-char -1))))
        (if region
            (progn
              (set-mark target)
              (goto-char (+ target (length text)))
              (setq deactivate-mark nil))
          (goto-char target)
          (move-to-column col))))))

(defun my/move-text-up ()
  "Move the current line or region up by one line."
  (interactive)
  (my/move-text--move -1))

(defun my/move-text-down ()
  "Move the current line or region down by one line."
  (interactive)
  (my/move-text--move 1))

(provide 'my-move-text)
;;; my-move-text.el ends here
