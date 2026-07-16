(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Mathias Bourgoin <mathias.bourgoin@atacama.tech>        *)
(*                                                                            *)
(******************************************************************************)

(** Closed error taxonomy for the MIAOU agent protocol.

    Every protocol-level failure (malformed request, unknown command, a
    [wait_for] timeout, a mutation attempted against a [--read-only] server,
    or an unexpected internal failure) is reported using one of the fixed
    codes below, never an ad hoc string, so agents can pattern-match on
    [code] rather than parsing [message]. *)

type code =
  | E_BAD_REQUEST
      (** Malformed JSON, or a required field is missing/invalid. *)
  | E_UNSUPPORTED_COMMAND
      (** [cmd] is not a command this server understands. *)
  | E_TIMEOUT
      (** A [wait_for] condition did not become true before [timeout_ms]. *)
  | E_READ_ONLY
      (** A mutating action was attempted against a read-only server. *)
  | E_INTERNAL  (** An unexpected internal failure. *)

val code_to_string : code -> string

(** A structured failure. Mirrors {!Miaou_core.Workflow.error} field-for-field
    ([step], [message], [attempt], [screen]) so a [wait_for] timeout over the
    wire and a [Workflow_error] raised in-process carry identical diagnostics
    (US-4/FR-042). [code] is [None] for assertion-style failures (e.g.
    [assert_screen] returning [ok:false]), which — like {!Workflow.expect} —
    have no protocol error code of their own, only the four Workflow-shaped
    fields. *)
type t = {
  code : code option;
  step : string;
  message : string;
  attempt : int option;
  screen : string option;
}

(** [make ~step message] builds a structured error for [step] with the given
    [message]; [?code], [?attempt], [?screen] default to [None]. *)
val make :
  ?code:code -> ?attempt:int -> ?screen:string -> step:string -> string -> t

(** Render [t] as a protocol error response object:
    [{"type":"error"; "schema_version"; "code"?; "step"; "message";
       "attempt"?; "screen"?}]. Always includes [schema_version] (FR-091). *)
val to_yojson : schema_version:string -> t -> Yojson.Safe.t
