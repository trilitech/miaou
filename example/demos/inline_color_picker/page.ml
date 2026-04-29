(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

module Inner = struct
  let tutorial_title = "Inline Color Picker"

  let tutorial_markdown = [%blob "README.md"]

  module Responsive = Miaou_widgets_layout.Responsive
  module W = Miaou_widgets_display.Widgets

  let palette =
    [|
      "Black";
      "Red";
      "Green";
      "Yellow";
      "Blue";
      "Magenta";
      "Cyan";
      "White";
      "Bright Black";
      "Bright Red";
      "Bright Green";
      "Bright Yellow";
      "Bright Blue";
      "Bright Magenta";
      "Bright Cyan";
      "Bright White";
    |]

  let palette_size = Array.length palette

  type state = {
    cursor : int; (* 0..15 *)
    chosen : int option;
    next_page : string option;
  }

  type msg = unit

  let init () = {cursor = 0; chosen = None; next_page = None}

  let update s _ = s

  (* Layout describes the grid shape: (cols, rows). *)
  type layout = {cols : int; rows : int}

  let wide_grid = {cols = 8; rows = 2}

  let narrow_grid = {cols = 4; rows = 4}

  let pick_layout ~width =
    Responsive.pick
      ~width
      ~default:wide_grid
      [{Responsive.max_width = 59; layout = narrow_grid}]

  (* Convert linear index <-> (row,col) under [layout]. *)
  let idx_of_pos {cols; rows = _} ~row ~col = (row * cols) + col

  let pos_of_idx {cols; rows = _} idx = (idx / cols, idx mod cols)

  let move_cursor layout cursor ~drow ~dcol =
    let row, col = pos_of_idx layout cursor in
    let row' = (row + drow + layout.rows) mod layout.rows in
    let col' = (col + dcol + layout.cols) mod layout.cols in
    let idx = idx_of_pos layout ~row:row' ~col:col' in
    if idx < palette_size then idx else cursor

  let render_swatch ~selected ~chosen idx =
    let label = Printf.sprintf "%2d" idx in
    (* Use bg color = idx, fg = white(231) or black(232) for legibility. *)
    let fg = if idx = 7 || idx = 15 || idx = 11 then 232 else 231 in
    let body = " " ^ label ^ " " in
    let body = W.fg fg (W.bg idx body) in
    let frame = if selected then ">" else if chosen then "*" else " " in
    frame ^ body ^ frame

  let render_grid s layout =
    let lines = Array.make layout.rows "" in
    for row = 0 to layout.rows - 1 do
      let cells = ref [] in
      for col = 0 to layout.cols - 1 do
        let idx = idx_of_pos layout ~row ~col in
        if idx < palette_size then
          let selected = idx = s.cursor in
          let chosen = s.chosen = Some idx in
          cells := render_swatch ~selected ~chosen idx :: !cells
      done ;
      lines.(row) <- String.concat " " (List.rev !cells)
    done ;
    String.concat "\n" (Array.to_list lines)

  let view s ~focus:_ ~size =
    let layout = pick_layout ~width:size.LTerm_geom.cols in
    let header = W.titleize "Inline Color Picker" in
    let bp_label =
      if layout.cols = 8 then "WIDE (>= 60): 8x2 grid"
      else "NARROW (< 60): 4x4 grid"
    in
    let bp =
      W.themed_emphasis
        (Printf.sprintf "Layout: %s [%d cols]" bp_label size.LTerm_geom.cols)
    in
    let hint =
      W.themed_muted
        "Arrows / hjkl move · Enter confirms · r resets · q/Esc quit · t \
         tutorial"
    in
    let grid = render_grid s layout in
    let cursor_line =
      let name = palette.(s.cursor) in
      W.themed_text "Cursor: "
      ^ W.themed_emphasis (Printf.sprintf "%d (%s)" s.cursor name)
    in
    let chosen_line =
      match s.chosen with
      | None -> W.themed_muted "(no choice yet)"
      | Some idx ->
          W.themed_text "Chosen: "
          ^ W.themed_emphasis (Printf.sprintf "%d (%s)" idx palette.(idx))
    in
    String.concat
      "\n"
      [header; bp; hint; ""; grid; ""; cursor_line; chosen_line]

  let go_back s =
    {s with next_page = Some Demo_shared.Demo_config.launcher_page_name}

  let handle_key s key_str ~size =
    let layout = pick_layout ~width:size.LTerm_geom.cols in
    match key_str with
    | "Esc" | "Escape" | "q" | "Q" -> go_back s
    | "Enter" | " " | "Space" -> {s with chosen = Some s.cursor}
    | "r" | "R" -> {s with chosen = None; cursor = 0}
    | "Left" | "h" ->
        {s with cursor = move_cursor layout s.cursor ~drow:0 ~dcol:(-1)}
    | "Right" | "l" ->
        {s with cursor = move_cursor layout s.cursor ~drow:0 ~dcol:1}
    | "Up" | "k" ->
        {s with cursor = move_cursor layout s.cursor ~drow:(-1) ~dcol:0}
    | "Down" | "j" ->
        {s with cursor = move_cursor layout s.cursor ~drow:1 ~dcol:0}
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
end

include Demo_shared.Demo_page.MakeSimple (Inner)
