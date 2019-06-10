# Common Lisp reader for PostgreSQL custom dump files

This Common Lisp librairie implements a reader for PostgreSQL dump files.
This has been hacked together to make it possible for pgloader to work from
a Postgres dump directly.

The idea is to be able to load data from a pg_dump file into a target
database schema that might be different (from a source schema in the dump to
a different target schema in the target database), and to implement schema
changes on-the-fly when loading the data.

This CL lib only implements an API to read from a PostgreSQL dump file tho.

## API / Example usage

The API is not fixed at this time, and the project is meant to be used as a
lib from another Common Lisp project such as
<https://github.com/dimitri/pgloader>.

Here's an example usage though:

~~~ lisp
PGDUMPFILE> (let* ((dump (open-pgdump-file "/tmp/pgloader.dump"))
                   (e    (find 5125 (pgdump-entry-list dump) :key #'entry-dump-id))
                   (data (read-data dump e)))
              (values (subseq data 0 10) (length data)))
(("AL" "01" "00124" "Abbeville city") ("AL" "01" "00460" "Adamsville city")
 ("AL" "01" "00484" "Addison town") ("AL" "01" "00676" "Akron town")
 ("AL" "01" "00820" "Alabaster city") ("AL" "01" "00988" "Albertville city")
 ("AL" "01" "01132" "Alexander City city") ("AL" "01" "01180" "Alexandria CDP")
 ("AL" "01" "01228" "Aliceville city") ("AL" "01" "01396" "Allgood town"))
25375
~~~

How do we know about the dump id 5125 in our dump file would you ask?

We can search by object name, here the table name is _places_. This comes in
position 227 in the dump file, and the TABLE DATA entry is found later in
the Table of Contents.

~~~ lisp
PGDUMPFILE> (find "places" (pgdump-entry-list (open-pgdump-file "/tmp/pgloader.dump")) :test #'string= :key #'entry-tag)
#S(ENTRY :DUMP-ID 316 :DUMPER-P NIL :TABLE-OID "1259" :OID "457316"
         :TAG "places" :DESC "TABLE" :SECTION DATA
         :DEFN "CREATE TABLE public.places (
    usps character(2) NOT NULL,
    fips character(2) NOT NULL,
    fips_code character(5),
    \"LocationName\" character varying(64)
);
"
         :DROP-STATEMENT "DROP TABLE public.places;
"
         :COPY-STATEMENT "" :NAMESPACE "public" :TABLESPACE "" :OWNER "dim"
         :OIDS-P NIL :DEPENDENCIES NIL :DATA-STATE 3 :OFFSET 0)
         
PGDUMPFILE> (position "places" (pgdump-entry-list (open-pgdump-file "/tmp/pgloader.dump")) :test #'string= :key #'entry-tag)
227

PGDUMPFILE> (find "places" (pgdump-entry-list (open-pgdump-file "/tmp/pgloader.dump")) :test #'string= :key #'entry-tag :start 228)
#S(ENTRY :DUMP-ID 5125 :DUMPER-P T :TABLE-OID "0" :OID "457316" :TAG "places"
         :DESC "TABLE DATA" :SECTION POST-DATA :DEFN "" :DROP-STATEMENT ""
         :COPY-STATEMENT "COPY public.places (usps, fips, fips_code, \"LocationName\") FROM stdin;
"
         :NAMESPACE "public" :TABLESPACE "" :OWNER "dim" :OIDS-P NIL
         :DEPENDENCIES (316) :DATA-STATE 2 :OFFSET 2228051)
~~~

The TOC entry that contains the table definition has the tag TABLE, the
entry with the table data attached is tagged TABLE DATA.
