(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

module C = Miaou_canvas.Canvas

let border_styles = [|C.Single; C.Double; C.Rounded; C.Heavy; C.Ascii|]

let border_style_name = function
  | C.Single -> "Single"
  | C.Double -> "Double"
  | C.Rounded -> "Rounded"
  | C.Heavy -> "Heavy"
  | C.Ascii -> "Ascii"

type color_scheme = {
  title_fg : int;
  box_fg : int;
  label_fg : int;
  fill_fg : int;
  fill_bg : int;
  overlay_fg : int;
}

let color_schemes =
  [|
    {
      title_fg = 81;
      box_fg = 75;
      label_fg = 255;
      fill_fg = 240;
      fill_bg = -1;
      overlay_fg = 214;
    };
    {
      title_fg = 212;
      box_fg = 204;
      label_fg = 230;
      fill_fg = 96;
      fill_bg = -1;
      overlay_fg = 156;
    };
    {
      title_fg = 120;
      box_fg = 34;
      label_fg = 194;
      fill_fg = 22;
      fill_bg = -1;
      overlay_fg = 226;
    };
  |]

let color_scheme_name i =
  match i with 0 -> "Ocean" | 1 -> "Rose" | 2 -> "Forest" | _ -> "Unknown"

module Inner = struct
  let tutorial_title = "Canvas"

  let tutorial_markdown = [%blob "README.md"]

  type state = {border_idx : int; color_idx : int; next_page : string option}

  type msg = unit

  let init () = {border_idx = 0; color_idx = 0; next_page = None}

  let update s (_ : msg) = s

  let view s ~focus:_ ~size =
    let cols = size.LTerm_geom.cols in
    let rows = size.LTerm_geom.rows in
    let border = border_styles.(s.border_idx) in
    let cs = color_schemes.(s.color_idx) in

    (* Canvas sized to terminal *)
    let c_rows = max 4 (rows - 2) in
    let c_cols = max 20 (min cols 120) in
    let c = C.create ~rows:c_rows ~cols:c_cols in

    let title_style = {C.default_style with fg = cs.title_fg; bold = true} in
    let box_style = {C.default_style with fg = cs.box_fg} in
    let label_style = {C.default_style with fg = cs.label_fg; bold = true} in
    let fill_style = {C.default_style with fg = cs.fill_fg; bg = cs.fill_bg} in
    let dim_style = {C.default_style with fg = 245; dim = true} in
    let overlay_style =
      {C.default_style with fg = cs.overlay_fg; bold = true}
    in

    (* Title *)
    let title = "Canvas Demo" in
    let title_col = max 0 ((c_cols - String.length title) / 2) in
    C.draw_text c ~row:0 ~col:title_col ~style:title_style title ;

    (* Box 1: Border showcase *)
    let box1_w = min 30 ((c_cols / 2) - 2) in
    let box1_h = min 8 (c_rows - 6) in
    if box1_w >= 4 && box1_h >= 4 then begin
      C.draw_box
        c
        ~row:2
        ~col:1
        ~width:box1_w
        ~height:box1_h
        ~border
        ~style:box_style ;
      let label = Printf.sprintf "Border: %s" (border_style_name border) in
      C.draw_text c ~row:3 ~col:3 ~style:label_style label ;
      (* Fill interior with pattern *)
      let fill_row_start = 4 in
      let fill_row_end = min (2 + box1_h - 2) (c_rows - 1) in
      for r = fill_row_start to fill_row_end do
        for col = 3 to min (box1_w - 2) (c_cols - 1) do
          let ch =
            if (r + col) mod 4 = 0 then "\xe2\x96\x91"
            else if (r + col) mod 4 = 2 then "\xe2\x96\x92"
            else " "
          in
          if ch <> " " then C.set_char c ~row:r ~col ~char:ch ~style:fill_style
        done
      done
    end ;

    (* Box 2: Color info *)
    let box2_col = max (box1_w + 3) ((c_cols / 2) + 1) in
    let box2_w = min 30 (c_cols - box2_col - 1) in
    let box2_h = min 8 (c_rows - 6) in
    if box2_w >= 4 && box2_h >= 4 then begin
      C.draw_box
        c
        ~row:2
        ~col:box2_col
        ~width:box2_w
        ~height:box2_h
        ~border
        ~style:box_style ;
      let scheme_label =
        Printf.sprintf "Colors: %s" (color_scheme_name s.color_idx)
      in
      C.draw_text c ~row:3 ~col:(box2_col + 2) ~style:label_style scheme_label ;
      (* Color swatches *)
      let swatch_row = 5 in
      if swatch_row < 2 + box2_h - 1 then begin
        let swatch_styles =
          [|
            ("Title", {C.default_style with fg = cs.title_fg});
            ("Box", {C.default_style with fg = cs.box_fg});
            ("Overlay", {C.default_style with fg = cs.overlay_fg});
          |]
        in
        let sc = ref (box2_col + 2) in
        Array.iter
          (fun (name, sty) ->
            let block = "\xe2\x96\x88\xe2\x96\x88" in
            C.draw_text
              c
              ~row:swatch_row
              ~col:!sc
              ~style:{sty with bold = true}
              block ;
            C.draw_text c ~row:swatch_row ~col:(!sc + 2) ~style:dim_style name ;
            sc := !sc + 2 + String.length name + 1)
          swatch_styles
      end
    end ;

    (* Layer compositing demo: small overlay canvases composed onto main canvas *)
    let overlay_row = max (2 + box1_h + 1) 11 in
    if overlay_row + 5 < c_rows then begin
      let ov_back = C.create ~rows:3 ~cols:22 in
      C.draw_box
        ov_back
        ~row:0
        ~col:0
        ~width:22
        ~height:3
        ~border:Rounded
        ~style:{overlay_style with dim = true} ;
      C.draw_text
        ov_back
        ~row:1
        ~col:2
        ~style:{overlay_style with dim = true}
        "Layer 1 (back)" ;

      let ov_front = C.create ~rows:3 ~cols:19 in
      C.draw_box
        ov_front
        ~row:0
        ~col:0
        ~width:19
        ~height:3
        ~border:Rounded
        ~style:overlay_style ;
      C.draw_text ov_front ~row:1 ~col:2 ~style:overlay_style "Layer 2 (front)" ;

      C.compose
        ~dst:c
        ~layers:
          [
            {C.canvas = ov_back; row = overlay_row; col = 2; opaque = false};
            {
              C.canvas = ov_front;
              row = overlay_row + 1;
              col = 10;
              opaque = false;
            };
          ] ;

      C.draw_text
        c
        ~row:(overlay_row + 3)
        ~col:2
        ~style:dim_style
        "^ composited via Canvas.compose"
    end ;

    (* Horizontal line across bottom *)
    let hline_row = c_rows - 3 in
    if hline_row > 2 then begin
      let bc = C.border_chars_of_style border in
      C.draw_hline
        c
        ~row:hline_row
        ~col:1
        ~len:(c_cols - 2)
        ~char:bc.h
        ~style:box_style
    end ;

    (* Status line *)
    let status =
      Printf.sprintf "b:border  c:colors  layers:compose  t:tutorial  Esc:back"
    in
    let status_row = c_rows - 1 in
    C.draw_text c ~row:status_row ~col:1 ~style:dim_style status ;

    C.to_ansi c

  let go_back s =
    {s with next_page = Some Demo_shared.Demo_config.launcher_page_name}

  let handle_key s key_str ~size:_ =
    match Miaou.Core.Keys.of_string key_str with
    | Some Miaou.Core.Keys.Escape -> go_back s
    | Some (Miaou.Core.Keys.Char k) when String.lowercase_ascii k = "b" ->
        let border_idx = (s.border_idx + 1) mod Array.length border_styles in
        {s with border_idx}
    | Some (Miaou.Core.Keys.Char k) when String.lowercase_ascii k = "c" ->
        let color_idx = (s.color_idx + 1) mod Array.length color_schemes in
        {s with color_idx}
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
