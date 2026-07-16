(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Mathias Bourgoin <mathias.bourgoin@atacama.tech>        *)
(*                                                                            *)
(******************************************************************************)

(** MCP tool/resource wiring for [miaou-mcp] (FR-070–FR-076, FR-080–FR-081).

    Every tool delegates to {!Miaou_protocol.Protocol_core.handle_cmd} — the
    same dispatcher the JSON-over-stdio runner uses — so [miaou-mcp] and
    [miaou-headless-json] agree on every command's behavior by construction,
    not by convention. *)

(** The full list of protocol command names this server exposes as tools,
    each tagged with its read-only classification (FR-081): [`Read_only] for
    [render]/[wait_for]/[assert_screen] (never call
    [HD.Stateful.send_key]/[switch_to_page]); [`Mutating] for
    [key]/[tick]/[resize]/[quit]. Exhaustive and closed — a conformance test
    iterates every registered tool name and asserts it appears here exactly
    once (FR-080's fixture). *)
val classification : (string * [`Read_only | `Mutating]) list

(** [tools ~read_only] builds every {!Mcp_kit.Tool.t} in {!classification}.
    When [read_only] is [true], [`Mutating] tools are registered as stubs
    that unconditionally return [E_READ_ONLY] without touching the driver
    (FR-080) — the refusal lives in the dispatch table itself, not a
    list-time-only gate. *)
val tools : read_only:bool -> Mcp_kit.Tool.t list

(** [resources ~page_names ~protocol_version] builds the static
    [miaou://pages] and [miaou://protocol/version] resources (FR-071). *)
val resources :
  page_names:string list -> protocol_version:string -> Mcp_kit.Resource.t list
