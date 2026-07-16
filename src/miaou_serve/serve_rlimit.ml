(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

let env_var_as_mb = "MIAOU_SERVE_RLIMIT_AS_MB"

let env_var_cpu_seconds = "MIAOU_SERVE_RLIMIT_CPU_SECONDS"

(* [prlimit --pid <self> --<resource>=<value>:<value>] sets both the soft
   and hard limit of the *current* process (identified by its own pid) in
   place — see the .mli's "why this shells out" note. Never raises: a
   missing binary, a non-zero exit, or any [Unix.system] failure is logged
   to stderr and otherwise ignored, since a missing defense-in-depth
   backstop must not itself take down a legitimate worker. *)
let run_prlimit ~resource ~value =
  let pid = Unix.getpid () in
  let cmd =
    Printf.sprintf "prlimit --pid %d --%s=%s:%s" pid resource value value
  in
  match Unix.system cmd with
  | Unix.WEXITED 0 -> ()
  | Unix.WEXITED code ->
      Printf.eprintf
        "[miaou serve worker] warning: 'prlimit --%s' exited %d; resource \
         limit not applied (see docs/serve-architecture.md for the platform \
         caveat)\n\
         %!"
        resource
        code
  | Unix.WSIGNALED _ | Unix.WSTOPPED _ ->
      Printf.eprintf
        "[miaou serve worker] warning: 'prlimit --%s' did not complete \
         normally; resource limit not applied\n\
         %!"
        resource
  | exception Unix.Unix_error (err, _, _) ->
      Printf.eprintf
        "[miaou serve worker] warning: could not run 'prlimit' (%s); resource \
         limit not applied — this defense-in-depth backstop requires the \
         prlimit(1) utility (util-linux) on PATH\n\
         %!"
        (Unix.error_message err)

let apply_positive_int_env env_var ~apply =
  match Sys.getenv_opt env_var with
  | None -> ()
  | Some s -> (
      match int_of_string_opt s with
      | Some n when n > 0 -> apply n
      | _ ->
          Printf.eprintf
            "[miaou serve worker] warning: %s=%S is not a positive integer; \
             ignoring\n\
             %!"
            env_var
            s)

let apply_from_env () =
  apply_positive_int_env env_var_as_mb ~apply:(fun mb ->
      run_prlimit ~resource:"as" ~value:(string_of_int (mb * 1024 * 1024))) ;
  apply_positive_int_env env_var_cpu_seconds ~apply:(fun secs ->
      run_prlimit ~resource:"cpu" ~value:(string_of_int secs))
