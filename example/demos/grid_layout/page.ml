(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

module Inner = struct
  let tutorial_title = "Grid Layout"

  let tutorial_markdown = [%blob "README.md"]

  module Grid = Miaou_widgets_layout.Grid_layout
  module W = Miaou_widgets_display.Widgets

  type state = {next_page : string option}

  type msg = unit

  let init () = {next_page = None}

  let render_cell label ~size =
    let header = W.titleize label in
    let info =
      W.dim (Printf.sprintf "%dx%d" size.LTerm_geom.cols size.LTerm_geom.rows)
    in
    String.concat "\n" [header; info]

  let update s _ = s

  let view _ ~focus:_ ~size =
    let header = W.titleize "Grid Layout (Esc returns, t opens tutorial)" in
    let desc =
      W.dim
        "Header spanning 2 cols | Sidebar (fixed 20) + Main (Fr 1.) | Footer \
         spanning 2 cols"
    in
    let grid_h = max 8 (size.LTerm_geom.rows - 5) in
    let grid_size = {LTerm_geom.cols = size.LTerm_geom.cols; rows = grid_h} in
    let grid =
      Grid.create
        ~rows:[Grid.Px 3; Grid.Fr 1.; Grid.Px 1]
        ~cols:[Grid.Px 20; Grid.Fr 1.]
        ~col_gap:1
        [
          Grid.span ~row:0 ~col:0 ~row_span:1 ~col_span:2 (render_cell "Header");
          Grid.cell ~row:1 ~col:0 (render_cell "Sidebar");
          Grid.cell ~row:1 ~col:1 (render_cell "Main");
          Grid.span ~row:2 ~col:0 ~row_span:1 ~col_span:2 (render_cell "Footer");
        ]
    in
    let grid_block = Grid.render grid ~size:grid_size in
    String.concat "\n\n" [header; desc; grid_block]

  let go_back = {next_page = Some Demo_shared.Demo_config.launcher_page_name}

  let handle_key s key_str ~size:_ =
    match Miaou.Core.Keys.of_string key_str with
    | Some Miaou.Core.Keys.Escape -> go_back
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

include Demo_shared.Demo_page.MakeSimple (Inner)
