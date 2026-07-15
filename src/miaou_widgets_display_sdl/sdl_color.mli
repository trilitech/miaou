(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(** Convert an ANSI SGR foreground code (e.g. ["32"]) to its Solarized
    RGB approximation, shared by the SDL-rendered chart widgets. Unknown
    codes fall back to Solarized green. *)
val ansi_to_rgb : string -> int * int * int
