(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)
(** Abstract type for a button widget. *)
type t

(** Create a button. *)
val create : label:string -> on_click:(unit -> unit) -> t

(** Render the button as a string, style depends on focus. *)
val render : t -> focus:bool -> string

(** Handle a key; returns updated widget and whether the action fired. *)
val handle_key : t -> key:string -> t * bool
