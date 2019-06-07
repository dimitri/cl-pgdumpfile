;;;
;;; PostgreSQL custom dump reader
;;;

(in-package #:pgdumpfile)

;;;
;;; Some Postgres pg_dump and pg_restore constants to read the dump files.
;;;

(defconstant +magic+ "PGDMP")
(defconstant +min-ver+ '(1 12 0))
(defconstant +formats+ '(unknown custom files tar null directory))
(defconstant +sections+ '(none pre-data data post-data))

(defconstant +block-data+ #x01)
(defconstant +block-blobs+ #x03)
(defconstant +eof+ -1)

(defconstant +k-offset-pos-not-set+ 1)
(defconstant +k-offset-pos-set+ 2)
(defconstant +k-offset-no-data+ 3)

(defconstant +zlib-out-size+ 4096)
(defconstant +zlib-in-size+ 4096)

(defparameter *external-format* :utf-8)


;;;
;;; Data Structures in which to expose the internal objects of a Postgres dump.
;;;
;;; A Postgres dump has a Table-Of-Contents which is a list of entries. Each
;;; entry is a SQL object with a definition and a drop statement. When it's
;;; a table it also has a COPY statement that contains the table contents.
;;;
(defstruct entry
  dump-id dumper-p table-oid oid tag desc section defn
  drop-statement copy-statement namespace tablespace owner
  oids-p dependencies data-state offset)

(defstruct header
  version-major version-minor version-revision integer-size offset-size format)

(defstruct pgdump path header compressed-p timestamp dbname
           server-version pgdump-version entry-list)

(defun open-pgdump-file (pathname)
  (let* ((dump (make-instance 'pgdump :path pathname)))
    (with-open-file (stream pathname
                            :direction :input
                            :element-type '(unsigned-byte 8))
      (read-header-magic stream)
      (let* ((version-major    (read-byte stream))
             (version-minor    (read-byte stream))
             (version-revision (read-byte stream))
             (integer-size     (read-byte stream))
             (offset-size      (read-byte stream))
             (format           (read-byte stream))
             (compressed-p     (/= 0 (read-signed-integer stream integer-size)))
             (timestamp        (read-timestamp stream integer-size))
             (dbname           (read-string stream integer-size))
             (server-version   (read-string stream integer-size))
             (pgdump-version   (read-string stream integer-size))
             (entries-count    (read-signed-integer stream integer-size))
             (entry-list
              (loop :repeat entries-count
                 :collect (read-toc-entry stream integer-size offset-size))))
        (assert
         (every #'<=
                +min-ver+
                (list version-major version-minor version-revision)))
        (setf (pgdump-header dump)
              (make-instance 'header
                             :version-major version-major
                             :version-minor version-minor
                             :version-revision version-revision
                             :integer-size integer-size
                             :offset-size offset-size
                             :format (nth format +formats+)))
        (setf (pgdump-compressed-p dump)   compressed-p
              (pgdump-timestamp dump)      timestamp
              (pgdump-dbname dump)         dbname
              (pgdump-server-version dump) server-version
              (pgdump-pgdump-version dump) pgdump-version
              (pgdump-entry-list dump)     entry-list)))
    dump))

(defmethod print-toc ((dump pgdump) &optional (stream t))
  (format stream "~&;")
    (multiple-value-bind
          (second minute hour date month year day-of-week dst-p tz)
        (decode-universal-time (pgdump-timestamp dump))
      (declare (ignore day-of-week dst-p tz))
      (format stream
              "~&; Archive created at ~d-~2,'0d-~2,'0d ~2,'0d:~2,'0d:~2,'0d"
              year month date hour minute second))
    (format stream "~&;     dbname: ~a" (pgdump-dbname dump))
    (format stream "~&;     TOC entries: ~a" (length (pgdump-entry-list dump)))
    (format stream "~&;     Compression: ~a" (pgdump-compressed-p dump))
    (print-toc (pgdump-header dump) stream)
    (format stream
            "~&;     Dumped from database version: ~a"
            (pgdump-server-version dump))
    (format stream
            "~&;     Dumped by pg_dump version: ~a"
            (pgdump-pgdump-version dump))
    (format stream "~&;")
    (format stream "~&;")
    (format stream "~&; Selected TOC Entries:")
    (format stream "~&;")

    (loop :for entry :in (pgdump-entry-list dump)
       :do (print-toc entry stream))

    (terpri stream))

(defmethod print-toc ((header header) &optional (stream t))
  (format stream "~&;     Dump version: ~a.~a-~a"
          (header-version-major header)
          (header-version-minor header)
          (header-version-revision header))
  (format stream "~&;     Format: ~a" (header-format header))
  (format stream "~&;     Integer: ~a bytes" (header-integer-size header))
  (format stream "~&;     Offset: ~a bytes" (header-offset-size header)))

(defmethod print-toc ((entry entry) &optional (stream t))
  (format stream
          "~&~a; ~a ~a ~a ~:[-~*~;~a~] ~a ~a"
          (entry-dump-id entry)
          (entry-table-oid entry)
          (entry-oid entry)
          (entry-desc entry)
          (entry-namespace entry)
          (entry-namespace entry)
          (entry-tag entry)
          (entry-owner entry)))


;;;
;;; Postgres dump file elements reader
;;;
(defun read-header-magic (stream)
  "First 5 bytes of a Postgres dump file are PGDMP."
  (let* ((magic (make-array 5 :element-type '(unsigned-byte 8))))
    (read-sequence magic stream)
    (assert (string= +magic+ (map 'string #'code-char magic)))
    +magic+))

(defun read-toc-entry (stream integer-size offset-size)
  "Read a Table of Content entry for the given dump."
  (let* ((dump-id      (read-signed-integer stream integer-size))
         (dumper-p     (/= 0 (read-signed-integer stream integer-size)))
         (table-oid    (read-string stream integer-size))
         (oid          (read-string stream integer-size))
         (tag          (read-string stream integer-size))
         (desc         (read-string stream integer-size))
         (section      (nth (read-signed-integer stream integer-size) +sections+))
         (defn         (read-string stream integer-size))
         (drop-stmt    (read-string stream integer-size))
         (copy-stmt    (read-string stream integer-size))
         (namespace    (read-string stream integer-size))
         (tablespace   (read-string stream integer-size))
         (owner        (read-string stream integer-size))
         (oids-p       (string= "true" (read-string stream integer-size)))
         (dependencies (read-dependencies stream integer-size))
         (data-state   (read-byte stream))
         (offset       (read-offset stream offset-size)))
    (make-instance 'entry
                   :dump-id dump-id
                   :dumper-p dumper-p
                   :table-oid table-oid
                   :oid oid
                   :tag tag
                   :desc desc
                   :section section
                   :defn defn
                   :drop-statement drop-stmt
                   :copy-statement copy-stmt
                   :namespace namespace
                   :tablespace tablespace
                   :owner owner
                   :oids-p oids-p
                   :dependencies dependencies
                   :data-state data-state
                   :offset offset)))

(defun read-dependencies (stream integer-size)
  "Read an array of OIDs that the current TOC entry depends on."
  (loop :for id := (read-string stream integer-size)
     :while (and id (not (string= "" id)))
     :collect (parse-integer id)))


;;;
;;; Utility functions
;;;
(defun read-signed-integer (stream size)
  "Read a signed integer from the PostgreSQL custom binary format."
  (let ((sign (read-byte stream))
        (value
         (loop :for offset :below size
            :for shift :from 0 :by 8
            :sum (let ((byte (logand (read-byte stream) #xff)))
                   (if (= 0 byte) 0 (ash byte shift))))))
    (if (/= 0 sign) (- value) value)))

(defun read-offset (stream offset-size)
  (loop
     :for value := 0 :then (logior value (ash byte (* 8 offset)))
     :for offset :below offset-size
     :for byte := (read-byte stream)
     :finally (return value)))

(defun skip-data (stream integer-size)
  "Skip data from current position in stream.

    Data blocks are formatted as an integer length, followed by data.
    A zero length denoted the end of the block."
  (loop :for block-size := (read-signed-integer stream integer-size)
     :until (zerop block-size)
     :do (file-position stream (+ (file-position stream) block-size))))

(defun read-string (stream integer-size)
  "String size is the first byte, then we convert bytes to *external-format*."
  (let* ((size  (read-signed-integer stream integer-size)))
    (if (< 0 size)
        (let ((bytes (make-array size :element-type '(unsigned-byte 8))))
          (read-sequence bytes stream)
          (babel:octets-to-string bytes :encoding *external-format*))
        ;; when size is zero or less, then we return an empty string
        "")))

(defun read-timestamp (stream integer-size)
  "Read a Postgres dump timestamp"
  (let ((seconds (read-signed-integer stream integer-size))
        (minutes (read-signed-integer stream integer-size))
        (hour    (read-signed-integer stream integer-size))
        (day     (read-signed-integer stream integer-size))
        (month   (+ 1 (read-signed-integer stream integer-size)))
        (year    (+ 1900 (read-signed-integer stream integer-size)))
        (tz      (read-signed-integer stream integer-size)))
    (encode-universal-time seconds minutes hour day month year tz)))
