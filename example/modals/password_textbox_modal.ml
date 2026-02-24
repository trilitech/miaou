(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

type state = Miaou_widgets_input.Textbox_widget.t

type pstate = state Miaou.Core.Navigation.t

type key_binding = state Miaou.Core.Tui_page.key_binding_desc

type msg = unit

let init () =
  Miaou.Core.Navigation.make
    (Miaou_widgets_input.Textbox_widget.open_centered
       ~mask:true
       ~width:40
       ~placeholder:(Some "Enter password...")
       ())

let update ps _ = ps

let view ps ~focus:_ ~size:_ =
  Miaou_widgets_input.Textbox_widget.render
    ps.Miaou.Core.Navigation.s
    ~focus:true

let handle_key ps key_str ~size:_ =
  Miaou.Core.Navigation.update
    (fun s -> Miaou_widgets_input.Textbox_widget.handle_key s ~key:key_str)
    ps

let on_key ps key ~size =
  let key_str = Miaou.Core.Keys.to_string key in
  let ps' = handle_key ps key_str ~size in
  (ps', Miaou_interfaces.Key_event.Bubble)

let on_modal_key ps key ~size = on_key ps key ~size

let key_hints (_ : pstate) = []

let move ps _ = ps

let refresh ps = ps

let service_select ps _ = ps

let service_cycle ps _ = ps

let handle_modal_key ps key ~size:_ =
  (* Forward mouse events to the widget *)
  if Miaou_helpers.Mouse.is_mouse_event key then
    Miaou.Core.Navigation.update
      (fun s -> Miaou_widgets_input.Textbox_widget.handle_key s ~key)
      ps
  else ps

let keymap (_ : pstate) = []

let handled_keys () = []

let back ps = ps

let has_modal _ = false
