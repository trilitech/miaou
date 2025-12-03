(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)
type target =
  | Internal of string  (** page id or route name *)
  | External of string  (** URL *)

(** Abstract type for a link widget. *)
type t

val create : label:string -> target:target -> on_navigate:(target -> unit) -> t

val render : t -> focus:bool -> string

val handle_key : t -> key:string -> t * bool
