(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

module Inner = struct
  let tutorial_title = "Layout Helpers"

  let tutorial_markdown = [%blob "README.md"]

  type state = {next_page : string option}

  type msg = unit

  let init () = {next_page = None}

  let update s _ = s

  let view _ ~focus:_ ~size =
    let module Pane = Miaou_widgets_layout.Pane_layout in
    let module Vsection = Miaou_widgets_layout.Vsection in
    let cols = max 40 size.LTerm_geom.cols in
    let pane =
      Pane.create
        ~left:"Services\n- API: healthy\n- Worker: syncing\n- Scheduler: idle"
        ~right:"Latest logs\nINFO ready\nWARN sync lag\nINFO checkpoint"
        ~left_ratio:0.45
        ()
    in
    let split = Pane.render pane cols in
    let section =
      Vsection.render
        ~size:{size with LTerm_geom.rows = min 20 size.LTerm_geom.rows}
        ~header:["Vsection layout"; "Child area shown between rulers"]
        ~footer:["Footer area"; "Esc returns, t opens tutorial"]
        ~child:(fun inner ->
          Printf.sprintf "Inner area: %d x %d" inner.rows inner.cols)
    in
    String.concat
      "\n\n"
      ["Layout helpers (Esc returns, t opens tutorial)"; split; section]

  let go_back = {next_page = Some Demo_shared.Demo_config.launcher_page_name}

  let handle_key s key_str ~size:_ =
    match Miaou.Core.Keys.of_string key_str with
    | Some (Miaou.Core.Keys.Char "Esc") | Some (Miaou.Core.Keys.Char "Escape")
      ->
        go_back
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

  let back _ = go_back

  let has_modal _ = false
end

include Demo_shared.Demo_page.Make (Inner)
