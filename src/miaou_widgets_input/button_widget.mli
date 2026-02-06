(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)
(** Abstract type for a button widget. *)
type t

(** Create a button.
    @param disabled When true, the button is rendered dimmed and ignores key handling. *)
val create :
  ?disabled:bool -> label:string -> on_click:(unit -> unit) -> unit -> t

(** Render the button as a string, style depends on focus. *)
val render : t -> focus:bool -> string

(** Handle a key; returns updated widget and whether the action fired.
    @deprecated Use [on_key] for new code. *)
val handle_key : t -> key:string -> t * bool

(** Handle a key with unified result type. Returns [Handled] on Enter/Space. *)
val on_key : t -> key:string -> t * Miaou_interfaces.Key_event.result

(** Usage:
    {[
      let b = Button_widget.create ~label:"Run" ~on_click:(fun () -> ()) () in
      let b, fired = Button_widget.handle_key b ~key:"Enter" in
      ignore fired ;
      Button_widget.render b ~focus:true
    ]}
    Keys: Enter/Space fires [on_click]. *)
