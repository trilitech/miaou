(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

type item = {label : string; id : int}

type state = item Miaou_widgets_input.Select_widget.t

type msg = unit

let init () =
  let items =
    [
      {label = "Alpha"; id = 1};
      {label = "Beta"; id = 2};
      {label = "Gamma"; id = 3};
    ]
  in
  Miaou_widgets_input.Select_widget.open_centered
    ~cursor:0
    ~title:"Select a record (poly)"
    ~items
    ~to_string:(fun i -> Printf.sprintf "%s (id=%d)" i.label i.id)
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

let back s = s

let has_modal _ = false

let handle_modal_key s _ ~size:_ = s

let next_page _ = None

let keymap (_ : state) = []

let handled_keys () = []

let extract_selection (s : state) : string option =
  match Miaou_widgets_input.Select_widget.get_selection s with
  | None -> None
  | Some it -> Some (Printf.sprintf "%s (id=%d)" it.label it.id)
