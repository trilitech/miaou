(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(** Shared debug switch for modal diagnostics, gated by the
    [MIAOU_TUI_DEBUG_MODAL] environment variable (checked via the
    {!Miaou_interfaces.System} capability when available, falling back to
    [Sys.getenv_opt]). *)

(** [true] when modal debug logging is enabled. Computed lazily so the
    environment is only consulted once. *)
val debug_enabled : bool Lazy.t

(** Print to stderr when {!debug_enabled} is set; a no-op otherwise. *)
val dprintf : ('a, out_channel, unit) format -> 'a
