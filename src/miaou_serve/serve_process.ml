(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

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

(* Best-effort teardown of a session directory: remove every file left in
   it (each session's worker socket file may still exist if that worker
   was killed abruptly and never got to clean up its own listening
   socket) and the now-empty directory. Never raises. *)
let cleanup_dir ~dir () =
  (try
     Array.iter
       (fun f -> try Sys.remove (Filename.concat dir f) with _ -> ())
       (Sys.readdir dir)
   with _ -> ()) ;
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
     doesn't accumulate unused fds across many spawns. *)
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

let display_host bind = if bind = "0.0.0.0" then "127.0.0.1" else bind

let stop_requested = Atomic.make false

let install_signal_handler () =
  let handler = Sys.Signal_handle (fun _ -> Atomic.set stop_requested true) in
  (try Sys.set_signal Sys.sigterm handler with Invalid_argument _ -> ()) ;
  try Sys.set_signal Sys.sigint handler with Invalid_argument _ -> ()
