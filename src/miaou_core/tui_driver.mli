(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)
open Tui_page

type t

val size : unit -> t

val poll_event : unit -> string

val draw_text : string -> unit

val clear : unit -> unit

val flush : unit -> unit

val set_page : (module PAGE_SIG) -> unit

type outcome = [`Quit | `Back | `SwitchTo of string]

val run : (module PAGE_SIG) -> outcome
