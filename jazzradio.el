;;; jazzradio.el --- jazzradio.com for Emacs -*- lexical-binding: t; -*-

;; Copyright (C) 2015 by Syohei YOSHIDA

;; Author: Syohei YOSHIDA <syohex@gmail.com>
;; URL: https://github.com/syohex/emacs-jazzradio
;; Version: 0.01
;; Package-Requires: ((emacs "24") (cl-lib "0.5"))

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;;; Code:

(require 'cl-lib)
(require 'json)

(defgroup jazzradio nil
  "Interface of `http://www.jazzradio.com/'."
  :group 'music)

(defface jazzradio-status
  '((t (:foreground "yellow")))
  "Face for highlighting query replacement matches."
  :group 'jazzradio)

(defconst jazzradio--channel-url
  "http://ephemeron:dayeiph0ne%40pp@api.audioaddict.com/v1/jazzradio/mobile/batch_update?stream_set_key=")

(defvar jazzradio--process nil)
(defvar jazzradio--channels-cache nil)

(cl-defstruct jazzradio-channel
  id key playlist name description status)

(defun jazzradio--parse-channels-response (response)
  (let* ((channel-filters (assoc-default 'channel_filters response))
         (channels (assoc-default 'channels (aref channel-filters 0))))
    (cl-loop for channel across channels
             for key = (assoc-default 'key channel)
             collect
             (make-jazzradio-channel
              :id (assoc-default 'id channel)
              :key key
              :playlist (concat "http://listen.jazzradio.com/webplayer/"
                                key ".pls")
              :name (assoc-default 'name channel)
              :description (assoc-default 'description channel)))))

(defun jazzradio--collect-channels ()
  (with-temp-buffer
    (unless (zerop (process-file "curl" nil t nil "-s" jazzradio--channel-url))
      (error "Can't get '%s'" jazzradio--channel-url))
    (let ((response (json-read-from-string
                     (buffer-substring-no-properties (point-min) (point-max)))))
      (jazzradio--parse-channels-response response))))

(defun jazzradio--read-channel (channels)
  (let ((channel-names (cl-loop for channel in channels
                                collect (jazzradio-channel-name channel))))
    (let ((name (completing-read "Channel: " channel-names nil t)))
      (cl-loop for channel in channels
               when (string= name (jazzradio-channel-name channel))
               return channel))))

(defun jazzradio--refresh ()
  (or jazzradio--channels-cache
      (let* ((channels (jazzradio--collect-channels))
             (entries (cl-loop for channel in channels
                               collect
                               (list channel
                                     `[,(jazzradio-channel-name channel)
                                       ""
                                       ,(jazzradio-channel-description channel)]))))
        (setq jazzradio--channels-cache entries)
        (setq tabulated-list-entries entries))))

(defsubst jazzradio--status-to-string (status)
  (cl-case status
    (play (if (char-displayable-p ?\u25B6) "   \u25B6   " "  Play  "))
    (pause (if (char-displayable-p ?\u258B) "  \u258B\u258B  " " Pause  "))
    (otherwise "")))

(defun jazzradio--update-status (channel status)
  (setf (jazzradio-channel-status channel) status)
  (setq tabulated-list-entries
        (cl-loop with this-channel = (jazzradio-channel-name channel)
                 for entry in tabulated-list-entries
                 for name = (jazzradio-channel-name (car entry))
                 if (string= this-channel name)
                 collect
                 (list channel
                       `[,this-channel
                         ,(propertize (jazzradio--status-to-string status)
                                      'face 'jazzradio-status)
                         ,(jazzradio-channel-description channel)])
                 else
                 collect
                 (let ((columns (cadr entry)))
                   (setf (aref columns 1) "")
                   entry))))

(defsubst jazzradio--play-playlist-url (channel)
  (start-file-process "jazzradio" nil
                      "mplayer" "-slave" "-really-quiet" "-playlist"
                      (jazzradio-channel-playlist channel)))

(defsubst jazzradio--playing-p (channel)
  (memq (jazzradio-channel-status channel) '(play pause)))

(defun jazzradio--current-playing-channel ()
  (cl-loop for entry in tabulated-list-entries
           for status = (jazzradio-channel-status (car entry))
           when (jazzradio--playing-p channel)
           return (car entry)))

(defun jazzradio--play ()
  (interactive)
  (let ((channel (tabulated-list-get-id)))
    (if (jazzradio--playing-p channel)
        (message "%s is playing now!!" (jazzradio-channel-name channel))
      (when jazzradio--process
        (if (not (y-or-n-p (format "Stop '%s' ?"
                                   (jazzradio-channel-name
                                    (jazzradio--current-playing-channel)))))
            (error "Cancel")
          (kill-process jazzradio--process)
          (setq jazzradio--process nil)))
      (let ((proc (jazzradio--play-playlist-url channel)))
        (setq jazzradio--process proc)
        (set-process-sentinel
         proc
         (lambda (process _event)
           (when (memq (process-status process) '(exit signal))
             (jazzradio--update-status channel nil)
             (message "finish: '%s'" (jazzradio-channel-name channel)))))
        (message "Play: '%s'" (jazzradio-channel-name channel))
        (jazzradio--update-status channel 'play)
        (tabulated-list-print t)))))

(defun jazzradio--stop ()
  (interactive)
  (let* ((channel (jazzradio--current-playing-channel))
         (name (jazzradio-channel-name channel)))
    (if (not (jazzradio--playing-p channel))
        (message "%s is not playing now" name)
      (when (y-or-n-p (format "Stop '%s' ?" name))
        (kill-process jazzradio--process)
        (jazzradio--update-status channel nil)
        (tabulated-list-print t)))))

(defsubst jazzradio--mplayer-send (cmd)
  (process-send-string jazzradio--process (concat cmd "\n")))

(defun jazzradio--toggle-pause ()
  (interactive)
  (let* ((channel (tabulated-list-get-id))
         (status (jazzradio-channel-status channel)))
    (if (not (jazzradio--playing-p channel))
        (message "%s is not playing now" (jazzradio-channel-name channel))
      (jazzradio--mplayer-send "pause")
      (cl-case status
        (play (jazzradio--update-status channel 'pause))
        (pause (jazzradio--update-status channel 'play)))
      (tabulated-list-print t))))

(defun jazzradio--volume-decrease ()
  (interactive)
  (jazzradio--mplayer-send "volume -1"))

(defun jazzradio--volume-increase ()
  (interactive)
  (jazzradio--mplayer-send "volume 1"))

(defvar jazzradio-menu-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map tabulated-list-mode-map)
    (define-key map (kbd "RET") 'jazzradio--play)
    (define-key map (kbd "U") 'jazzradio--stop)
    (define-key map (kbd "SPC") 'jazzradio--toggle-pause)
    (define-key map (kbd "9") 'jazzradio--volume-decrease)
    (define-key map (kbd "0") 'jazzradio--volume-increase)
    map)
  "Local keymap for `jazzradio-menu-mode' buffers.")

(defun jazzradio--channel-name-predicate (a b)
  (string< (jazzradio-channel-name (car a))
           (jazzradio-channel-name (car b))))

(define-derived-mode jazzradio-menu-mode tabulated-list-mode "JazzRadio"
  "jazzradio menu"
  (set (make-local-variable 'jazzradio--process) nil)
  (setq tabulated-list-format
        `[("Channel" 20 jazzradio--channel-name-predicate)
          ("Status" 8 nil)
          ("Description" 50 nil)])
  (setq tabulated-list-padding 2)
  (setq tabulated-list-sort-key (cons "Channel" nil))
  ;;(add-hook 'tabulated-list-revert-hook 'jazzradio--refresh nil t)
  (tabulated-list-init-header))

;;;###autoload
(defun jazzradio ()
  "Show channels menu."
  (interactive)
  (let ((buf (get-buffer-create "*jazzradio*")))
    (with-current-buffer buf
      (jazzradio--refresh)
      (jazzradio-menu-mode)
      (tabulated-list-print t)
      (switch-to-buffer buf))))

(provide 'jazzradio)

;;; jazzradio.el ends here
