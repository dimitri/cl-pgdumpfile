# Common Lisp reader for PostgreSQL custom dump files

This Common Lisp librairie implements a reader for PostgreSQL dump files.
This has been hacked together to make it possible for pgloader to work from
a Postgres dump directly.

The idea is to be able to load data from a pg_dump file into a target
database schema that might be different (from a source schema in the dump to
a different target schema in the target database), and to implement schema
changes on-the-fly when loading the data.

This CL lib only implements an API to read from a PostgreSQL dump file tho.
