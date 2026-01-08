(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

type state = Miaou_widgets_input.Textbox_widget.t

type pstate = state Miaou.Core.Navigation.t

type msg = unit

let init () =
  Miaou.Core.Navigation.make
    (Miaou_widgets_input.Textbox_widget.open_centered
       ~width:40
       ~initial:"Initial text"
       ~placeholder:(Some "Type here...")
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

let move ps _ = ps

let refresh ps = ps

let service_select ps _ = ps

let service_cycle ps _ = ps

let handle_modal_key ps _ ~size:_ = ps

let keymap (_ : pstate) = []

let handled_keys () = []

let back ps = ps

let has_modal _ = false
