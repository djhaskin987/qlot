(in-package :cl-user)
(defpackage qlot.source.ql
  (:use :cl
        :qlot.source)
  (:import-from :qlot.http
                :safety-http-request)
  (:import-from :qlot.util
                :find-qlfile
                :with-package-functions)
  (:import-from :function-cache
                :defcached)
  (:export :source-ql))
(in-package :qlot.source.ql)

(defclass source-ql (source)
  ((%version :initarg :%version)))

(defclass source-ql-all (source) ())

(defmethod make-source ((source (eql 'source-ql)) &rest args)
  (destructuring-bind (project-name version) args
    (if (eq project-name :all)
        (make-instance 'source-ql-all
                       :project-name "quicklisp"
                       :version version)
        (make-instance 'source-ql
                       :project-name project-name
                       :%version version))))

(defmethod freeze-source ((source source-ql))
  (format nil "ql ~A ~A"
          (source-project-name source)
          (source-ql-version source)))

(defmethod freeze-source ((source source-ql-all))
  (format nil "ql :all ~A"
          (source-ql-version source)))

(defmethod print-object ((source source-ql) stream)
  (with-slots (project-name %version) source
    (format stream "#<~S ~A ~A>"
            (type-of source)
            (if (stringp project-name)
                project-name
                (prin1-to-string project-name))
            (if (stringp %version)
                %version
                (prin1-to-string %version)))))

(defmethod prepare ((source source-ql))
  (setf (source-version source)
        (format nil "ql-~A" (source-ql-version source))))

(defcached ql-latest-version ()
  (let ((stream (safety-http-request "http://beta.quicklisp.org/dist/quicklisp.txt"
                                     :want-stream t)))
    (or
     (loop for line = (read-line stream nil nil)
           while line
           when (string= (subseq line 0 9) "version: ")
             do (return (subseq line 9)))
     (error "Failed to get the latest version of Quicklisp."))))

(defun retrieve-quicklisp-releases (version)
  (safety-http-request (format nil "http://beta.quicklisp.org/dist/quicklisp/~A/releases.txt"
                               version)
                       :want-stream t))

(defun retrieve-quicklisp-systems (version)
  (safety-http-request (format nil "http://beta.quicklisp.org/dist/quicklisp/~A/systems.txt"
                               version)
                       :want-stream t))

(defun source-ql-releases (source)
  (with-slots (project-name) source
    (let* ((version (source-ql-version source))
           (body (retrieve-quicklisp-releases version)))
      (loop with len = (1+ (length project-name))
            with str = (concatenate 'string project-name " ")
            for line = (read-line body nil nil)
            while line
            when (string= (subseq line 0 len) str)
              do (return (ppcre:split "\\s+" line))
            finally
               (error "~S doesn't exist in quicklisp ~A."
                      project-name
                      version)))))

(defun source-ql-systems (source)
  (with-slots (project-name) source
    (let* ((version (source-ql-version source))
           (body (retrieve-quicklisp-systems version)))
      (loop with len = (1+ (length project-name))
            with str = (concatenate 'string project-name " ")
            for line = (read-line body nil nil)
            while line
            when (string= (subseq line 0 len) str)
              collect (ppcre:split "\\s+" line)))))

(defgeneric source-ql-version (source)
  (:method ((source source-ql))
    (with-slots (%version) source
      (if (eq %version :latest)
          (ql-latest-version)
          %version)))
  (:method ((source source-ql-all))
    (with-slots (version) source
      (if (eq version :latest)
          (ql-latest-version)
          version))))

(defmethod distinfo.txt ((source source-ql))
  (format nil "name: ~A
version: ~A
system-index-url: ~A~A
release-index-url: ~A~A
archive-base-url: http://beta.quicklisp.org/
canonical-distinfo-url: ~A~A
distinfo-subscription-url: ~A~A
"
          (source-project-name source)
          (source-version source)
          *dist-base-url* (url-path-for source 'systems.txt)
          *dist-base-url* (url-path-for source 'releases.txt)
          *dist-base-url* (url-path-for source 'distinfo.txt)
          *dist-base-url* (url-path-for source 'project.txt)))

(defmethod systems.txt ((source source-ql))
  (format nil "# project system-file system-name [dependency1..dependencyN]
~{~{~A~^ ~}~%~}"
          (source-ql-systems source)))

(defmethod releases.txt ((source source-ql))
  (format nil "# project url size file-md5 content-sha1 prefix [system-file1..system-fileN]
~{~A~^ ~}
"
          (source-ql-releases source)))

(defmethod url-path-for ((source source-ql-all) (for (eql 'project.txt)))
  (with-slots (version) source
    (if (eq version :latest)
        "http://beta.quicklisp.org/dist/quicklisp.txt"
        (format nil "http://beta.quicklisp.org/dist/quicklisp/~A/distinfo.txt" version))))

(defmethod install-source ((source source-ql-all))
  ;; do nothing.
  nil)
