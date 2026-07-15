(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(** Direct, non-capability-routed logging sink (enable/disable + optional
    logfile), distinct from {!Logger} (which proxies through
    {!Miaou_interfaces.Logger_capability}).

    Decision (structural-debt G5b, FR-106): a repo-wide qualified-reference
    grep finds no direct in-tree caller of this module (every current
    consumer goes through the capability-routed {!Logger.Tui_logger}
    instead). It is kept rather than deleted because it is re-exported as
    part of the public library surface ([Lib_tui.Tui_logger] — see
    `lib_tui.ml`), which external embedders may reference directly; removing
    it would be a public-API break outside this package's evidence
    (parity/tmux suite covers in-tree behavior, not external embedding
    call sites). Flagged as a non-obvious case for maintainer review rather
    than silently deleted. Its state remains a plain top-level [ref]
    (not folded into an app-context record): it configures a single
    process-wide log sink by design, not a per-instance render/main-domain
    value, so there is no isolation hazard analogous to the other G5b
    slices. *)

val set_enabled : bool -> unit

val set_logfile : string option -> (unit, string) result

val logf : Miaou_interfaces.Logger_capability.level -> string -> unit
