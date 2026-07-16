(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(* Plain-Eio module: no Miaou_helpers.Fiber_runtime, no Miaou_core.Registry,
   no Miaou_core.Modal_manager, no Domain.spawn. Single-domain by
   construction — this is the supervisor half of the process-per-session
   design; the worker (Serve_worker) is where the full app runtime lives. *)

exception Bind_refused of string

let dir_prefix = "miaou-serve-"

let socket_root () =
  match Sys.getenv_opt "XDG_RUNTIME_DIR" with
  | Some d when d <> "" -> d
  | _ -> Filename.get_temp_dir_name ()

let socket_dir ~pid =
  Filename.concat (socket_root ()) (dir_prefix ^ string_of_int pid)

let ensure_socket_dir dir =
  match Unix.mkdir dir 0o700 with
  | () -> ()
  | exception Unix.Unix_error (Unix.EEXIST, _, _) ->
      (* A directory already existing at this (pid-derived) path should
         be rare — only a recycled pid colliding with a stale leftover —
         but on the shared, world-writable [$TMPDIR] fallback (when
         [$XDG_RUNTIME_DIR] is unset) a pre-existing entry at a
         guessable path could also be planted by another local user
         (TOCTOU/symlink risk: reusing it, or blindly chmod'ing it,
         would let that entry become our "private" socket directory).
         Verify it is a real directory we own before reusing it;
         otherwise fail closed rather than silently proceeding. *)
      let st = Unix.lstat dir in
      if st.Unix.st_kind <> Unix.S_DIR then
        failwith
          (Printf.sprintf
             "miaou serve: refusing to reuse %s: not a directory (possible \
              symlink)"
             dir)
      else if st.Unix.st_uid <> Unix.getuid () then
        failwith
          (Printf.sprintf
             "miaou serve: refusing to reuse %s: owned by a different user"
             dir)
      else Unix.chmod dir 0o700

(* Best-effort: does a pid still refer to a live process? Conservative on
   any answer other than a definite "no" (ESRCH) — we would rather leave
   a stale directory around an extra cycle than delete a live worker's
   socket directory out from under it because of an ambiguous errno. *)
let is_pid_alive pid =
  match Unix.kill pid 0 with
  | () -> true
  | exception Unix.Unix_error (Unix.ESRCH, _, _) -> false
  | exception Unix.Unix_error _ -> true

(* Best-effort startup hygiene: earlier supervisor invocations that were
   killed abruptly (kill -9, host reboot survivors on a persistent
   $TMPDIR, etc.) leave their [miaou-serve-<pid>/] directory behind,
   since only a clean exit runs {!cleanup_dir}. Sweep dead-pid entries
   under our own root before creating this run's directory. Never
   raises — any failure here just means one fewer stale directory
   removed this time, not a startup failure. *)
let sweep_stale_dirs () =
  let root = socket_root () in
  match Sys.readdir root with
  | entries ->
      let plen = String.length dir_prefix in
      Array.iter
        (fun name ->
          if String.length name > plen && String.sub name 0 plen = dir_prefix
          then
            match
              int_of_string_opt
                (String.sub name plen (String.length name - plen))
            with
            | Some pid when pid <> Unix.getpid () && not (is_pid_alive pid) -> (
                let dir = Filename.concat root name in
                (try
                   Array.iter
                     (fun f ->
                       try Sys.remove (Filename.concat dir f) with _ -> ())
                     (Sys.readdir dir)
                 with _ -> ()) ;
                try Unix.rmdir dir with _ -> ())
            | _ -> ())
        entries
  | exception _ -> ()

(* Best-effort teardown of this run's own socket directory: remove the
   worker's socket file (in case the worker was killed abruptly and
   never got to clean up its own listening socket) and the now-empty
   directory. Never raises. *)
let cleanup_dir ~dir ~socket_path () =
  (try Sys.remove socket_path with _ -> ()) ;
  try Unix.rmdir dir with _ -> ()

type worker = {
  pid : int;
  socket_path : string;
  await : unit -> Eio.Process.exit_status;
  signal : int -> unit;
}

let spawn_worker ~sw ~proc_mgr ~socket_path () =
  let stdin_r, _stdin_w = Eio.Process.pipe ~sw proc_mgr in
  let env =
    Array.append
      (Unix.environment ())
      [|Serve_worker.env_var ^ "=" ^ socket_path|]
  in
  let argv = Array.to_list Sys.argv in
  let proc =
    Eio.Process.spawn
      ~sw
      proc_mgr
      ~executable:Sys.executable_name
      ~stdin:stdin_r
      ~env
      argv
  in
  (* Our copy of the read end is only needed to hand to the child; the
     child has its own (dup'd) descriptor. Close ours so the supervisor
     doesn't accumulate unused fds across many spawns (future slices). *)
  (try Eio.Flow.close stdin_r with _ -> ()) ;
  let pid = Eio.Process.pid proc in
  {
    pid;
    socket_path;
    await = (fun () -> Eio.Process.await proc);
    signal = (fun s -> Eio.Process.signal proc s);
  }

let rec wait_ready ~sw ~net ~clock ~socket_path ~retries ~delay =
  match Eio.Net.connect ~sw net (`Unix socket_path) with
  | conn ->
      (try Eio.Flow.close conn with _ -> ()) ;
      true
  | exception (Eio.Io _ | Unix.Unix_error _) ->
      if retries <= 0 then false
      else begin
        Eio.Time.sleep clock delay ;
        wait_ready ~sw ~net ~clock ~socket_path ~retries:(retries - 1) ~delay
      end

let reap ~sw worker ~on_exit =
  Eio.Fiber.fork ~sw (fun () -> on_exit (worker.await ()))

let kill worker = worker.signal Sys.sigterm

let string_of_exit_status = function
  | `Exited code -> Printf.sprintf "exited %d" code
  | `Signaled signum -> Printf.sprintf "signaled %d" signum

(* ["localhost"] must resolve the same way {!Serve_policy.is_loopback}
   already treats it (already-trusted, no auth required) — otherwise
   [--bind localhost] would pass the fail-closed check and then crash
   with an uncaught [Failure] the moment we try to actually bind it,
   since {!Unix.inet_addr_of_string} only accepts numeric IP literals.
   Any other non-numeric host is a genuine usage error and still fails,
   but with a clear message. *)
let ipaddr_of_host host =
  let literal = if host = "localhost" then "127.0.0.1" else host in
  match Unix.inet_addr_of_string literal with
  | addr -> Eio_unix.Net.Ipaddr.of_unix addr
  | exception Failure _ ->
      failwith
        (Printf.sprintf
           "miaou serve: --bind %S is not a valid IP literal (DNS name \
            resolution is not supported; use an IP address or \"localhost\")"
           host)

(* ["0.0.0.0"] (all interfaces) is not itself a usable client-facing
   address — print a loopback address a browser can actually connect
   to instead of an address that only makes sense as a bind target. *)
let display_host bind = if bind = "0.0.0.0" then "127.0.0.1" else bind

(* Set by the supervisor's SIGTERM/SIGINT handler; polled by a fiber
   rather than acted on directly inside the signal handler (running
   arbitrary Eio operations from inside a raw signal handler is not
   something this module relies on being safe). *)
let stop_requested = Atomic.make false

let install_signal_handler () =
  let handler = Sys.Signal_handle (fun _ -> Atomic.set stop_requested true) in
  (try Sys.set_signal Sys.sigterm handler with Invalid_argument _ -> ()) ;
  try Sys.set_signal Sys.sigint handler with Invalid_argument _ -> ()

let run ?auth_token ?auth_file ?(port = Serve_config.default.port)
    ?(bind = Serve_config.default.bind)
    ?(max_sessions = Serve_config.default.max_sessions)
    ?(idle_timeout = Serve_config.default.idle_timeout)
    ?(insecure_allow_plaintext_external = false)
    (_page : (module Miaou_core.Tui_page.PAGE_SIG)) : unit =
  (* [_page] is accepted (not used directly): the supervisor never runs
     an app instance itself. It exists only so {!Serve_run.run}'s
     signature is uniform across the worker/supervisor branches — the
     worker re-exec, running the very same host [main] a second time,
     is what actually threads [_page] into {!Serve_worker.run}. *)
  let has_auth = Option.is_some auth_token || Option.is_some auth_file in
  (match
     Serve_policy.check ~bind ~has_auth ~insecure_allow_plaintext_external
   with
  | Ok () -> ()
  | Error refusal -> raise (Bind_refused (Serve_policy.refusal_message refusal))) ;
  if insecure_allow_plaintext_external then
    Printf.eprintf
      "[miaou serve] WARNING: --insecure-allow-plaintext-external set; binding \
       %s without a reverse proxy. See docs/serve.md.\n\
       %!"
      bind ;
  Printf.eprintf
    "[miaou serve] max_sessions=%d idle_timeout=%.0fs (Slice 2: single worker, \
     both values recorded but not yet enforced — Slice 4 wires limits/timeout)\n\
     %!"
    max_sessions
    idle_timeout ;
  Eio_main.run @@ fun env ->
  Eio.Switch.run @@ fun sw ->
  let proc_mgr = env#process_mgr in
  let pid = Unix.getpid () in
  sweep_stale_dirs () ;
  let dir = socket_dir ~pid in
  ensure_socket_dir dir ;
  let socket_path = Filename.concat dir "worker.sock" in
  (* Last-resort net: covers any exit path that doesn't go through the
     explicit cleanup calls below (an uncaught exception unwinding out
     of [Eio_main.run], for instance). [Stdlib.exit] — including the one
     called by the runtime's own uncaught-exception handler — always
     runs [at_exit] callbacks; only a raw signal kill of *this* process
     (not the worker) would skip it, which is why the reap callback
     below also cleans up independently of this. *)
  at_exit (cleanup_dir ~dir ~socket_path) ;
  let worker = spawn_worker ~sw ~proc_mgr ~socket_path () in
  reap ~sw worker ~on_exit:(fun status ->
      Printf.eprintf
        "[miaou serve] worker pid=%d exited: %s\n%!"
        worker.pid
        (string_of_exit_status status) ;
      cleanup_dir ~dir ~socket_path ()) ;
  if
    not
      (wait_ready
         ~sw
         ~net:env#net
         ~clock:env#clock
         ~socket_path
         ~retries:150
         ~delay:0.02)
  then begin
    Printf.eprintf
      "[miaou serve] worker pid=%d never became reachable, killing it\n%!"
      worker.pid ;
    kill worker ;
    failwith "miaou serve: worker did not become reachable"
  end ;
  let token = Serve_token.generate ~env ~role:Serve_token.Controller in
  let url =
    Printf.sprintf
      "http://%s:%d/s/%s/"
      (display_host bind)
      port
      (Serve_token.to_string token)
  in
  Printf.eprintf "[miaou serve] session ready: %s\n%!" url ;
  install_signal_handler () ;
  Eio.Fiber.fork ~sw (fun () ->
      let rec watch () =
        if Atomic.get stop_requested then begin
          Printf.eprintf
            "[miaou serve] shutdown requested, killing worker pid=%d\n%!"
            worker.pid ;
          kill worker ;
          cleanup_dir ~dir ~socket_path () ;
          exit 0
        end
        else begin
          Eio.Time.sleep env#clock 0.2 ;
          watch ()
        end
      in
      watch ()) ;
  let listen_addr = `Tcp (ipaddr_of_host bind, port) in
  let listening =
    Eio.Net.listen env#net ~sw ~reuse_addr:true ~backlog:16 listen_addr
  in
  let rec accept_loop () =
    let conn, _addr = Eio.Net.accept ~sw listening in
    Eio.Fiber.fork ~sw (fun () ->
        Serve_proxy.handle_connection
          ~sw
          ~env
          ~token
          ~worker_socket_path:socket_path
          ~conn) ;
    accept_loop ()
  in
  accept_loop ()
