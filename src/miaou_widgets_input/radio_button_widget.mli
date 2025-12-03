(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)
type t

val create : ?label:string -> ?selected:bool -> unit -> t

val open_centered : ?label:string -> ?selected:bool -> unit -> t

val render : t -> focus:bool -> string

(** Space/Enter selects this radio button. *)
val handle_key : t -> key:string -> t

val is_selected : t -> bool

val set_selected : t -> bool -> t

val is_cancelled : t -> bool

val reset_cancelled : t -> t
