(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

module Inner = struct
  let tutorial_title = "Flex Layout"

  let tutorial_markdown = [%blob "README.md"]

  module Flex = Miaou_widgets_layout.Flex_layout
  module W = Miaou_widgets_display.Widgets

  type state = {next_page : string option}

  type msg = unit

  let init () = {next_page = None}

  let render_box title basis ~size =
    String.concat
      "\n"
      [
        W.titleize title;
        W.dim
          (Printf.sprintf
             "slot %dx%d · %s"
             size.LTerm_geom.cols
             size.rows
             basis);
      ]

  let row size =
    let children =
      [
        {
          Flex.render = render_box "Fixed" "Px 10";
          basis = Flex.Px 10;
          cross = None;
        };
        {
          Flex.render = render_box "Percent" "30%";
          basis = Flex.Percent 30.;
          cross = None;
        };
        {
          Flex.render = render_box "Ratio" "2x share";
          basis = Flex.Ratio 2.;
          cross = None;
        };
        {
          Flex.render = render_box "Fill" "Auto";
          basis = Flex.Fill;
          cross = None;
        };
      ]
    in
    Flex.create
      ~direction:Flex.Row
      ~gap:{h = 2; v = 0}
      ~padding:{left = 2; right = 2; top = 0; bottom = 0}
      ~align_items:Flex.Center
      ~justify:Flex.Space_between
      children
    |> fun flex -> Flex.render flex ~size

  let column size =
    let children =
      [
        {
          Flex.render = render_box "Top" "Fill";
          basis = Flex.Fill;
          cross = Some {width = Some 24; height = None};
        };
        {
          Flex.render = render_box "Middle" "Percent 40%";
          basis = Flex.Percent 40.;
          cross = None;
        };
        {
          Flex.render = render_box "Bottom" "Px 3";
          basis = Flex.Px 3;
          cross = None;
        };
      ]
    in
    Flex.create
      ~direction:Flex.Column
      ~gap:{h = 0; v = 1}
      ~padding:{left = 2; right = 2; top = 1; bottom = 1}
      ~align_items:Flex.Center
      ~justify:Flex.Center
      children
    |> fun flex -> Flex.render flex ~size

  let update s _ = s

  let view _ ~focus:_ ~size =
    let header = W.titleize "Flex layout (Esc returns, t opens tutorial)" in
    let desc =
      W.dim
        "Row: px + percent + ratio + fill with gaps | Column: centered \
         children. Resize to see wrap/stretch."
    in
    let row_height =
      if size.LTerm_geom.rows < 20 then 4 else max 4 (size.LTerm_geom.rows / 3)
    in
    let col_height =
      if size.LTerm_geom.rows < 20 then 6 else max 8 (size.LTerm_geom.rows / 2)
    in
    let row_block =
      row {LTerm_geom.cols = size.LTerm_geom.cols; rows = row_height}
    in
    let col_block =
      column {LTerm_geom.cols = size.LTerm_geom.cols; rows = col_height}
    in
    String.concat "\n\n" [header; desc; row_block; col_block]

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
