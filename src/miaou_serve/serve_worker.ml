(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

module Fibers = Miaou_helpers.Fiber_runtime

let env_var = "MIAOU_SERVE_WORKER_SOCKET"

(* Orphan guard: the supervisor hands us the read end of a pipe and keeps
   the write end open for as long as it (and its Eio switch) is alive.
   If the supervisor dies — crash, kill -9, anything — the write end
   closes and this read loop observes End_of_file. A worker whose
   supervisor is gone is unreapable garbage (nothing else knows its
   socket path or is waiting on its exit status), so it must exit
   itself rather than linger. *)
let watch_stdin_orphan_guard (env : Eio_unix.Stdenv.base) =
  Eio.Fiber.fork ~sw:(Fibers.require_current_switch ()) (fun () ->
      let buf = Cstruct.create 256 in
      let rec loop () =
        match Eio.Flow.single_read env#stdin buf with
        | (_ : int) -> loop ()
        | exception End_of_file ->
            Printf.eprintf
              "[miaou serve worker] stdin closed (supervisor gone); exiting\n%!" ;
            exit 1
      in
      try loop () with
      | End_of_file ->
          Printf.eprintf
            "[miaou serve worker] stdin closed (supervisor gone); exiting\n%!" ;
          exit 1
      | Eio.Io _ ->
          (* Not every host process gives the worker a pipe-backed stdin
             (e.g. a stub/test harness that never spawns via
             {!Serve_supervisor}) — treat that as "no orphan guard
             available" rather than a fatal error. *)
          ())

let run ~socket_path (page : (module Miaou_core.Tui_page.PAGE_SIG)) : unit =
  (* FR-072: applied before anything else in the worker's own execution —
     before the Eio event loop even starts — so the self-imposed limit
     covers as much of the worker's lifetime as possible. *)
  Serve_rlimit.apply_from_env () ;
  Eio_main.run @@ fun env ->
  Eio.Switch.run @@ fun sw ->
  Fibers.init ~env ~sw ;
  watch_stdin_orphan_guard env ;
  Printf.eprintf "[miaou serve worker] listening on unix:%s\n%!" socket_path ;
  ignore
    (Miaou_driver_web.Web_driver.run_on ~listen:(`Unix socket_path) page
      : [`Quit | `Back | `SwitchTo of string])
