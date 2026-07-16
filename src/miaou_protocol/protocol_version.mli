(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Mathias Bourgoin <mathias.bourgoin@atacama.tech>        *)
(*                                                                            *)
(******************************************************************************)

(** Versioning for the MIAOU agent protocol (JSON-over-stdio and MCP).

    [current] is stamped as [schema_version] on every response. Requests may
    carry an optional [protocol_version] field; the server tolerates any
    version in [supported] and rejects the rest with [E_BAD_REQUEST], per the
    backward-compatibility requirement that v1-only clients (no
    [protocol_version] field at all) keep working unmodified. *)

(** The schema version stamped on every response, e.g. ["1.0"]. *)
val current : string

(** All protocol versions this server accepts in an incoming request's
    optional [protocol_version] field. *)
val supported : string list

(** [is_supported v] is [true] iff [v] is in {!supported}. *)
val is_supported : string -> bool
