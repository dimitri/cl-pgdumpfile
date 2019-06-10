;;;; pgdump.asd

(asdf:defsystem #:pgdumpfile
  :serial t
  :description "PostgreSQL custom dump format reader utility"
  :author "Dimitri Fontaine <dim@tapoueh.org>"
  :license "WTFPL"
  :depends-on (#:babel
               #:chipz
               #:split-sequence)
  :components ((:file "package")
	       (:file "pgdumpfile")))
