(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

type state = Miaou_widgets_input.Textbox_widget.t

type msg = unit

let init () =
  Miaou_widgets_input.Textbox_widget.open_centered
    ~width:40
    ~initial:"Initial text"
    ~placeholder:(Some "Type here...")
    ()

let update s _ = s

let view s ~focus:_ ~size:_ =
  Miaou_widgets_input.Textbox_widget.render s ~focus:true

let handle_key s key_str ~size:_ =
  Miaou_widgets_input.Textbox_widget.handle_key s ~key:key_str

let move s _ = s

let refresh s = s

let enter s = s

let service_select s _ = s

let service_cycle s _ = s

let handle_modal_key s _ ~size:_ = s

let next_page _ = None

let keymap (_ : state) = []

let handled_keys () = []

let back s = s

let has_modal _ = false
