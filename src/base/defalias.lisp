;;;; -*- Mode: Lisp; indent-tabs-mode: nil -*-
;;;
;;; --- Creating aliases in CL namespaces
;;;

(in-package :iolib.base)

(defvar *namespaces* nil)

(defmacro defalias (alias original)
  (destructuring-bind (namespace new-name &optional args)
      alias
    (assert (member namespace *namespaces*) (namespace)
            "Namespace ~A does not exist" namespace)
    (make-alias namespace original new-name args)))

(defmacro defnamespace (namespace &optional docstring)
  (check-type namespace symbol)
  (check-type docstring (or null string))
  `(progn
     (pushnew ',namespace *namespaces*)
     (handler-bind ((warning #'muffle-warning))
       (setf (documentation ',namespace 'namespace) ,docstring))))

(defgeneric make-alias (namespace original alias args))

(defnamespace function
  "The namespace of ordinary and generic functions.")

(defmethod make-alias ((namespace (eql 'function))
                       original alias args)
  `(defun ,alias ,args
     (,original ,@args)))

(defnamespace macro
  "The namespace of macros.")

(defmethod make-alias ((namespace (eql 'macro))
                       original alias args)
  (alexandria:with-gensyms (args)
    `(setf (macro-function ',alias)
           (lambda (&rest ,args)
             (apply (macro-function ',original) ,args)))))

(defnamespace special
  "The namespace of special variables.")

(defmethod make-alias ((namespace (eql 'special))
                       original alias args)
  `(define-symbol-macro ,alias ,original))

(defnamespace constant
  "The namespace of special variables.")

(defmethod make-alias ((namespace (eql 'constant))
                       original alias args)
  `(define-symbol-macro ,alias ,original))
