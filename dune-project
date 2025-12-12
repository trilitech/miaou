(lang dune 3.15)
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
  cohttp-eio
  eio
  eio_main
  lambda-term
  tsdl
  tsdl-ttf
  rresult
 uri
 yojson
 imagelib
 qrc
 (alcotest :with-test)
 (bisect_ppx :with-test)))

(package
 (name miaou-core)
 (synopsis "Miaou core/widgets (no drivers)")
 (depends miaou)
 (allow_empty true))

(package
 (name miaou-driver-term)
 (synopsis "Miaou terminal driver")
 (depends miaou-core)
 (allow_empty true))

(package
 (name miaou-driver-sdl)
 (synopsis "Miaou SDL driver")
 (depends 
  miaou-core
  tsdl
  tsdl-ttf
  tsdl-image)
 (allow_empty true))

(package
 (name miaou-runner)
 (synopsis "Miaou runner with backend selection")
 (depends miaou-core miaou-driver-term miaou-driver-sdl)
 (allow_empty true))
