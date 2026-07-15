(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(** Fail-closed bind policy (FR-003, FR-060).

    [miaou serve] must refuse to bind to a non-loopback address unless an
    auth mechanism is configured, or the operator has explicitly
    acknowledged the risk via [--insecure-allow-plaintext-external]. This
    module is pure decision logic — it does not open sockets; callers
    (the CLI, {!Miaou_serve.run}) consult it before doing so. *)

(** [true] iff [host] is a loopback address (["127.0.0.1"], ["::1"], or
    ["localhost"]) — the only bind target treated as already-trusted. *)
val is_loopback : string -> bool

(** Reason a bind was refused, for a documented, testable error message. *)
type refusal =
  | No_auth_on_public_bind of {bind : string}
      (** Binding to a non-loopback address with no auth token configured
          and no explicit insecure override. *)

val refusal_message : refusal -> string

(** [check ~bind ~has_auth ~insecure_allow_plaintext_external] returns
    [Ok ()] if the bind is permitted, or [Error r] if it must be refused.
    A loopback [bind] is always permitted. A non-loopback [bind] is
    permitted only if [has_auth] or
    [insecure_allow_plaintext_external] is [true]. *)
val check :
  bind:string ->
  has_auth:bool ->
  insecure_allow_plaintext_external:bool ->
  (unit, refusal) result
