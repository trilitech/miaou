(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

type event =
  | Create
  | Attach_controller
  | Attach_viewer
  | Detach
  | Reconnect
  | Idle_kill
  | Explicit_kill
  | Auth_fail
  | Origin_reject
  | Session_end

let event_name = function
  | Create -> "create"
  | Attach_controller -> "attach-controller"
  | Attach_viewer -> "attach-viewer"
  | Detach -> "detach"
  | Reconnect -> "reconnect"
  | Idle_kill -> "idle-kill"
  | Explicit_kill -> "explicit-kill"
  | Auth_fail -> "auth-fail"
  | Origin_reject -> "origin-reject"
  | Session_end -> "session-end"

let hash_prefix_hex_chars = 16

let hash_token token =
  let hex = Digestif.SHA256.to_hex (Digestif.SHA256.digest_string token) in
  String.sub hex 0 hash_prefix_hex_chars

let log event ~token =
  try
    Printf.eprintf
      "[miaou serve audit] ts=%.6f event=%s session=%s\n%!"
      (Unix.gettimeofday ())
      (event_name event)
      (hash_token token)
  with _ -> ()
