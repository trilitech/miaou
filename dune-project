(lang dune 3.12)
(name miaou)
(version 0.1.0)
(generate_opam_files true)
(license MIT)

(package
 (name miaou)
 (synopsis "A TUI framework for OCaml")
 (maintainers "Nomadic Labs <contact@nomadic-labs.com>")
 (authors "Nomadic Labs <contact@nomadic-labs.com>")
 (homepage "https://gitlab.com/mbourgoin/miaou")
 (bug_reports "https://gitlab.com/mbourgoin/miaou/-/issues")
 (depends
  cohttp
  cohttp-lwt-unix
  lambda-term
  lwt
  rresult
  uri
  yojson
  (alcotest :with-test)))
