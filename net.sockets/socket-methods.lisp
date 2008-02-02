;;;; -*- Mode: Lisp; Syntax: ANSI-Common-Lisp; Indent-tabs-mode: NIL -*-
;;;
;;; socket-methods.lisp --- Various socket methods.
;;;
;;; Copyright (C) 2006-2008, Stelian Ionescu  <sionescu@common-lisp.net>
;;;
;;; This code is free software; you can redistribute it and/or
;;; modify it under the terms of the version 2.1 of
;;; the GNU Lesser General Public License as published by
;;; the Free Software Foundation, as clarified by the
;;; preamble found here:
;;;     http://opensource.franz.com/preamble.html
;;;
;;; This program is distributed in the hope that it will be useful,
;;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;;; GNU General Public License for more details.
;;;
;;; You should have received a copy of the GNU Lesser General
;;; Public License along with this library; if not, write to the
;;; Free Software Foundation, Inc., 51 Franklin St, Fifth Floor,
;;; Boston, MA 02110-1301, USA

(in-package :net.sockets)

(defvar *socket-type-map*
  '(((:ipv4  :stream   :active  :default) . socket-stream-internet-active)
    ((:ipv6  :stream   :active  :default) . socket-stream-internet-active)
    ((:ipv4  :stream   :passive :default) . socket-stream-internet-passive)
    ((:ipv6  :stream   :passive :default) . socket-stream-internet-passive)
    ((:local :stream   :active  :default) . socket-stream-local-active)
    ((:local :stream   :passive :default) . socket-stream-local-passive)
    ((:local :datagram :active  :default) . socket-datagram-local-active)
    ((:ipv4  :datagram :active  :default) . socket-datagram-internet-active)
    ((:ipv6  :datagram :active  :default) . socket-datagram-internet-active)))

;;; FIXME: should match :default to whatever protocol is the default.
(defun select-socket-class (family type connect protocol)
  (or (cdr (assoc (list family type connect protocol) *socket-type-map*
                  :test #'equal))
      (error "No socket class found !!")))

;;;; Shared Initialization

(defun translate-make-socket-keywords-to-constants (family type protocol)
  (let ((sf (ecase family
              (:ipv4  af-inet)
              (:ipv6  af-inet6)
              (:local af-local)))
        (st (ecase type
              (:stream   sock-stream)
              (:datagram sock-dgram)))
        (sp (cond
              ((integerp protocol) protocol)
              ((eq :default protocol) 0)
              (t (lookup-protocol protocol)))))
    (values sf st sp)))

(defmethod socket-fd ((socket socket))
  (fd-of socket))

(defmethod (setf socket-fd) (fd (socket socket))
  (setf (fd-of socket) fd))

(defmethod initialize-instance :after ((socket socket) &key
                                       file-descriptor family type
                                       (protocol :default))
  (with-accessors ((fd fd-of) (fam socket-family) (proto socket-protocol))
      socket
    (setf fd (or file-descriptor
                 (multiple-value-call #'%socket
                   (translate-make-socket-keywords-to-constants
                    family type protocol))))
    (setf fam family
          proto protocol)))

(defmethod (setf external-format-of) (external-format (socket passive-socket))
  (setf (slot-value socket 'external-format)
        (babel:ensure-external-format external-format)))

(defmethod initialize-instance :after ((socket passive-socket)
                                       &key external-format)
  (setf (external-format-of socket) external-format))

(defmethod socket-type ((socket stream-socket))
  :stream)

(defmethod socket-type ((socket datagram-socket))
  :datagram)

;;;; Printing

(defun sock-fam (socket)
  (ecase (socket-family socket)
    (:ipv4 "IPv4")
    (:ipv6 "IPv6")))

(defmethod print-object ((socket socket-stream-internet-active) stream)
  (print-unreadable-object (socket stream :identity t)
    (format stream "active ~A stream socket" (sock-fam socket))
    (if (socket-connected-p socket)
        (multiple-value-bind (addr port) (remote-name socket)
          (format stream " connected to ~A/~A"
                  (address-to-string addr) port))
        (format stream ", ~:[closed~;unconnected~]" (fd-of socket)))))

(defmethod print-object ((socket socket-stream-internet-passive) stream)
  (print-unreadable-object (socket stream :identity t)
    (format stream "passive ~A stream socket" (sock-fam socket))
    (if (socket-bound-p socket)
        (multiple-value-bind (addr port) (local-name socket)
          (format stream " ~:[bound to~;waiting @~] ~A/~A"
                  (socket-listening-p socket)
                  (address-to-string addr) port))
        (format stream ", ~:[closed~;unbound~]" (fd-of socket)))))

(defmethod print-object ((socket socket-stream-local-active) stream)
  (print-unreadable-object (socket stream :identity t)
    (format stream "active local stream socket")
    (if (socket-connected-p socket)
        (format stream " connected to ~S"
                (address-to-string (remote-address socket)))
        (format stream ", ~:[closed~;unconnected~]" (fd-of socket)))))

(defmethod print-object ((socket socket-stream-local-passive) stream)
  (print-unreadable-object (socket stream :identity t)
    (format stream "passive local stream socket")
    (if (socket-bound-p socket)
        (format stream " ~:[bound to~;waiting @~] ~S"
                  (socket-listening-p socket)
                  (address-to-string (local-address socket)))
        (format stream ", ~:[closed~;unbound~]" (fd-of socket)))))

(defmethod print-object ((socket socket-datagram-local-active) stream)
  (print-unreadable-object (socket stream :identity t)
    (format stream "local datagram socket")
    (if (socket-connected-p socket)
        (format stream " connected to ~S"
                (address-to-string (remote-address socket)))
        (if (fd-of socket)
            (format stream " waiting @ ~S" (address-to-string (local-address socket)))
            (format stream ", closed" )))))

(defmethod print-object ((socket socket-datagram-internet-active) stream)
  (print-unreadable-object (socket stream :identity t)
    (format stream "~A datagram socket" (sock-fam socket))
    (if (socket-connected-p socket)
        (multiple-value-bind (addr port) (remote-name socket)
          (format stream " connected to ~A/~A"
                  (address-to-string addr) port))
        (if (fd-of socket)
            (multiple-value-bind (addr port) (local-name socket)
              (format stream " waiting @ ~A/~A"
                      (address-to-string addr) port))
            (format stream ", closed" )))))

;;;; CLOSE

(defmethod close :around ((socket socket) &key abort)
  (declare (ignore abort))
  (call-next-method)
  (when (fd-of socket)
    (nix:close (fd-of socket)))
  (setf (fd-of socket) nil
        (slot-value socket 'bound) nil)
  (values socket))

(defmethod close :around ((socket passive-socket) &key abort)
  (declare (ignore abort))
  (call-next-method)
  (setf (slot-value socket 'listening) nil)
  (values socket))

(defmethod close ((socket socket) &key abort)
  (declare (ignore socket abort)))

(defmethod socket-open-p ((socket socket))
  (when (fd-of socket)
    (with-sockaddr-storage (ss)
      (with-socklen (size size-of-sockaddr-storage)
        (handler-case
            (%getsockname (fd-of socket) ss size)
          (nix:ebadf () nil)
          (nix:econnreset () nil)
          (:no-error (_) (declare (ignore _)) t))))))

;;;; GETSOCKNAME

(defmethod local-name ((socket socket))
  (with-sockaddr-storage (ss)
    (with-socklen (size size-of-sockaddr-storage)
      (%getsockname (fd-of socket) ss size)
      (sockaddr-storage->sockaddr ss))))

(defmethod local-address ((socket socket))
  (nth-value 0 (local-name socket)))

(defmethod local-port ((socket internet-socket))
  (nth-value 1 (local-name socket)))

;;;; GETPEERNAME

(defmethod remote-name ((socket socket))
  (with-sockaddr-storage (ss)
    (with-socklen (size size-of-sockaddr-storage)
      (%getpeername (fd-of socket) ss size)
      (sockaddr-storage->sockaddr ss))))

(defmethod remote-address ((socket socket))
  (nth-value 0 (remote-name socket)))

(defmethod remote-port ((socket internet-socket))
  (nth-value 1 (remote-name socket)))

;;;; BIND

(defmethod bind-address :before ((socket internet-socket) address
                                 &key (reuse-address t))
  (declare (ignore address))
  (when reuse-address
    (setf (socket-option socket :reuse-address) t)))

(defun bind-ipv4-address (fd address port)
  (with-sockaddr-in (sin address port)
    (%bind fd sin size-of-sockaddr-in)))

(defun bind-ipv6-address (fd address port)
  (with-sockaddr-in6 (sin6 address port)
    (%bind fd sin6 size-of-sockaddr-in6)))

(defmethod bind-address ((socket internet-socket) (address ipv4-address)
                         &key (port 0))
  (if (eq :ipv6 (socket-family socket))
      (bind-ipv6-address (fd-of socket)
                         (map-ipv4-vector-to-ipv6 (address-name address))
                         port)
      (bind-ipv4-address (fd-of socket) (address-name address) port))
  (values socket))

(defmethod bind-address ((socket internet-socket) (address ipv6-address)
                         &key (port 0))
  (bind-ipv6-address (fd-of socket) (address-name address) port)
  (values socket))

(defmethod bind-address ((socket local-socket) (address local-address) &key)
  (with-sockaddr-un (sun (address-name address))
      (%bind (fd-of socket) sun size-of-sockaddr-un))
  (values socket))

(defmethod bind-address :after ((socket socket) (address address) &key)
  (setf (slot-value socket 'bound) t))

;;;; LISTEN

(defmethod socket-listen ((socket passive-socket) &key backlog)
  (unless backlog (setf backlog (min *default-backlog-size*
                                     +max-backlog-size+)))
  (check-type backlog unsigned-byte "a non-negative integer")
  (%listen (fd-of socket) backlog)
  (setf (slot-value socket 'listening) t)
  (values socket))

(defmethod socket-listen ((socket active-socket) &key)
  (error "You can't listen on active sockets."))

;;;; ACCEPT

(defmethod accept-connection ((socket active-socket) &key)
  (error "You can't accept connections on active sockets."))

(defmethod accept-connection ((socket passive-socket) &key external-format
                              input-buffer-size output-buffer-size)
  (flet ((make-client-socket (fd)
           (make-instance (active-class socket)
                          :file-descriptor fd
                          :external-format (or external-format
                                               (external-format-of socket))
                          :input-buffer-size input-buffer-size
                          :output-buffer-size output-buffer-size)))
    (with-sockaddr-storage (ss)
      (with-socklen (size size-of-sockaddr-storage)
        (handler-case
            (make-client-socket (%accept (fd-of socket) ss size))
          (nix:ewouldblock ()))))))

;;;; CONNECT

#+freebsd
(defmethod connect :before ((socket active-socket) sockaddr &key)
  (declare (ignore sockaddr))
  (setf (socket-option socket :no-sigpipe) t))

(defun ipv4-connect (fd address port)
  (with-sockaddr-in (sin address port)
    (%connect fd sin size-of-sockaddr-in)))

(defun ipv6-connect (fd address port)
  (with-sockaddr-in6 (sin6 address port)
    (%connect fd sin6 size-of-sockaddr-in6)))

(defmethod connect ((socket internet-socket) (address ipv4-address)
                    &key (port 0))
  (if (eq :ipv6 (socket-family socket))
      (ipv6-connect (fd-of socket)
                    (map-ipv4-vector-to-ipv6 (address-name address))
                    port)
      (ipv4-connect (fd-of socket) (address-name address) port))
  (values socket))

(defmethod connect ((socket internet-socket) (address ipv6-address)
                    &key (port 0))
  (ipv6-connect (fd-of socket) (address-name address) port)
  (values socket))

(defmethod connect ((socket local-socket) (address local-address) &key)
  (with-sockaddr-un (sun (address-name address))
    (%connect (fd-of socket) sun size-of-sockaddr-un))
  (values socket))

(defmethod connect ((socket passive-socket) address &key)
  (declare (ignore address))
  (error "You cannot connect passive sockets."))

(defmethod socket-connected-p ((socket socket))
  (when (fd-of socket)
    (with-sockaddr-storage (ss)
      (with-socklen (size size-of-sockaddr-storage)
        (handler-case
            (%getpeername (fd-of socket) ss size)
          (socket-not-connected-error () nil)
          (:no-error (_) (declare (ignore _)) t))))))

;;;; SHUTDOWN

(defmethod shutdown ((socket socket) &key read write)
  (assert (or read write) (read write)
          "You must select at least one direction to shut down.")
  (%shutdown (fd-of socket)
             (multiple-value-case (read write)
               ((_   nil) shut-rd)
               ((nil _)   shut-wr)
               (t         shut-rdwr)))
  (values socket))

;;;; SENDTO

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defun compute-flags (flags args)
    (loop :with flag-combination := 0
          :for cons :on args :by #'cddr
          :for flag := (car cons)
          :for val := (cadr cons)
          :for const := (cdr (assoc flag flags))
          :when const :do
       (when (not (constantp val)) (return-from compute-flags))
       (setf flag-combination (logior flag-combination const))
       :finally (return flag-combination)))

  (defmacro define-socket-flag (place name value platform)
    (let ((val (cond ((or (not platform)
                          (featurep platform)) value)
                     ((not (featurep platform)) 0))))
      `(push (cons ,name ,val) ,place))))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defparameter *sendmsg-flags* nil)

  (defmacro define-sendmsg-flags (&rest forms)
    (flet ((dflag (form)
             (destructuring-bind (name value &optional platform) form
               `(define-socket-flag *sendmsg-flags* ,name ,value ,platform))))
      `(progn
         ,@(mapcar #'dflag forms))))

  (define-sendmsg-flags
    (:end-of-record msg-eor       (:not :windows))
    (:dont-route    msg-dontroute)
    (:dont-wait     msg-dontwait  (:not :windows))
    (:no-signal     msg-nosignal  (:not (:or :darwin :windows)))
    (:out-of-band   msg-oob)
    (:more          msg-more      :linux)
    (:confirm       msg-confirm   :linux)))

(defun %normalize-send-buffer (buff start end ef)
  (check-bounds buff start end)
  (etypecase buff
    (ub8-sarray (values buff start (- end start)))
    (ub8-vector (values (coerce buff 'ub8-sarray)
                        start (- end start)))
    (string     (values (%to-octets buff ef start end)
                        0 (- end start)))
    (vector (values (coerce buff 'ub8-sarray)
                    start (- end start)))))

(defun %send-to (socket buffer start end remote-address remote-port flags)
  (when (typep socket 'passive-socket)
    (error "You cannot send data on a passive socket."))
  (when remote-address (setf remote-address (ensure-hostname remote-address)))
  (when remote-port (setf remote-port (ensure-numerical-service remote-port)))
  (when (and (ipv4-address-p remote-address)
             (eq :ipv6 (socket-family socket)))
    (setf remote-address (map-ipv4-address-to-ipv6 remote-address)))
  (multiple-value-bind (buff start-offset bufflen)
      (%normalize-send-buffer buffer start end (external-format-of socket))
    (with-sockaddr-storage (ss)
      (when remote-address
        (sockaddr->sockaddr-storage ss remote-address remote-port))
      (with-pointer-to-vector-data (buff-sap buff)
        (incf-pointer buff-sap start-offset)
        (%sendto (fd-of socket) buff-sap bufflen flags
                 (if remote-address ss (null-pointer))
                 (if remote-address size-of-sockaddr-storage 0))))))

(defmethod send-to ((socket active-socket) buffer &rest args
                    &key (start 0) end remote-address (remote-port 0) (ipv6 *ipv6*))
  (let ((*ipv6* ipv6))
    (%send-to socket buffer start end remote-address remote-port
              (compute-flags *sendmsg-flags* args))))

(define-compiler-macro send-to (&whole form socket buffer &rest args
                                &key (start 0) end remote-address (remote-port 0)
                                (ipv6 '*ipv6* ipv6p))
  (let ((flags (compute-flags *sendmsg-flags* args)))
    (cond (flags (if ipv6p
                     `(let ((*ipv6* ,ipv6))
                        (%send-to ,socket ,buffer ,start ,end
                                  ,remote-address ,remote-port ,flags))
                     `(%send-to ,socket ,buffer ,start ,end
                                ,remote-address ,remote-port ,flags)))
          (t form))))

;;;; RECVFROM

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defparameter *recvfrom-flags* nil)

  (defmacro define-recvfrom-flags (&rest forms)
    (flet ((dflag (form)
             (destructuring-bind (name value &optional platform) form
               `(define-socket-flag *recvfrom-flags* ,name ,value ,platform))))
      `(progn
         ,@(mapcar #'dflag forms))))

  (define-recvfrom-flags
    (:out-of-band msg-oob)
    (:peek        msg-peek)
    (:wait-all    msg-waitall  (:not :windows))
    (:dont-wait   msg-dontwait (:not :windows))
    (:no-signal   msg-nosignal (:not (:or :darwin :windows)))))

(defun %normalize-receive-buffer (buff start end)
  (check-bounds buff start end)
  (etypecase buff
    (ub8-sarray (values buff start (- end start)))))

(defun %socket-receive-bytes (fd buffer start end flags ss)
  (multiple-value-bind (buff start-offset bufflen)
      (%normalize-receive-buffer buffer start end)
    (with-socklen (size size-of-sockaddr-storage)
      (bzero ss size-of-sockaddr-storage)
      (with-pointer-to-vector-data (buff-sap buff)
        (incf-pointer buff-sap start-offset)
        (%recvfrom fd buff-sap bufflen flags ss size)))))

(declaim (inline %receive-from-stream-socket))
(defun %receive-from-stream-socket (socket buffer start end flags)
  (with-sockaddr-storage (ss)
    (let ((bytes-received (%socket-receive-bytes (fd-of socket) buffer
                                                 start end flags ss)))
      (values buffer bytes-received))))

(declaim (inline %receive-from-datagram-socket))
(defun %receive-from-datagram-socket (socket buffer start end flags)
  (with-sockaddr-storage (ss)
    (let ((bytes-received (%socket-receive-bytes (fd-of socket) buffer
                                                 start end flags ss)))
      (multiple-value-bind (remote-address remote-port)
          (sockaddr-storage->sockaddr ss)
        (values buffer bytes-received remote-address remote-port)))))

(defun %receive-from (socket buffer start end size flags)
  (unless buffer
    (check-type size unsigned-byte "a non-negative integer")
    (setf buffer (make-array size :element-type 'ub8)
          start 0 end size))
  (etypecase socket
    (stream-socket (%receive-from-stream-socket socket buffer start end flags))
    (datagram-socket (%receive-from-datagram-socket socket buffer start end flags))))

(defmethod receive-from ((socket active-socket) &rest args
                         &key buffer size (start 0) end)
  (%receive-from socket buffer start end size
                 (compute-flags *recvfrom-flags* args)))

(define-compiler-macro receive-from (&whole form socket &rest args
                                     &key buffer size (start 0) end)
  (let ((flags (compute-flags *recvfrom-flags* args)))
    (cond (flags `(%receive-from ,socket ,buffer ,start ,end ,size ,flags))
          (t form))))

;;;; Datagram Sockets

(defmethod disconnect :before ((socket active-socket))
  (unless (typep socket 'datagram-socket)
    (error "You can only disconnect active datagram sockets.")))

(defmethod disconnect ((socket datagram-socket))
  (with-foreign-object (sin 'sockaddr-in)
    (bzero sin size-of-sockaddr-in)
    (setf (foreign-slot-value sin 'sockaddr-in 'addr) af-unspec)
    (%connect (fd-of socket) sin size-of-sockaddr-in)))