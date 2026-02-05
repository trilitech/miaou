(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

module Inner = struct
  let tutorial_title = "Box Widget"

  let tutorial_markdown = [%blob "README.md"]

  module BW = Miaou_widgets_layout.Box_widget
  module W = Miaou_widgets_display.Widgets
  module Flex = Miaou_widgets_layout.Flex_layout

  type state = {next_page : string option}

  type msg = unit

  let init () = {next_page = None}

  let update s _ = s

  let view _s ~focus:_ ~size =
    let header = W.titleize "Box Widget (Esc returns, t opens tutorial)" in
    let cols = size.LTerm_geom.cols in
    let box_w = min 35 ((cols / 2) - 2) in
    let single_box =
      BW.render ~title:"Single" ~style:Single ~width:box_w "Hello, world!"
    in
    let double_box =
      BW.render
        ~title:"Double"
        ~style:Double
        ~color:75
        ~width:box_w
        "Blue border"
    in
    let pad = {BW.left = 1; right = 1; top = 1; bottom = 1} in
    let rounded_box =
      BW.render
        ~title:"Rounded"
        ~style:Rounded
        ~padding:pad
        ~width:box_w
        "With padding"
    in
    let inner =
      BW.render ~style:Single ~width:(max 10 (box_w - 4)) "Inner box"
    in
    let nested_box =
      BW.render ~title:"Nested" ~style:Single ~width:box_w inner
    in
    let ascii_box =
      BW.render ~title:"ASCII" ~style:Ascii ~width:box_w "Fallback style"
    in
    let left_col = single_box ^ "\n\n" ^ double_box ^ "\n\n" ^ ascii_box in
    let right_col = rounded_box ^ "\n\n" ^ nested_box in
    let left_child =
      {
        Flex.render = (fun ~size:_ -> left_col);
        basis = Flex.Px box_w;
        cross = None;
      }
    in
    let right_child =
      {
        Flex.render = (fun ~size:_ -> right_col);
        basis = Flex.Fill;
        cross = None;
      }
    in
    let panels =
      Flex.create
        ~direction:Flex.Row
        ~gap:{h = 2; v = 0}
        ~padding:{left = 1; right = 1; top = 0; bottom = 0}
        [left_child; right_child]
    in
    let panel_size =
      {LTerm_geom.cols; rows = max 10 (size.LTerm_geom.rows - 4)}
    in
    let body = Flex.render panels ~size:panel_size in
    let controls = W.dim "Esc: return • t: tutorial" in
    String.concat "\n" [header; ""; body; ""; controls]

  let go_back _s = {next_page = Some Demo_shared.Demo_config.launcher_page_name}

  let handle_key s key_str ~size:_ =
    match key_str with "Esc" | "Escape" -> go_back s | _ -> s

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
end

include Demo_shared.Demo_page.Make (Inner)
