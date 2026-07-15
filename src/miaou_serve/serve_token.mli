(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(** Unguessable session tokens (FR-030, FR-033).

    A session token is CSPRNG-generated entropy embedded in a session's
    attach URL (e.g. [/s/<token>]). It is never sequential, never derived
    from user input, and carries a role claim fixed at issuance so a
    viewer-scoped token can never be used to attach as controller
    (FR-032) — the role is bound to the token value itself, not asserted
    by the client. *)

(** The role a token grants. [Controller] may drive input; [Viewer] is
    permanently read-only (no "request control" handoff in v1). *)
type role = Controller | Viewer

type t

(** Number of random bytes read from the CSPRNG source per token
    (32 bytes = 256 bits of entropy, well above the FR-030 128-bit floor). *)
val entropy_bytes : int

(** [generate ~env ~role] draws {!entropy_bytes} bytes from [env]'s secure
    random source (never {!Stdlib.Random}, which is seeded/predictable) and
    returns a fresh token bound to [role]. *)
val generate :
  env:< secure_random : Eio.Flow.source_ty Eio.Resource.t ; .. > ->
  role:role ->
  t

(** The token's role claim. *)
val role : t -> role

(** The token's URL-safe string representation (lowercase hex). *)
val to_string : t -> string

(** [matches t ~candidate] is [true] iff [candidate] equals [t]'s string
    representation, compared in constant time ({!Eqaf.equal}) to avoid the
    timing side-channel of {!Stdlib.( = )} (FR-033). Does not by itself
    check role — callers that need role enforcement must additionally
    consult {!role}. *)
val matches : t -> candidate:string -> bool
