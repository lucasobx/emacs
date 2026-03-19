;;; rg-themes-bosque-theme.el --- A night walk through the forest -*- lexical-binding: t; -*-

;; Copyright (C) 2025  Ronaldo Gligan

;; Author: Ronaldo Gligan <ronaldogligan@gmail.com>
;; URL: https://github.com/raegnald/rg-themes
;; Version: 0.1.0
;; Keywords: faces

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:
;;; Code:

(require 'rg-themes)

(defconst rg-themes-custom-palette
  (rg-themes-define-palette
     '((main-bg              . "#110d12")
      (main-fg              . "#bcafb6")

      (bosque-oscuro-extra  . "#3e3042")
      (bosque-oscuro-0      . "#3e3042")
      (bosque-oscuro-1      . "#503f58")
      (bosque-oscuro-2      . "#695a75")
      (bosque-code-1        . "#928d9a")
      (bosque-code-2        . "#7d7688")
      (bosque-code-3        . "#989ea1")
      (bosque-code-4        . "#b1a599")

      (drought-custom-darker . "#373b4d")
      (drought-grass-darker+ . "#515670")
      (drought-grass-darker  . "#636e94")
      (drought-grass-dark    . "#768c9c")
      (drought-grass         . "#989ea1")
      (drought-grass-lighter . "#bcafb6")

      (uranus         . "#768c9c")
      (salmon-tint    . "#a67c6a")
      (keyword-colour . "#a09b72")
      (invigorating   . "#758672")
      (some-red       . "#98585b")
      (pinkish        . "#a67c6a"))   
    
    ;; The palette associations
    '((background . main-bg)
      (foreground . main-fg)

      (cursor . drought-grass)
      (region . bosque-oscuro-1)
      (fringe . main-bg)

      (background-accent-strong . bosque-oscuro-0)
      (background-accent-medium . bosque-oscuro-1)
      (background-accent-light  . bosque-oscuro-2)

      (mode-line-background          . bosque-oscuro-0)
      (mode-line-foreground          . drought-grass-lighter)
      (mode-line-inactive-background . bosque-oscuro-2)
      (mode-line-inactive-foreground . drought-custom-darker)

      (accent-strong . drought-grass)
      (accent-medium . drought-grass-dark)

      (grey-neutral . bosque-code-2)
      (grey-accent  . bosque-code-1)

      (line-number             . bosque-code-2)
      (current-line-number     . bosque-code-1)
      (current-line-background . bosque-oscuro-extra)

      (white   . drought-grass-lighter)
      (black   . bosque-oscuro-0)
      (red     . some-red)
      (green   . drought-grass-darker+)
      (yellow  . keyword-colour)
      (blue    . uranus)
      (magenta . pinkish)
      (cyan    . uranus)

      (success . bosque-code-4)
      (warning . some-red)

      (built-in            . bosque-code-3)
      (preprocessor        . bosque-code-3)
      (comment             . drought-grass-darker)
      (comment-delimiter   . drought-grass-darker+)
      (comment-doc         . drought-grass-dark)
      (comment-doc-markup  . drought-grass)
      (punctuation         . drought-grass-darker+)
      (type                . invigorating)
      (function-name       . drought-grass-lighter)
      (variable-name       . bosque-code-4)
      (keyword             . uranus)
      (string              . pinkish)
      (escaped-char        . drought-grass-darker)
      (negation            . some-red)
      (number              . drought-grass-lighter)
      (constant            . salmon-tint)
      (regexp              . salmon-tint)
      (stand-out           . some-red)
      (trailing-whitespace . salmon-tint)

      (minibuffer-prompt . uranus))))

(deftheme rg-themes-custom
  "A night walk through the forest."
  :background-mode 'light
  :family 'rg)

(rg-themes-apply-palette-for 'rg-themes-custom 'rg-themes-custom-palette)

(provide-theme 'rg-themes-custom)

;;; rg-themes-bosque-theme.el ends here
