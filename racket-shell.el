;;; racket-shell.el -*- lexical-binding: t -*-

;; Copyright (c) 2022 by Greg Hendershott.
;; Portions Copyright (C) 1985-1986, 1999-2013 Free Software Foundation, Inc.

;; Author: Greg Hendershott
;; URL: https://github.com/greghendershott/racket-mode

;; License:
;; This is free software; you can redistribute it and/or modify it
;; under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version. This is distributed in the hope that it will be
;; useful, but without any warranty; without even the implied warranty
;; of merchantability or fitness for a particular purpose. See the GNU
;; General Public License for more details. See
;; http://www.gnu.org/licenses/ for details.

(require 'racket-custom)
(require 'racket-util)
(require 'shell)
(require 'term)

(defun racket-racket ()
  "Use command-line racket to run the file.

Uses a shell or terminal buffer as specified by the configuration
variable `racket-shell-or-terminal-function'."
  (interactive)
  (racket--shell-or-terminal
   (concat (shell-quote-argument (racket--buffer-file-name)))))

(defun racket-raco-test ()
  "Use command-line raco test to run the \"test\" submodule.

Uses a shell or terminal buffer as specified by the configuration
variable `racket-shell-or-terminal-function'."
  (interactive)
  (racket--shell-or-terminal
   (concat "-l raco test -x "
           (shell-quote-argument (racket--buffer-file-name)))))

(defun racket--shell-or-terminal (args)
  (racket--save-if-changed)
  (let* ((exe (shell-quote-argument
               (if (file-name-absolute-p racket-program)
                   (expand-file-name racket-program) ;handle e.g. ~/
                 racket-program)))
         (cmd (concat exe " " args))
         (win (selected-window)))
    (funcall racket-shell-or-terminal-function cmd)
    (select-window win)))

(defun racket-shell (cmd)
  (let ((buf (shell)))
    (comint-simple-send buf cmd)))

(defun racket-term (cmd)
  (let ((buf (term (or explicit-shell-file-name
                       (getenv "ESHELL")
                       (getenv "SHELL")
                       "/bin/sh"))))
    (term-simple-send buf cmd)))

(defun racket-ansi-term (cmd)
  (let ((buf (ansi-term (or explicit-shell-file-name
                            (getenv "ESHELL")
                            (getenv "SHELL")
                            "/bin/sh"))))
    (term-simple-send buf cmd)))

(declare-function vterm "ext:vterm")
(declare-function vterm-send-return "ext:vterm")
(declare-function vterm-send-string "ext:vterm")

(defun racket-vterm (cmd)
  (unless (require 'vterm nil 'noerror)
    (error "Package 'vterm' is not available"))
  (vterm)
  (vterm-send-string cmd)
  (vterm-send-return))

(provide 'racket-shell)

;; racket-shell.el ends here
