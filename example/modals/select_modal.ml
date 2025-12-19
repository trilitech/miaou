(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

type state = string Miaou_widgets_input.Select_widget.t

type msg = unit

let init () =
  Miaou_widgets_input.Select_widget.open_centered
    ~cursor:0
    ~title:"Select an option"
    ~items:["Option A"; "Option B"; "Option C"; "Option D"]
    ~to_string:(fun x -> x)
    ()

let update s _ = s

let view s ~focus ~size:_ = Miaou_widgets_input.Select_widget.render s ~focus

let handle_key s key_str ~size:_ =
  Miaou_widgets_input.Select_widget.handle_key s ~key:key_str

let move s _ = s

let refresh s = s

let enter s = s

let service_select s _ = s

let service_cycle s _ = s

let handle_modal_key s _ ~size:_ = s

let next_page _ = None

let keymap (_ : state) = []

let handled_keys () = []

let extract_selection s = Miaou_widgets_input.Select_widget.get_selection s

let back s = s

let has_modal _ = false
