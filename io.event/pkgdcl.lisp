;;;; -*- Mode: Lisp; Syntax: ANSI-Common-Lisp; Indent-tabs-mode: NIL -*-
;;;
;;; pkgdcl.lisp --- Package definition.
;;;
;;; Copyright (C) 2007, Stelian Ionescu  <sionescu@common-lisp.net>
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

(in-package :common-lisp-user)

(defpackage :io.event
  (:nicknames #:evie)
  (:use #:common-lisp :io.streams :io.multiplex :net.sockets)
  (:export
   ;; Transports
   #:io-channel
   #:io-buffered-channel
   #:socket-transport
   #:tcp-transport
   #:udp-transport

   #:on-transport-readable
   #:on-transport-writable
   #:on-transport-error

   ;; Protocols
   #:io-protocol
   #:stream-protocol
   #:datagram-protocol
   #:protocol-debug-mixin

   #:transport-of
   #:on-protocol-start
   #:on-procotol-stop
   #:on-connection-made
   #:on-connection-lost
   #:on-connection-end
   #:on-data-received
   #:on-datagram-received

   ;; Event Managers
   #:event-manager
   #:protocol-manager-mixin
   #:server
   #:tcp-server
   #:client

   ;; Event Loop
   #:event-loop
   #:listen-tcp
   ))