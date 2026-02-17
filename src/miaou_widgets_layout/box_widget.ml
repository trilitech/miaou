(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

[@@@warning "-32-34-37-69"]

module W = Miaou_widgets_display.Widgets
module H = Miaou_helpers.Helpers

type border_style = Single | Double | Rounded | Ascii | Heavy

type padding = {left : int; right : int; top : int; bottom : int}

type border_colors = {
  c_top : int option;
  c_bottom : int option;
  c_left : int option;
  c_right : int option;
}

type border_chars = {
  tl : string;
  tr : string;
  bl : string;
  br : string;
  h : string;
  v : string;
}

let single =
  {
    tl = "\xe2\x94\x8c";
    tr = "\xe2\x94\x90";
    bl = "\xe2\x94\x94";
    br = "\xe2\x94\x98";
    h = "\xe2\x94\x80";
    v = "\xe2\x94\x82";
  }

let double =
  {
    tl = "\xe2\x95\x94";
    tr = "\xe2\x95\x97";
    bl = "\xe2\x95\x9a";
    br = "\xe2\x95\x9d";
    h = "\xe2\x95\x90";
    v = "\xe2\x95\x91";
  }

let rounded =
  {
    tl = "\xe2\x95\xad";
    tr = "\xe2\x95\xae";
    bl = "\xe2\x95\xb0";
    br = "\xe2\x95\xaf";
    h = "\xe2\x94\x80";
    v = "\xe2\x94\x82";
  }

let heavy =
  {
    tl = "\xe2\x94\x8f";
    tr = "\xe2\x94\x93";
    bl = "\xe2\x94\x97";
    br = "\xe2\x94\x9b";
    h = "\xe2\x94\x81";
    v = "\xe2\x94\x83";
  }

let ascii_chars = {tl = "+"; tr = "+"; bl = "+"; br = "+"; h = "-"; v = "|"}

let resolve_chars style =
  if Lazy.force W.use_ascii_borders then ascii_chars
  else
    match style with
    | Single -> single
    | Double -> double
    | Rounded -> rounded
    | Heavy -> heavy
    | Ascii -> ascii_chars

let repeat s n =
  let buf = Buffer.create (max 0 n * String.length s) in
  for _ = 1 to max 0 n do
    Buffer.add_string buf s
  done ;
  Buffer.contents buf

let render ?(title = "") ?(style = Single)
    ?(padding = {left = 0; right = 0; top = 0; bottom = 0}) ?height ?color
    ?border_colors ~width content =
  let bc = resolve_chars style in
  let inner_w = max 0 (width - 2) in
  let content_w = max 0 (inner_w - padding.left - padding.right) in
  (* Color helpers: border_colors takes precedence over color.
     When no explicit color is provided, use themed border styling. *)
  let color_with c s =
    match c with Some col -> W.fg col s | None -> W.themed_border s
  in
  let color_top s =
    match border_colors with
    | Some {c_top = Some c; _} -> W.fg c s
    | _ -> color_with color s
  in
  let color_bottom s =
    match border_colors with
    | Some {c_bottom = Some c; _} -> W.fg c s
    | _ -> color_with color s
  in
  let color_left s =
    match border_colors with
    | Some {c_left = Some c; _} -> W.fg c s
    | _ -> color_with color s
  in
  let color_right s =
    match border_colors with
    | Some {c_right = Some c; _} -> W.fg c s
    | _ -> color_with color s
  in
  (* Corner colors: use adjacent side colors, preferring top/bottom for corners *)
  let color_tl s =
    match border_colors with
    | Some {c_top = Some c; _} -> W.fg c s
    | Some {c_left = Some c; _} -> W.fg c s
    | _ -> color_with color s
  in
  let color_tr s =
    match border_colors with
    | Some {c_top = Some c; _} -> W.fg c s
    | Some {c_right = Some c; _} -> W.fg c s
    | _ -> color_with color s
  in
  let color_bl s =
    match border_colors with
    | Some {c_bottom = Some c; _} -> W.fg c s
    | Some {c_left = Some c; _} -> W.fg c s
    | _ -> color_with color s
  in
  let color_br s =
    match border_colors with
    | Some {c_bottom = Some c; _} -> W.fg c s
    | Some {c_right = Some c; _} -> W.fg c s
    | _ -> color_with color s
  in
  (* Top border *)
  let top_border =
    if title <> "" then
      let t = W.themed_emphasis (" " ^ title ^ " ") in
      let t_vis = H.visible_chars_count t in
      let remaining = max 0 (inner_w - 1 - t_vis) in
      color_tl bc.tl ^ color_top bc.h ^ t
      ^ color_top (repeat bc.h remaining)
      ^ color_tr bc.tr
    else color_tl bc.tl ^ color_top (repeat bc.h inner_w) ^ color_tr bc.tr
  in
  (* Bottom border *)
  let bottom_border =
    color_bl bc.bl ^ color_bottom (repeat bc.h inner_w) ^ color_br bc.br
  in
  (* Content lines *)
  let raw_lines =
    if content = "" then [""] else String.split_on_char '\n' content
  in
  let pad_left_str = String.make padding.left ' ' in
  let pad_right_str = String.make padding.right ' ' in
  let format_line line =
    let vis = H.visible_chars_count line in
    let truncated =
      if vis > content_w then
        let byte_idx =
          H.visible_byte_index_of_pos line (max 0 (content_w - 1))
        in
        String.sub line 0 byte_idx ^ "\xe2\x80\xa6"
      else line
    in
    let padded = H.pad_to_width truncated content_w ' ' in
    let inner = pad_left_str ^ padded ^ pad_right_str in
    let inner = W.themed_contextual_fill inner in
    color_left bc.v ^ inner ^ color_right bc.v
  in
  let content_rows = List.map format_line raw_lines in
  (* Add padding rows *)
  let empty_row =
    let inner = String.make inner_w ' ' |> W.themed_contextual_fill in
    color_left bc.v ^ inner ^ color_right bc.v
  in
  let top_pad_rows = List.init padding.top (fun _ -> empty_row) in
  let bottom_pad_rows = List.init padding.bottom (fun _ -> empty_row) in
  let body_rows = top_pad_rows @ content_rows @ bottom_pad_rows in
  (* Apply height constraint *)
  let body_rows =
    match height with
    | None -> body_rows
    | Some h ->
        let target = max 0 (h - 2) in
        let len = List.length body_rows in
        if len > target then List.filteri (fun i _ -> i < target) body_rows
        else if len < target then
          let extra = List.init (target - len) (fun _ -> empty_row) in
          body_rows @ extra
        else body_rows
  in
  H.concat_lines ([top_border] @ body_rows @ [bottom_border])
