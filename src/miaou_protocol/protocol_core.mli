(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Mathias Bourgoin <mathias.bourgoin@atacama.tech>        *)
(*                                                                            *)
(******************************************************************************)

(** Transport-agnostic core of the MIAOU agent protocol (TEXT-FIRST v1).

    This module owns command dispatch against the headless driver
    ({!Lib_miaou_internal.Headless_driver.Stateful}) and returns plain
    [Yojson.Safe.t] response values. It has no notion of stdio framing, MCP
    tool wrapping, or process lifecycle — those concerns belong to the
    transport shims that call {!handle_cmd} ({!Headless_json_runner} for
    JSON-over-stdio, [Miaou_mcp] for MCP tools).

    Read-only mode: this module never enforces [--read-only] itself — that
    classification lives in the transport (the stdio runner has no
    [--read-only] mode; [miaou-mcp] enforces it at tool-registration time, see
    FR-080). {!handle_cmd} always dispatches mutating commands. *)

(** ANSI/VT escape sequences stripped from a raw terminal frame, leaving plain
    text (shared by [snapshot]-style consumers and [wait_for]/[assert_screen]
    predicates, both of which operate on ANSI-stripped text in TEXT-FIRST v1). *)
val ansi_strip : string -> string

(** Set (or clear) the callback invoked with every raw ANSI frame as it is
    rendered, e.g. to drive an attached viewer. Mirrors the pre-extraction
    [~on_frame] parameter of the JSON-over-stdio runner. *)
val set_on_frame : (rows:int -> cols:int -> string -> unit) option -> unit

(** [init_session ?no_record page] installs [page] on the headless stateful
    driver and, unless [no_record] is [true] (or [MIAOU_NO_RECORD]/
    [--no-record] was already honoured by the caller), enables default-on
    session recording (FR-060) before the first frame renders. *)
val init_session :
  ?no_record:bool -> (module Miaou_core.Tui_page.PAGE_SIG) -> unit

(** [handle_cmd fields] dispatches one parsed JSON command object (its
    top-level fields as an assoc list) and returns the JSON response together
    with whether the session should keep running. Every response carries
    [schema_version] (FR-001); unknown/extra request fields are ignored
    (FR-002); [render]/[key]/[tick]/[resize]/[quit] are unchanged in shape
    beyond the additive [schema_version] field (FR-003/FR-100).

    Never raises: malformed input (including an invalid [wait_for]/
    [assert_screen] regex) is reported as [E_BAD_REQUEST], and any other
    unanticipated exception is caught and reported as [E_INTERNAL] — both
    callers (the stdio transport loop and [miaou-mcp]'s tool handlers) have
    no exception guard of their own around this call, so a crash here would
    otherwise take down the whole process. Eio's cancellation exception
    ([Eio.Cancel.Cancelled]) is the one exception re-raised unchanged, so
    structured-concurrency shutdown still works correctly. *)
val handle_cmd :
  (string * Yojson.Safe.t) list -> Yojson.Safe.t * [`Continue | `Stop]

(** Every command name {!handle_cmd} matches on its request's ["cmd"]
    field — the canonical list a conformance test checks the MCP tool
    classification ({!Miaou_mcp}'s [Mcp_tools.classification]) against, so
    an unclassified new command fails that test instead of becoming
    silently unreachable via MCP (M1). *)
val dispatchable_commands : string list

(** The subset of {!dispatchable_commands} deliberately not exposed as MCP
    tools (currently just ["click"], TEXT-FIRST v1's pre-existing stub for
    the deferred spatial-click feature) — subtracted from
    {!dispatchable_commands} before comparing against the MCP tool
    classification. *)
val deferred_commands : string list
