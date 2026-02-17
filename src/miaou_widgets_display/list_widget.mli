(* ***************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(* *************************************************************************** *)

(** Foldable list widget with recursive sublists.

    This widget renders a hierarchical list with expandable/collapsible
    sublists and indentation. It is designed for menus, navigation trees,
    or categorized lists.
*)

(** List item with optional children. *)
type item = {
  id : string option;  (** Optional identifier for selection/lookup *)
  label : string;  (** Display label *)
  children : item list;  (** Nested items *)
  selectable : bool;  (** Whether the item can be activated *)
}

(** Widget state. *)
type t

(** {1 Construction} *)

val item :
  ?id:string -> ?selectable:bool -> ?children:item list -> string -> item

val group : ?id:string -> ?selectable:bool -> string -> item list -> item

val create : ?indent:int -> ?expand_all:bool -> item list -> t

val set_items : t -> item list -> t

(** {1 Selection} *)

val selected : t -> item option

val selected_path : t -> int list option

val visible_count : t -> int

val cursor_index : t -> int

val set_cursor_index : t -> int -> t

(** {1 Expansion} *)

val toggle : t -> t

val expand_all : t -> t

val collapse_all : t -> t

(** {1 Rendering} *)

val render : t -> focus:bool -> string

(** {1 Input Handling} *)

val handle_key : t -> key:string -> t
