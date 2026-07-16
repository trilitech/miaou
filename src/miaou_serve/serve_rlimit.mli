(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(** Per-worker OS resource limits, applied by the worker itself at
    worker-mode entry (FR-072).

    {b Why this shells out instead of calling [Unix.setrlimit]}: OCaml's
    stdlib [Unix] module has no [setrlimit] binding (verified against
    this project's pinned compiler: [grep -i rlimit
    _opam/lib/ocaml/unix/unix.mli] has zero hits). Adding one would mean
    either a new opam dependency (e.g. [extunix], not otherwise used by
    this codebase) or a from-scratch C stub library — both a
    disproportionate amount of new build surface (an opam dep, or a C
    compiler + header-portability dependency across Linux/macOS/BSD) for
    one defense-in-depth knob, and this project's own process notes flag
    that new not-always-present dependencies here have already caused a
    CI incident once. Instead, this module invokes the POSIX/util-linux
    [prlimit(1)] command-line utility against the worker's own pid
    ([Unix.getpid ()]): [prlimit --pid <self> --as=N:N] adjusts a
    *running* process's own limit in place — functionally identical to a
    self-[setrlimit] call, no re-exec, no new file descriptors, no new
    build-time dependency (a runtime tool lookup, not an opam package).

    {b Platform caveat}: [prlimit(1)] is a Linux (util-linux) tool; it is
    not present on macOS/BSD by default. If it is missing, or the call
    otherwise fails, {!apply_from_env} logs a warning to stderr and
    continues — a missing defense-in-depth backstop must never itself
    become a denial-of-service for a legitimate session. *)

(** Environment variable: if set to a positive integer, the worker caps
    its own virtual address space (RLIMIT_AS) at that many megabytes
    (soft limit = hard limit). {b Choose this generously above the
    expected resident set}: RLIMIT_AS bounds total *virtual* address
    space, not resident memory, and OCaml's runtime (particularly
    OCaml 5's multicore minor/major heap allocation strategy) reserves
    address space in bulk ahead of what is actually touched — setting
    this close to a measured RSS figure risks aborting an otherwise
    healthy worker with a spurious allocation failure. If this caveat is
    a concern for a given deployment, prefer {!env_var_cpu_seconds}
    alone, which has no such interaction. *)
val env_var_as_mb : string

(** Environment variable: if set to a positive integer, the worker caps
    its own total CPU time (RLIMIT_CPU) at that many seconds (soft =
    hard). Unaffected by the RLIMIT_AS/OCaml-heap caveat above. *)
val env_var_cpu_seconds : string

(** [apply_from_env ()] reads both environment variables above and
    applies whichever are set (best-effort — never raises; a
    missing/failing [prlimit] is logged and otherwise ignored, per the
    platform caveat). Call once, as early as possible at worker-mode
    entry, before the app has had a chance to allocate meaningfully.
    A value that is present but not a positive integer is logged and
    ignored (fails safe, not silently). *)
val apply_from_env : unit -> unit
