(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

type item = {label : string; id : int}

type state = item Miaou_widgets_input.Select_widget.t

type pstate = state Miaou.Core.Navigation.t

type key_binding = state Miaou.Core.Tui_page.key_binding_desc

type msg = unit

let init () =
  let items =
    [
      {label = "Alpha"; id = 1};
      {label = "Beta"; id = 2};
      {label = "Gamma"; id = 3};
    ]
  in
  Miaou.Core.Navigation.make
    (Miaou_widgets_input.Select_widget.open_centered
       ~cursor:0
       ~title:"Select a record (poly)"
       ~items
       ~to_string:(fun i -> Printf.sprintf "%s (id=%d)" i.label i.id)
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

let back ps = ps

let has_modal _ = false

let handle_modal_key ps _ ~size:_ = ps

let keymap (_ : pstate) = []

let handled_keys () = []

let extract_selection (ps : pstate) : string option =
  match
    Miaou_widgets_input.Select_widget.get_selection ps.Miaou.Core.Navigation.s
  with
  | None -> None
  | Some it -> Some (Printf.sprintf "%s (id=%d)" it.label it.id)
