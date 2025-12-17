(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

let tutorial_markdown = [%blob "README.md"]

module Switch = Miaou_widgets_input.Switch_widget

type state = {switch : Switch.t; next_page : string option}

type msg = unit

let init () =
  let switch = Switch.create ~label:"Auto-update" ~on:false () in
  {switch; next_page = None}

let update s (_ : msg) = s

let view s ~focus:_ ~size:_ =
  let module W = Miaou_widgets_display.Widgets in
  let header = W.titleize "Switch" in
  let body = Switch.render s.switch ~focus:true in
  let hint = W.dim "Space/Enter toggles \226\128\162 t opens tutorial \226\128\162 Esc returns" in
  String.concat "\n\n" [header; body; hint]

let go_back s = {s with next_page = Some Demo_shared.Demo_config.launcher_page_name}

let show_tutorial () =
  Demo_shared.Tutorial_modal.show ~title:"Switch tutorial" ~markdown:tutorial_markdown ()

let handle_key s key_str ~size:_ =
  match Miaou.Core.Keys.of_string key_str with
  | Some (Miaou.Core.Keys.Char "Esc") | Some (Miaou.Core.Keys.Char "Escape") ->
      go_back s
  | Some (Miaou.Core.Keys.Char k) when String.lowercase_ascii k = "t" ->
      show_tutorial () ;
      s
  | Some (Miaou.Core.Keys.Char " ") | Some Miaou.Core.Keys.Enter ->
      {s with switch = Switch.handle_key s.switch ~key:"Enter"}
  | _ -> s

let move s _ = s

let refresh s = s

let enter s = s

let service_select s _ = s

let service_cycle s _ = s

let handle_modal_key s _ ~size:_ = s

let next_page s = s.next_page

let keymap (_ : state) = []

let handled_keys () = []

let back s = go_back s

let has_modal _ = false
