(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

module Inner = struct
  let tutorial_title = "Spinner & Progress"

  let tutorial_markdown = [%blob "README.md"]

  module Spinner = Miaou_widgets_layout.Spinner_widget
  module Progress = Miaou_widgets_layout.Progress_widget

  type state = {
    spinner : Spinner.t;
    blocks_right : Spinner.t;
    blocks_left : Spinner.t;
    circles : Spinner.t;
    progress : Progress.t;
    pct : float;
    running : bool;
    next_page : string option;
  }

  type msg = unit

  let init () =
    let spinner = Spinner.open_centered ~label:"Fetching data" () in
    let blocks_right =
      Spinner.open_centered
        ~style:Spinner.Blocks
        ~direction:Spinner.Right
        ~glyph:Spinner.Square
        ~blocks_count:6
        ~label:"Build"
        ()
    in
    let blocks_left =
      Spinner.open_centered
        ~style:Spinner.Blocks
        ~direction:Spinner.Left
        ~glyph:Spinner.Square
        ~blocks_count:6
        ~label:"Deploy"
        ()
    in
    let circles =
      Spinner.open_centered
        ~style:Spinner.Blocks
        ~direction:Spinner.Right
        ~glyph:Spinner.Circle
        ~blocks_count:5
        ~label:"Processing"
        ()
    in
    let progress = Progress.open_inline ~width:30 ~label:"Download" () in
    {
      spinner;
      blocks_right;
      blocks_left;
      circles;
      progress;
      pct = 0.;
      running = true;
      next_page = None;
    }

  let update s _ = s

  let view s ~focus:_ ~size =
    let progress_line = Progress.render s.progress ~cols:size.LTerm_geom.cols in
    let spinner_line = Spinner.render s.spinner in
    let blocks_right_line = Spinner.render s.blocks_right in
    let blocks_left_line = Spinner.render s.blocks_left in
    let circles_line = Spinner.render s.circles in
    let lines =
      [
        "Space: toggle run • r: reset • t: tutorial • Esc: back";
        "";
        "Dots spinner:";
        "  " ^ spinner_line;
        "";
        "Blocks (right):";
        "  " ^ blocks_right_line;
        "";
        "Blocks (left):";
        "  " ^ blocks_left_line;
        "";
        "Circles:";
        "  " ^ circles_line;
        "";
        "Progress bar:";
        "  " ^ progress_line;
      ]
    in
    String.concat "\n" lines

  let go_back s =
    {s with next_page = Some Demo_shared.Demo_config.launcher_page_name}

  let handle_key s key_str ~size:_ =
    match Miaou.Core.Keys.of_string key_str with
    | Some (Miaou.Core.Keys.Char "Esc") | Some (Miaou.Core.Keys.Char "Escape")
      ->
        go_back s
    | Some (Miaou.Core.Keys.Char " ") -> {s with running = not s.running}
    | Some (Miaou.Core.Keys.Char "r") ->
        let progress = Progress.set_progress s.progress 0. in
        {s with pct = 0.; progress; running = true}
    | _ -> s

  let move s _ = s

  let advance s =
    if s.running then
      let spinner = Spinner.tick s.spinner in
      let blocks_right = Spinner.tick s.blocks_right in
      let blocks_left = Spinner.tick s.blocks_left in
      let circles = Spinner.tick s.circles in
      let pct = min 1. (s.pct +. 0.02) in
      let progress = Progress.set_progress s.progress pct in
      {
        s with
        spinner;
        blocks_right;
        blocks_left;
        circles;
        pct;
        progress;
        running = pct < 1.;
      }
    else s

  let refresh s = advance s

  let enter s = s

  let service_select s _ = s

  let service_cycle s _ = advance s

  let handle_modal_key s _ ~size:_ = s

  let next_page s = s.next_page

  let keymap (_ : state) = []

  let handled_keys () = []

  let back s = go_back s

  let has_modal _ = false
end

include Demo_shared.Demo_page.MakeSimple (Inner)
