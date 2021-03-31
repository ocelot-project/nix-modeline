;;; nix-modeline.el --- Info about in-progress Nix evaluations on your modeline  -*- lexical-binding: t; -*-

;; Copyright (C) 2021 Jordan Mulcahey

;; Version: 1.0.0
;; Author: Jordan Mulcahey <snhjordy@gmail.com>
;; Description: Show in-progress Nix evaluations on your modeline
;; URL: https://github.com/ocelot-project/nix-modeline
;; Keywords: processes, unix, tools
;; Package-Requires: ((emacs "25.1"))

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

;; Displays the number of running Nix evaluations in the modeline.
;; Runs efficiently by using the `entr' command-line utility to watch
;; files that Nix updates on the start and completion of each
;; operation. Useful as the missing UI for Nix asynchronous build tools
;; like `lorri'.

;;; Code:

(eval-when-compile (require 'subr-x))

(defgroup nix-modeline nil
  "Display running Nix builders in the modeline."
  :group 'mode-line
  :group 'tools)

(defcustom nix-modeline-default-text " λ(?) "
  "The text for nix-modeline to display before its process starts."
  :type 'string)

(defcustom nix-modeline-idle-text " λ(✓) "
  "The text for nix-modeline to show when no builders are running."
  :type 'string)

(defcustom nix-modeline-running-text " λ⇒%s "
  "The text for nix-modeline to display when builders are running.

Note that a %s format specifier in this string will be replaced with the number
of Nix builders running."
  :type 'string)

(defcustom nix-modeline-error-text " λ(X) "
  "The text to display when nix-modeline's process crashes."
  :type 'string)

(defcustom nix-modeline-entr-command "entr"
  "The path to the entr command line utility.

Note that Nix substituteInPlace will edit this file to a correct path if
nix-modeline is built as a declarative elisp package."
  :type '(file :must-match t))

(defcustom nix-modeline-trigger-files '("/nix/var/nix/db/db.sqlite")
  "A list of files nix-modeline will monitor.

Changes to any of these files will cause nix-modeline to update, which forces a
modeline redisplay. The ideal files for this purpose should reliably be changed
only when Nix operations begin and end."
  :type '(repeat string))

(defcustom nix-modeline-users 'self
  "A symbol indicating which users' Nix builders should be tracked.

Usually, setting this variable only makes sense in multi-user Nix environments.

'self means to track only your own builders.
'self-and-root means your builders and those belonging to root get tracked.
'all means to track all of the builders on the system."
  :type '(choice (const :tag "Your User" 'self)
                 (const :tag "Your User and root" 'self-and-root)
                 (const :tag "All Users" 'all)))

(defcustom nix-modeline-process-regex "(nix-build)|(nix-instantiate)"
  "A regex of process names that should count as Nix builders.

nix-modeline passes this regex to pgrep and uses the number of matching
processes to report how many Nix builders are in progress."
  :type 'regexp)

(defcustom nix-modeline-pgrep-string (pcase system-type
                                       ('darwin "pgrep %s '%s' | wc -l")
                                       (_ "pgrep %s -c '%s'"))
  "The pgrep command line that nix-modeline should use.

Note: the first %s in this variable gets replaced by the value of
`nix-modeline--pgrep-users', and the second %s gets replaced by the value of
`nix-modeline-process-regex'."
  :type 'string)

(defcustom nix-modeline-delay 0.025
  "The delay between when nix-modeline triggers and when it updates.

This value is in seconds. Short (microsecond) delays help prevent race
conditions in nix-modeline during lengthy Nix builds."
  :type 'number)

(defcustom nix-modeline-hook nil
  "List of functions to be called when nix-modeline updates."
  :type 'hook)

(defface nix-modeline-idle-face
  '((t :inherit mode-line))
  "Face used when no Nix builders are running.")

(defface nix-modeline-running-face
  '((t :inherit homoglyph))
  "Face used when one or more Nix builders are running.")

(defface nix-modeline-error-face
  '((t :inherit warning))
  "Face used when nix-modeline's process crashes.")

(defvar nix-modeline--process nil
  "The process nix-modeline uses to monitor Nix build processes.")

(defvar nix-modeline--status-text ""
  "The string representing the current Nix builder status.")

(defun nix-modeline--update (num-builders)
  "Update nix-modeline's text and force redisplay all modelines.

NUM-BUILDERS is a string from the nix-modeline child process representing the
number of Nix builder processes it saw running."
  (setq nix-modeline--status-text (pcase num-builders
                                    (0 (propertize nix-modeline-idle-text
                                                   'face 'nix-modeline-idle-face))
                                    (n (propertize (format nix-modeline-running-text n)
                                                   'face 'nix-modeline-running-face))))
  (run-hooks 'nix-modeline-hook)
  (force-mode-line-update 'all))

(defun nix-modeline--callback (process output)
  "Update nix-modeline based on the OUTPUT of its PROCESS."
  (ignore process)
  (dolist (num-builders (split-string output nil 'omit-nulls))
    (nix-modeline--update (string-to-number num-builders))))

(defun nix-modeline--sentinel (process event)
  "Inspects EVENT, and alerts the user if nix-modeline's PROCESS crashes."
  (ignore event)
  (unless (process-live-p process)
    (setq nix-modeline--status-text (propertize nix-modeline-error-text
                                                'face 'nix-modeline-error-face))))

(defun nix-modeline--pgrep-users ()
  "Convert a nix-modeline users setting into a pgrep argument."
  (pcase nix-modeline-users
    ('self "-U $(id -u)")
    ('self-and-root "-U $(id -u) -U 0")
    ('all "")))

(defun nix-modeline--start-process ()
    "Start nix-modeline's Nix watcher process."
    (let ((process-connection-type nil))
      (setq nix-modeline--process (make-process
                                   :name "Nix Process Watcher"
                                   :buffer nil
                                   :command
                                   (list shell-file-name
                                         shell-command-switch
                                         (string-join
                                          (list
                                           "while [ true ]; do"
                                           "printf" (string-join
                                                     nix-modeline-trigger-files
                                                     "\\n")
                                           "|"
                                           nix-modeline-entr-command "-dns"
                                           (format "\"sleep %s; %s\""
                                                   nix-modeline-delay
                                                   (format
                                                    nix-modeline-pgrep-string
                                                    (nix-modeline--pgrep-users)
                                                    nix-modeline-process-regex))
                                                    "2>/dev/null"
                                                    "; done") " "))
                                   :filter 'nix-modeline--callback
                                   :sentinel 'nix-modeline--sentinel)))
    (set-process-query-on-exit-flag nix-modeline--process nil))

;;;###autoload
(define-minor-mode nix-modeline-mode
  "Displays the number of running Nix builders in the modeline."
  :global t :group 'nix-modeline
  (and nix-modeline--process
       (process-live-p nix-modeline--process)
       (delete-process nix-modeline--process))
  (setq nix-modeline--status-text "")
  (or global-mode-string (setq global-mode-string '("")))
  (cond
   (nix-modeline-mode
    (add-to-list 'global-mode-string '(t (:eval nix-modeline--status-text)) 'append)
    (setq nix-modeline--status-text (propertize nix-modeline-default-text
                                                'face 'nix-modeline-idle-face))
    (nix-modeline--start-process))
   (t
    (setq global-mode-string (remove '(t (:eval nix-modeline--status-text)) global-mode-string))
    (delete-process nix-modeline--process))))

(provide 'nix-modeline)
;;; nix-modeline.el ends here
