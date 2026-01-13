(lang dune 3.15)
(name miaou)
(version 0.1.1)
(generate_opam_files true)
(license MIT)

(package
 (name miaou-core)
 (synopsis "Miaou core/widgets (no drivers, no SDL)")
 (maintainers "Nomadic Labs <contact@nomadic-labs.com>")
 (authors "Nomadic Labs <contact@nomadic-labs.com>")
 (homepage "https://github.com/trilitech/miaou")
 (bug_reports "https://github.com/trilitech/miaou/issues")
 (depends
  cohttp
  cohttp-eio
  eio
  eio_main
  lambda-term
  rresult
  uri
  yojson
  imagelib
  qrc
  ppx_blob
  (alcotest :with-test)
  (bisect_ppx :with-test)))

(package
 (name miaou-driver-term)
 (synopsis "Miaou terminal driver")
 (maintainers "Nomadic Labs <contact@nomadic-labs.com>")
 (authors "Nomadic Labs <contact@nomadic-labs.com>")
 (homepage "https://github.com/trilitech/miaou")
 (bug_reports "https://github.com/trilitech/miaou/issues")
 (depends miaou-core))

(package
 (name miaou-driver-matrix)
 (synopsis "Miaou high-performance terminal driver with diff rendering")
 (maintainers "Nomadic Labs <contact@nomadic-labs.com>")
 (authors "Nomadic Labs <contact@nomadic-labs.com>")
 (homepage "https://github.com/trilitech/miaou")
 (bug_reports "https://github.com/trilitech/miaou/issues")
 (depends
  miaou-core
  eio
  eio_main))

(package
 (name miaou-widgets-display-sdl)
 (synopsis "Miaou SDL widget implementations")
 (maintainers "Nomadic Labs <contact@nomadic-labs.com>")
 (authors "Nomadic Labs <contact@nomadic-labs.com>")
 (homepage "https://github.com/trilitech/miaou")
 (bug_reports "https://github.com/trilitech/miaou/issues")
 (depends
  miaou-core
  tsdl))

(package
 (name miaou-driver-sdl)
 (synopsis "Miaou SDL driver")
 (maintainers "Nomadic Labs <contact@nomadic-labs.com>")
 (authors "Nomadic Labs <contact@nomadic-labs.com>")
 (homepage "https://github.com/trilitech/miaou")
 (bug_reports "https://github.com/trilitech/miaou/issues")
 (depends
  miaou-core
  miaou-widgets-display-sdl
  miaou-driver-term
  miaou-driver-matrix
  tsdl
  tsdl-ttf
  tsdl-image))

(package
 (name miaou-runner)
 (synopsis "Miaou runner with backend selection")
 (maintainers "Nomadic Labs <contact@nomadic-labs.com>")
 (authors "Nomadic Labs <contact@nomadic-labs.com>")
 (homepage "https://github.com/trilitech/miaou")
 (bug_reports "https://github.com/trilitech/miaou/issues")
 (depends miaou-core miaou-driver-term miaou-driver-matrix)
 (depopts miaou-driver-sdl))

(package
 (name miaou-tui)
 (synopsis "Miaou TUI framework - terminal only (no SDL)")
 (maintainers "Nomadic Labs <contact@nomadic-labs.com>")
 (authors "Nomadic Labs <contact@nomadic-labs.com>")
 (homepage "https://github.com/trilitech/miaou")
 (bug_reports "https://github.com/trilitech/miaou/issues")
 (allow_empty)
 (depends
  miaou-core
  miaou-driver-term
  miaou-runner))

(package
 (name miaou)
 (synopsis "A TUI framework for OCaml (full install with SDL)")
 (maintainers "Nomadic Labs <contact@nomadic-labs.com>")
 (authors "Nomadic Labs <contact@nomadic-labs.com>")
 (homepage "https://github.com/trilitech/miaou")
 (bug_reports "https://github.com/trilitech/miaou/issues")
 (depends
  miaou-core
  miaou-driver-term
  miaou-driver-sdl
  miaou-runner))
