(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

type 'a validation_result = Valid of 'a | Invalid of string

type 'a validator = string -> 'a validation_result

type 'a t

val create :
  ?title:string ->
  ?width:int ->
  ?initial:string ->
  ?placeholder:string option ->
  validator:'a validator ->
  unit ->
  'a t

val open_centered :
  ?title:string ->
  ?width:int ->
  ?initial:string ->
  ?placeholder:string option ->
  validator:'a validator ->
  unit ->
  'a t

val render : 'a t -> focus:bool -> string

val handle_key : 'a t -> key:string -> 'a t

val is_cancelled : 'a t -> bool

val reset_cancelled : 'a t -> 'a t

val value : 'a t -> string

val validation_result : 'a t -> 'a validation_result

val is_valid : 'a t -> bool

val get_validated_value : 'a t -> 'a option

val get_error_message : 'a t -> string option

val width : 'a t -> int

val with_width : 'a t -> int -> 'a t

(** Usage:
    {[
      let validate_int s =
        match int_of_string_opt s with
        | Some v when v >= 0 -> Valid v
        | _ -> Invalid "Enter a non-negative integer"
      in
      let box = create ~title:"Instances" ~validator:validate_int () in
      let box = handle_key box ~key:"1" in
      render box ~focus:true
    ]}
    Keys: forwarded to [Textbox_widget.handle_key]; render shows validation errors in red. *)
