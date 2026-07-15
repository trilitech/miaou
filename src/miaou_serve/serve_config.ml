(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

type t = {
  app : string option;
  port : int;
  bind : string;
  auth_token : string option;
  auth_file : string option;
  max_sessions : int;
  idle_timeout : float;
  insecure_allow_plaintext_external : bool;
}

let default =
  {
    app = None;
    port = 8080;
    bind = "127.0.0.1";
    auth_token = None;
    auth_file = None;
    (* FR-071's measurement (Slice 0, kb/architecture.md) is not yet a
       shipped numeric default owner in Slice 1; this value is a
       placeholder pending Slice 4, kept conservative. *)
    max_sessions = 16;
    idle_timeout = 15. *. 60.;
    insecure_allow_plaintext_external = false;
  }

let has_auth t = Option.is_some t.auth_token || Option.is_some t.auth_file
