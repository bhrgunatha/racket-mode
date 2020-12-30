;;; racket-logger.el -*- lexical-binding: t; -*-

;; Copyright (c) 2013-2020 by Greg Hendershott.
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

(require 'easymenu)
(require 'rx)
(require 'racket-custom)
(require 'racket-repl)

;; Need to define this before racket-logger-mode
(defvar racket-logger-mode-map
  (racket--easy-keymap-define
   '(("l"       racket-logger-topic-level)
     ("w"       toggle-truncate-lines)
     ("n"       racket-logger-next-item)
     ("p"       racket-logger-previous-item)
     ("g"       racket-logger-clear))))

(easy-menu-define racket-logger-mode-menu racket-logger-mode-map
  "Menu for Racket logger mode."
  '("Racket-Logger"
    ["Configure Topic and Level" racket-logger-topic-level]
    ["Toggle Truncate Lines" toggle-truncate-lines]
    "---"
    ["Clear" racket-logger-clear]))

(define-derived-mode racket-logger-mode special-mode "Racket-Logger"
  "Major mode for Racket logger output.
\\<racket-logger-mode-map>

The customization variable `racket-logger-config' determines the
levels for topics. During a session you may change topic levels
using `racket-logger-topic-level'.

For more information see:
  <https://docs.racket-lang.org/reference/logging.html>

\\{racket-logger-mode-map}
"
  (setq-local font-lock-defaults nil)
  (setq-local truncate-lines t)
  (setq-local buffer-undo-list t) ;disable undo
  (setq-local window-point-insertion-type t)
  (setq buffer-invisibility-spec nil)
  (racket--logger-configure-depth-faces))

(defconst racket--logger-buffer-name "*Racket Logger*")

(defun racket--logger-get-buffer-create ()
  "Create buffer if necessary. Do not display or select it."
  (unless (get-buffer racket--logger-buffer-name)
    (with-current-buffer (get-buffer-create racket--logger-buffer-name)
      (racket-logger-mode)
      (racket--logger-activate-config)))
  (get-buffer racket--logger-buffer-name))

(defun racket--logger-on-notify (v)
 (when noninteractive ;emacs --batch
    (princ (format "{racket logger}: %s" v)))
  (with-current-buffer (racket--logger-get-buffer-create)
    (let* ((inhibit-read-only  t)
           (original-point     (point))
           (point-was-at-end-p (equal original-point (point-max))))
      (goto-char (point-max))
      (racket--logger-insert v)
      (unless point-was-at-end-p
        (goto-char original-point)))))

(cl-defstruct racket-logger
  depth caller context msec thread)

(cl-defstruct racket-trace
  callp tailp name show identifier formals header)

(defun racket--logger-insert (v)
  (pcase-let*
      ((`(,level ,topic ,message ,depth ,caller ,context ,msec ,thread ,tracing) v)
       (logger-prop (make-racket-logger
                     :depth   depth
                     :caller  (racket--logger-srcloc-beg+end caller)
                     :context (racket--logger-srcloc-beg+end context)
                     :msec    msec
                     :thread  thread))
       ;; Possibly more things if tracing
       (`(,callp ,tailp ,trace-prop)
        (pcase tracing
          (`(,call ,tail ,name ,show ,identifier ,formals ,header)
           (list call
                 tail
                 (make-racket-trace
                  :callp      call
                  :tailp      tail
                  :name       name
                  :show       show
                  :identifier (racket--logger-srcloc-line+col identifier)
                  :formals    (racket--logger-srcloc-beg+end formals)
                  :header     (racket--logger-srcloc-beg+end header))))))
       (prefix (if trace-prop
                   (if callp
                       (if tailp
                           "⤑ "
                         "↘ ")
                     "   ⇒ ")
                 "")))
    (insert (racket--logger-level->string level))
    (insert (racket--logger-topic->string topic))

    ;; For an "inset boxes" effect, we start the line by
    ;; drawing a space for each parent level, in its background
    ;; color.
    (cl-loop for n to (1- depth)
             do
             (insert
              (propertize
               "  "
               'face          `(:inherit ,(racket--logger-depth-face-name n))
               'racket-logger logger-prop
               'racket-trace  trace-prop)))
    ;; Finally draw the interesting information for this line.
    ;; We insert several separately-propertized strings because
    ;; some are "fields" that need their own face and
    ;; 'invisible property.
    (let ((inherit `(:inherit ,(racket--logger-depth-face-name depth))))
      (insert
       (concat
        (propertize (concat prefix (racket--logger-limit-string message
                                                                4096))
                    'face          inherit
                    'racket-logger logger-prop
                    'racket-trace  trace-prop
                    'invisible     thread)
        (when thread
          (propertize (format "  %s" thread)
                      'face          `(,@inherit
                                       :height 0.8)
                      'racket-logger logger-prop
                      'racket-trace  trace-prop
                      'invisible     thread))
        (when msec
          (propertize (format "  %s" msec)
                      'face          `(,@inherit
                                       :height 0.8)
                      'racket-logger logger-prop
                      'racket-trace  trace-prop
                      'invisible     thread))
        (propertize "\n"
                    'face          inherit
                    'racket-logger logger-prop
                    'racket-trace  trace-prop
                    'invisible     thread))))))

(defun racket--logger-topic->string (topic)
  (propertize (concat (substring topic 0 (min (length topic) 15))
                      (make-string (max 0 (- 15 (length topic))) ?\ )
                      " ")
              'face racket-logger-topic-face
              'invisible 'topic))

(defun racket--logger-level->string (level)
  (case level
    ('fatal   (propertize "[  fatal] "
                          'face racket-logger-fatal-face
                          'invisible 'level))
    ('error   (propertize "[  error] "
                          'face racket-logger-error-face
                          'invisible 'level))
    ('warning (propertize "[warning] "
                          'face racket-logger-warning-face
                          'invisbile 'level))
    ('info    (propertize "[   info] "
                          'face racket-logger-info-face
                          'invisible 'level))
    ('debug   (propertize "[  debug] "
                          'face racket-logger-debug-face
                          'invisible 'level))))

;;; srclocs

(defun racket--logger-srcloc-line+col (v)
  "Extract the line and col from a srcloc."
  (pcase v
    (`(,path ,line ,col ,_pos ,_span)
     `(,path ,line ,col))))

(defun racket--logger-srcloc-beg+end (v)
  "Extract the pos and span from a srcloc and convert to beg and end."
  (pcase v
    (`(,path ,_line ,_col ,pos ,span)
     `(,path ,pos ,(+ pos span)))))

;;; Depth faces

(defface racket-logger-even-depth-face '((t (:inherit default)))
  "Face for even depths. Calculated from theme. Not for user customization."
  :group 'racket-faces)
(defface racket-logger-odd-depth-face '((t (:inherit default)))
  "Face for odd depths. Calculated from theme. Not for user customization."
  :group 'racket-faces)

(defun racket--logger-configure-depth-faces (&rest _ignored)
  (let ((bg   (face-background 'default))
        (sign (if (eq 'dark (frame-parameter nil 'background-mode)) 1 -1)))
    (set-face-background 'racket-logger-even-depth-face
                         (color-lighten-name bg (* 5 sign)))
    (set-face-background 'racket-logger-odd-depth-face
                         (color-lighten-name bg (* 10 sign)))))

(advice-add 'load-theme    :after #'racket--logger-configure-depth-faces)
(advice-add 'disable-theme :after #'racket--logger-configure-depth-faces)

(defun racket--logger-depth-face-name (depth)
  (if (cl-evenp depth)
      'racket-logger-even-depth-face
    'racket-logger-odd-depth-face))

(defun racket--logger-depth-background (depth)
  `(:background ,(face-background (racket--logger-depth-face-name depth))))

;;; Logger topic configuration

(defun racket--logger-activate-config ()
  "Send config to logger and display it in the buffer."
  (racket--cmd/async nil
                     `(logger ,racket-logger-config))
  (with-current-buffer (get-buffer-create racket--logger-buffer-name)
    (let ((inhibit-read-only t))
      (goto-char (point-max))
      (insert (propertize (concat "racket-logger-config:"
                                  (let ((print-length nil)
                                        (print-level nil))
                                    (pp-to-string racket-logger-config)))
                          'face racket-logger-config-face))
      (goto-char (point-max)))))

(defun racket--logger-set (topic level)
  (unless (symbolp topic) (error "TOPIC must be symbolp"))
  (unless (symbolp level) (error "LEVEL must be symbolp"))
  (pcase (assq topic racket-logger-config)
    (`() (add-to-list 'racket-logger-config (cons topic level)))
    (v   (setcdr v level)))
  (racket--logger-activate-config))

(defun racket--logger-unset (topic)
  (unless (symbolp topic) (error "TOPIC must be symbolp"))
  (when (eq topic '*)
    (user-error "Cannot unset the level for the '* topic"))
  (setq racket-logger-config
        (assq-delete-all topic racket-logger-config))
  (racket--logger-activate-config))

(defun racket--logger-topics ()
  "Effectively (sort (dict-keys racket-logger-config))."
  (sort (mapcar (lambda (x) (format "%s" (car x)))
                racket-logger-config)
        #'string<))

(defun racket--logger-topic-level (topic not-found)
  "Effectively (dict-ref racket-logger-config topic not-found)."
  (or (cdr (assq topic racket-logger-config))
      not-found))

;;; commands

(defun racket-logger ()
  "Select the `racket-logger-mode' buffer in a bottom side window."
  (interactive)
  (select-window
   (display-buffer-in-side-window (racket--logger-get-buffer-create)
                                  '((side . bottom)
                                    (slot . 1)
                                    (window-height . 15)))))

(defun racket-logger-clear ()
  "Clear the buffer and reconnect."
  (interactive)
  (when (y-or-n-p "Clear buffer? ")
    (let ((inhibit-read-only t))
      (delete-region (point-min) (point-max)))
    (racket--logger-activate-config)))

(defconst racket--logger-item-rx
  (rx bol ?\[ (0+ space) (or "fatal" "error" "warning" "info" "debug") ?\] space))

(defun racket-logger-next-item (&optional count)
  "Move point N items forward.

An \"item\" is a line starting with a log level in brackets.

Interactively, N is the numeric prefix argument.
If N is omitted or nil, move point 1 item forward."
  (interactive "P")
  (forward-char 1)
  (if (re-search-forward racket--logger-item-rx nil t count)
      (beginning-of-line)
    (backward-char 1)))

(defun racket-logger-previous-item (&optional count)
  "Move point N items backward.

An \"item\" is a line starting with a log level in brackets.

Interactively, N is the numeric prefix argument.
If N is omitted or nil, move point 1 item backward."
  (interactive "P")
  (re-search-backward racket--logger-item-rx nil t count))

(defun racket-logger-topic-level ()
  "Set or unset the level for a topic.

For convenience, input choices using `ido-completing-read'.

The topic labeled \"*\" is the level to use for all topics not
specifically assigned a level.

The level choice \"*\" means the topic will no longer have its
own level, therefore will follow the level specified for the
\"*\" topic."
  (interactive)
  (let* ((topic  (ido-completing-read
                  "Topic: "
                  (racket--logger-topics)))
         (topic  (pcase topic
                   ("" "*")
                   (v  v)))
         (topic  (intern topic))
         (levels (list "fatal" "error" "warning" "info" "debug"))
         (levels (if (eq topic '*) levels (cons "*" levels)))
         (level  (ido-completing-read
                  (format "Level for topic `%s': " topic)
                  levels
                  nil t nil nil
                  (format "%s" (racket--logger-topic-level topic "*"))))
         (level  (pcase level
                   (""  nil)
                   ("*" nil)
                   (v   (intern v)))))
    (if level
        (racket--logger-set topic level)
      (racket--logger-unset topic))))

;; TODO: Refine this limiting
(defun racket--logger-limit-string (str &optional max)
  (let ((max (or max 80))
        (len (length str)))
    (if (< len max)
        str
      (concat (substring str 0 (min len (- max 3)))
              "..."))))

(provide 'racket-logger)

;;; racket-logger.el ends here
