(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(* Reusable prompt helpers. See prompt.mli for the public API. *)

(* {1 Pure result mapping} *)

let confirm_outcome = function `Commit -> true | `Cancel -> false

let input_result outcome ~text =
  match outcome with `Commit -> Some text | `Cancel -> None

let select_result outcome ~selected =
  match outcome with `Commit -> selected | `Cancel -> None

(* {1 Confirm modal page}

   A trivial page that renders a static message. Modal_manager's commit_on /
   cancel_on lists handle Enter and Esc — the page itself is a passive
   message box. *)

module Confirm_page (M : sig
  val message : string
end) : Tui_page.PAGE_SIG = struct
  type state = unit

  type pstate = state Navigation.t

  type msg = unit

  type key_binding = state Tui_page.key_binding_desc

  let init () = Navigation.make ()

  let update ps _ = ps

  let view _ ~focus:_ ~size:_ = M.message ^ "\n\n[Enter] yes   [Esc] no"

  let handle_key ps _ ~size:_ = ps

  let on_key ps _ ~size:_ = (ps, Miaou_interfaces.Key_event.Bubble)

  let on_modal_key ps _ ~size:_ = (ps, Miaou_interfaces.Key_event.Bubble)

  let key_hints (_ : pstate) = []

  let move ps _ = ps

  let refresh ps = ps

  let service_select ps _ = ps

  let service_cycle ps _ = ps

  let handle_modal_key ps _ ~size:_ = ps

  let keymap (_ : pstate) = []

  let handled_keys () = []

  let back ps = ps

  let has_modal _ = false
end

(* {1 Input (textbox) modal page} *)

module Input_page : sig
  include
    Tui_page.PAGE_SIG with type state = Miaou_widgets_input.Textbox_widget.t

  val make_init : ?placeholder:string -> ?initial:string -> unit -> pstate
end = struct
  type state = Miaou_widgets_input.Textbox_widget.t

  type pstate = state Navigation.t

  type msg = unit

  type key_binding = state Tui_page.key_binding_desc

  let make_init ?placeholder ?(initial = "") () =
    Navigation.make
      (Miaou_widgets_input.Textbox_widget.open_centered
         ~width:40
         ~initial
         ~placeholder
         ())

  let init () = make_init ()

  let update ps _ = ps

  let view ps ~focus:_ ~size:_ =
    Miaou_widgets_input.Textbox_widget.render ps.Navigation.s ~focus:true

  let handle_key ps key_str ~size:_ =
    Navigation.update
      (fun s -> Miaou_widgets_input.Textbox_widget.handle_key s ~key:key_str)
      ps

  let on_key ps key ~size =
    let key_str = Keys.to_string key in
    let ps' = handle_key ps key_str ~size in
    (ps', Miaou_interfaces.Key_event.Bubble)

  let on_modal_key ps key ~size = on_key ps key ~size

  let key_hints (_ : pstate) = []

  let move ps _ = ps

  let refresh ps = ps

  let service_select ps _ = ps

  let service_cycle ps _ = ps

  let handle_modal_key ps key ~size:_ =
    if Miaou_helpers.Mouse.is_mouse_event key then
      Navigation.update
        (fun s -> Miaou_widgets_input.Textbox_widget.handle_key s ~key)
        ps
    else ps

  let keymap (_ : pstate) = []

  let handled_keys () = []

  let back ps = ps

  let has_modal _ = false
end

(* {1 Select modal page} *)

module Select_page (Item : sig
  type t

  val items : t list

  val to_string : t -> string
end) : sig
  include
    Tui_page.PAGE_SIG
      with type state = Item.t Miaou_widgets_input.Select_widget.t

  val make_init : unit -> pstate

  val extract : pstate -> Item.t option
end = struct
  type state = Item.t Miaou_widgets_input.Select_widget.t

  type pstate = state Navigation.t

  type msg = unit

  type key_binding = state Tui_page.key_binding_desc

  let make_init () =
    Navigation.make
      (Miaou_widgets_input.Select_widget.open_centered
         ~cursor:0
         ~title:""
         ~items:Item.items
         ~to_string:Item.to_string
         ())

  let init () = make_init ()

  let update ps _ = ps

  let view ps ~focus ~size:_ =
    Miaou_widgets_input.Select_widget.render ps.Navigation.s ~focus

  let handle_key ps key_str ~size:_ =
    Navigation.update
      (fun s -> Miaou_widgets_input.Select_widget.handle_key s ~key:key_str)
      ps

  let on_key ps key ~size =
    let key_str = Keys.to_string key in
    let ps' = handle_key ps key_str ~size in
    (ps', Miaou_interfaces.Key_event.Bubble)

  let on_modal_key ps key ~size = on_key ps key ~size

  let key_hints (_ : pstate) = []

  let move ps _ = ps

  let refresh ps = ps

  let service_select ps _ = ps

  let service_cycle ps _ = ps

  let handle_modal_key ps key ~size =
    if Miaou_helpers.Mouse.is_mouse_event key then
      Navigation.update
        (fun s ->
          Miaou_widgets_input.Select_widget.handle_key_with_size s ~key ~size)
        ps
    else ps

  let keymap (_ : pstate) = []

  let handled_keys () = []

  let extract ps =
    Miaou_widgets_input.Select_widget.get_selection ps.Navigation.s

  let back ps = ps

  let has_modal _ = false
end

(* {1 Public helpers} *)

let confirm ~title ~message ~on_result () =
  let module C = Confirm_page (struct
    let message = message
  end) in
  Modal_manager.confirm
    (module C)
    ~init:(C.init ())
    ~title
    ~dim_background:true
    ~on_result
    ()

let input ?placeholder ?initial ~title ~on_result () =
  let init = Input_page.make_init ?placeholder ?initial () in
  Modal_manager.confirm_with_extract
    (module Input_page)
    ~init
    ~title
    ~dim_background:true
    ~extract:(fun ps ->
      Some (Miaou_widgets_input.Textbox_widget.get_text ps.Navigation.s))
    ~on_result
    ()

let select (type a) ~title ~items ~(to_string : a -> string) ~on_result () =
  let module S = Select_page (struct
    type t = a

    let items = items

    let to_string = to_string
  end) in
  Modal_manager.confirm_with_extract
    (module S)
    ~init:(S.make_init ())
    ~title
    ~dim_background:true
    ~extract:S.extract
    ~on_result
    ()
