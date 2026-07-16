(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(** Parsed configuration shared by the [miaou serve] CLI and
    {!Miaou_serve.run} (FR-001, FR-002). *)

type t = {
  app : string option;
      (** App name resolved via [Registry.find]; [None] when
          {!Miaou_serve.run} is called directly with a page module instead
          of going through the CLI's [--app] flag. *)
  port : int;
  bind : string;
  auth_token : string option;
  auth_file : string option;
  max_sessions : int;
  idle_timeout : float;  (** seconds *)
  insecure_allow_plaintext_external : bool;
  allowed_origins : string list;
      (** Extra [Origin] values accepted at WebSocket upgrade (FR-045),
          in addition to the same-origin-as-[bind] default
          ({!Serve_origin.default_allowed}) — for a reverse-proxy setup
          whose public origin differs from the bind address. Populated
          by one or more [--allowed-origin] flags; [[]] means "no extra
          origins beyond the bind-derived default". *)
}

(** Defaults used when a flag/argument is not supplied. [bind] defaults to
    loopback-only, matching the fail-closed policy (FR-003). *)
val default : t

(** [true] iff [t] carries some auth mechanism (a literal token or a token
    file path) — the input to {!Serve_policy.check}'s [~has_auth]. Does
    not read or validate the file's contents. *)
val has_auth : t -> bool
