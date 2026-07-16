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
    (* FR-071: grounded in a measured per-worker RSS figure, not invented.
       A worker's baseline RSS was measured at ~6-9MB (see
       docs/serve-architecture.md §3 for the measurement and the
       derivation below, spelled out there in full). Assuming a
       conservative 320MB memory budget an operator can spare for
       `miaou serve` sessions on a modest host, and a 20MB
       per-worker headroom figure (roughly 2x the measured RSS, to
       absorb OCaml-runtime/OS bookkeeping overhead beyond live heap
       data): 320 / 20 = 16. Adjustable via --max-sessions for hosts
       with a different memory budget. *)
    max_sessions = 16;
    idle_timeout = 15. *. 60.;
    insecure_allow_plaintext_external = false;
  }

let has_auth t = Option.is_some t.auth_token || Option.is_some t.auth_file
