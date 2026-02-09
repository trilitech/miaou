(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(** Page state wrapper with navigation support.
    Pages work with ['a pstate] instead of raw state, enabling
    framework-managed navigation without boilerplate. *)

type nav = Goto of string | Back | Quit

type 'a t = {s : 'a; nav : nav option}

let make s = {s; nav = None}

let goto page ps = {ps with nav = Some (Goto page)}

let back ps = {ps with nav = Some Back}

let quit ps = {ps with nav = Some Quit}

let pending ps = ps.nav

let update f ps = {ps with s = f ps.s}
