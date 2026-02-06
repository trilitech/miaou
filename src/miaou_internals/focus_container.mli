(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

(** Focus container: GADT-based heterogeneous widget container.

    Holds a {!Focus_ring.t} and a list of existentially packed widget
    slots. Tab/Shift+Tab cycle focus; other keys are routed to the
    focused widget automatically.

    {[
      let c = FC.create [
        FC.slot "enable" checkbox_ops (Checkbox_widget.create ());
        FC.slot "name"   textbox_ops  (Textbox_widget.create ());
        FC.slot "go"     button_ops   (Button_widget.create ~label:"Go"
                                         ~on_click:ignore ());
      ]
      let c', result = FC.on_key c ~key:"Tab"
    ]} *)

(** Widget operations record -- uniform interface for any widget type. *)
type 'a widget_ops = {
  render : 'a -> focus:bool -> string;
  on_key : 'a -> key:string -> 'a * Miaou_interfaces.Key_event.result;
}

(** @deprecated Legacy widget ops with polymorphic variant result. *)
type 'a widget_ops_legacy = {
  render : 'a -> focus:bool -> string;
  handle_key : 'a -> key:string -> 'a * [`Handled | `Bubble];
}

(** Existentially packed widget slot. *)
type packed_slot

(** Create a named slot. *)
val slot : string -> 'a widget_ops -> 'a -> packed_slot

(** The container type. *)
type t

(** Create from a list of slots. Focus ring built from slot IDs. *)
val create : packed_slot list -> t

(** Handle a key. Tab/Shift+Tab cycle focus; other keys route to
    the focused widget. Returns Key_event.result. *)
val on_key : t -> key:string -> t * Miaou_interfaces.Key_event.result

(** @deprecated Use [on_key] instead. Returns polymorphic variant for compat. *)
val handle_key : t -> key:string -> t * [`Handled | `Bubble]

(** Render all widgets: [(id, focused, rendered_string)] in order. *)
val render_all : t -> (string * bool * string) list

(** Render only the focused widget. *)
val render_focused : t -> (string * string) option

(** Current focused slot ID. *)
val focused_id : t -> string option

(** Focus a slot by ID. *)
val focus : t -> string -> t

(** Access the underlying focus ring (for scope nesting). *)
val ring : t -> Focus_ring.t

(** Replace the focus ring. *)
val set_ring : t -> Focus_ring.t -> t

(** Number of slots. *)
val count : t -> int

(** {1 Type-safe extraction via witness} *)

type 'a witness

val witness : unit -> 'a witness

val slot_w : string -> 'a widget_ops -> 'a -> 'a witness -> packed_slot

val get : t -> string -> 'a witness -> 'a option

val set : t -> string -> 'a witness -> 'a -> t

(** {1 Adapter constructors} *)

(** Create widget_ops from render and on_key functions. *)
val ops :
  render:('a -> focus:bool -> string) ->
  on_key:('a -> key:string -> 'a * Miaou_interfaces.Key_event.result) ->
  'a widget_ops

(** @deprecated For widgets with [handle_key : t -> key:string -> t] (always bubbles). *)
val ops_simple :
  render:('a -> focus:bool -> string) ->
  handle_key:('a -> key:string -> 'a) ->
  'a widget_ops

(** @deprecated For widgets with [handle_key : t -> key:string -> t * bool]. *)
val ops_bool :
  render:('a -> focus:bool -> string) ->
  handle_key:('a -> key:string -> 'a * bool) ->
  'a widget_ops

(** Adapter: wrap legacy handle_key returning polymorphic variant. *)
val ops_of_legacy : 'a widget_ops_legacy -> 'a widget_ops
