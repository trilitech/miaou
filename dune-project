(lang dune 3.24)
(name miaou)
(version 0.6.1)
(generate_opam_files true)
(license MIT)
(source (github trilitech/miaou))

(package
 (name miaou-registry)
 (synopsis "Miaou widget registry (runtime discoverability + embedded mli)")
 (maintainers "Nomadic Labs <contact@nomadic-labs.com>")
 (authors "Nomadic Labs <contact@nomadic-labs.com>")
 (homepage "https://github.com/trilitech/miaou")
 (bug_reports "https://github.com/trilitech/miaou/issues")
 (depends (ocaml (>= 5.2))))

(package
 (name miaou-core)
 (synopsis "Miaou core/widgets (no drivers, no SDL)")
 (maintainers "Nomadic Labs <contact@nomadic-labs.com>")
 (authors "Nomadic Labs <contact@nomadic-labs.com>")
 (homepage "https://github.com/trilitech/miaou")
 (bug_reports "https://github.com/trilitech/miaou/issues")
  (depends
   (ocaml (>= 5.2))
   (miaou-registry (= :version))
   cohttp
   (cohttp-eio (>= 6.2.1))
   (eio (>= 1.0))
   (eio_main (>= 1.0))
   lambda-term
   rresult
   uri
   yojson
   ppx_deriving_yojson
   imagelib
   qrc
   (ppx_blob (>= 0.9.0))
   (ppx_forbid :build)
   (ppx_enforce :build)
   (alcotest :with-test)
   (bisect_ppx :with-test)))

(package
 (name miaou-driver-term)
 (synopsis "Miaou terminal driver")
 (maintainers "Nomadic Labs <contact@nomadic-labs.com>")
 (authors "Nomadic Labs <contact@nomadic-labs.com>")
 (homepage "https://github.com/trilitech/miaou")
 (bug_reports "https://github.com/trilitech/miaou/issues")
 (depends (miaou-core (= :version))))

(package
 (name miaou-driver-matrix)
 (synopsis "Miaou high-performance terminal driver with diff rendering")
 (maintainers "Nomadic Labs <contact@nomadic-labs.com>")
 (authors "Nomadic Labs <contact@nomadic-labs.com>")
 (homepage "https://github.com/trilitech/miaou")
 (bug_reports "https://github.com/trilitech/miaou/issues")
 (depends
  (miaou-core (= :version))
  (eio (>= 1.0))
  (eio_main (>= 1.0))))

(package
 (name miaou-widgets-display-sdl)
 (synopsis "Miaou SDL widget implementations")
 (maintainers "Nomadic Labs <contact@nomadic-labs.com>")
 (authors "Nomadic Labs <contact@nomadic-labs.com>")
 (homepage "https://github.com/trilitech/miaou")
 (bug_reports "https://github.com/trilitech/miaou/issues")
 (depends
  (miaou-core (= :version))
  tsdl))

(package
 (name miaou-driver-sdl)
 (synopsis "Miaou SDL driver")
 (maintainers "Nomadic Labs <contact@nomadic-labs.com>")
 (authors "Nomadic Labs <contact@nomadic-labs.com>")
 (homepage "https://github.com/trilitech/miaou")
 (bug_reports "https://github.com/trilitech/miaou/issues")
 (depends
  (miaou-core (= :version))
  (miaou-widgets-display-sdl (= :version))
  (miaou-driver-term (= :version))
  (miaou-driver-matrix (= :version))
  tsdl
  tsdl-ttf
  tsdl-image))

(package
 (name miaou-driver-web)
 (synopsis "Miaou web driver (xterm.js over WebSocket)")
 (maintainers "Nomadic Labs <contact@nomadic-labs.com>")
 (authors "Nomadic Labs <contact@nomadic-labs.com>")
 (homepage "https://github.com/trilitech/miaou")
 (bug_reports "https://github.com/trilitech/miaou/issues")
 (depends
  (miaou-core (= :version))
  (miaou-driver-matrix (= :version))
  (miaou-driver-term (= :version))
  digestif
  base64
  yojson
  (ppx_blob (>= 0.9.0))
  (eio (>= 1.0))
  (eio_main (>= 1.0))))

(package
 (name miaou-serve)
 (synopsis "Miaou serve: process-per-session supervisor exposing a MIAOU app over the network")
 (maintainers "Nomadic Labs <contact@nomadic-labs.com>")
 (authors "Nomadic Labs <contact@nomadic-labs.com>")
 (homepage "https://github.com/trilitech/miaou")
 (bug_reports "https://github.com/trilitech/miaou/issues")
 (depends
  (miaou-core (= :version))
  (miaou-driver-web (= :version))
  eqaf
  cstruct
  digestif
  (cmdliner (>= 1.3))
  (eio (>= 1.0))
  (eio_main (>= 1.0))
  (alcotest :with-test)
  (bisect_ppx :with-test)))

(package
 (name miaou-runner)
 (synopsis "Miaou runner with backend selection")
 (maintainers "Nomadic Labs <contact@nomadic-labs.com>")
 (authors "Nomadic Labs <contact@nomadic-labs.com>")
 (homepage "https://github.com/trilitech/miaou")
 (bug_reports "https://github.com/trilitech/miaou/issues")
 (depends
  (miaou-core (= :version))
  (miaou-driver-term (= :version))
  (miaou-driver-matrix (= :version))
  (eio (>= 1.0)))
 (depopts (miaou-driver-sdl (= :version))))

(package
 (name miaou-tui)
 (synopsis "Miaou TUI framework - terminal only (no SDL)")
 (maintainers "Nomadic Labs <contact@nomadic-labs.com>")
 (authors "Nomadic Labs <contact@nomadic-labs.com>")
 (homepage "https://github.com/trilitech/miaou")
 (bug_reports "https://github.com/trilitech/miaou/issues")
 (allow_empty)
 (depends
  (miaou-core (= :version))
  (miaou-driver-term (= :version))
  (miaou-runner (= :version))))

(package
 (name miaou)
 (synopsis "A TUI framework for OCaml (full install with SDL)")
 (maintainers "Nomadic Labs <contact@nomadic-labs.com>")
 (authors "Nomadic Labs <contact@nomadic-labs.com>")
 (homepage "https://github.com/trilitech/miaou")
 (bug_reports "https://github.com/trilitech/miaou/issues")
 (depends
  (miaou-core (= :version))
  (miaou-driver-term (= :version))
  (miaou-driver-web (= :version))
  (miaou-driver-sdl (= :version))
  (miaou-runner (= :version))
  (ppx_blob (>= 0.9.0))))
