(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

type state = string Miaou_widgets_input.Select_widget.t

type pstate = state Miaou.Core.Navigation.t

type msg = unit

let init () =
  Miaou.Core.Navigation.make
    (Miaou_widgets_input.Select_widget.open_centered
       ~cursor:0
       ~title:"Select an option"
       ~items:["Option A"; "Option B"; "Option C"; "Option D"]
       ~to_string:(fun x -> x)
       ())

let update ps _ = ps

let view ps ~focus ~size:_ =
  Miaou_widgets_input.Select_widget.render ps.Miaou.Core.Navigation.s ~focus

let handle_key ps key_str ~size:_ =
  Miaou.Core.Navigation.update
    (fun s -> Miaou_widgets_input.Select_widget.handle_key s ~key:key_str)
    ps

let move ps _ = ps

let refresh ps = ps

let service_select ps _ = ps

let service_cycle ps _ = ps

let handle_modal_key ps _ ~size:_ = ps

let keymap (_ : pstate) = []

let handled_keys () = []

let extract_selection ps =
  Miaou_widgets_input.Select_widget.get_selection ps.Miaou.Core.Navigation.s

let back ps = ps

let has_modal _ = false
