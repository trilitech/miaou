(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

[@@@warning "-32-34-37-69"]

module W = Miaou_widgets_display.Widgets
module H = Miaou_helpers.Helpers

type direction = Row | Column

type align_items = Start | Center | End | Stretch

type justify = Start | Center | End | Space_between | Space_around

type spacing = {h : int; v : int}

type padding = {left : int; right : int; top : int; bottom : int}

type basis =
  | Auto
  | Px of int
  | Ratio of float
  | Percent of float
  | Fill

type size_hint = {width : int option; height : int option}

type child = {
  render : size:LTerm_geom.size -> string;
  basis : basis;
  cross : size_hint option;
}

type t = {
  direction : direction;
  align_items : align_items;
  justify : justify;
  gap : spacing;
  padding : padding;
  children : child list;
}

let default_padding = {left = 0; right = 0; top = 0; bottom = 0}

let default_gap = {h = 0; v = 0}

let create ?(direction = Row) ?(align_items : align_items = Start)
    ?(justify : justify = Start) ?(gap = default_gap)
    ?(padding = default_padding) children =
  {direction; align_items; justify; gap; padding; children}

let clamp v ~min_v ~max_v = max min_v (min max_v v)

let truncate_visible s width =
  let idx = H.visible_byte_index_of_pos s width in
  String.sub s 0 idx

let pad_lines lines ~width =
  List.map
    (fun line ->
      let vis = W.visible_chars_count line in
      if vis >= width then truncate_visible line width
      else line ^ String.make (width - vis) ' ')
    lines

let split_lines s = String.split_on_char '\n' s

let rec take n lst =
  if n <= 0 then []
  else match lst with [] -> [] | x :: xs -> x :: take (n - 1) xs

let pad_block lines ~width ~height =
  let lines = pad_lines lines ~width in
  let padded =
    if List.length lines >= height then lines
    else
      lines
      @ List.init (height - List.length lines) (fun _ ->
            String.make width ' ')
  in
  take height padded

let compute_sizes direction padding gap size children =
  let available_main =
    match direction with
    | Row ->
        size.LTerm_geom.cols - padding.left - padding.right
        - (max 0 ((List.length children - 1) * gap.h))
    | Column ->
        size.LTerm_geom.rows - padding.top - padding.bottom
        - (max 0 ((List.length children - 1) * gap.v))
  in
  let fixed, ratios, percents, fills =
    List.fold_left
      (fun (fix, rat, per, fil) c ->
        match c.basis with
        | Px n -> (fix + n, rat, per, fil)
        | Ratio r -> (fix, rat +. r, per, fil)
        | Percent p -> (fix, rat, per +. p, fil)
        | Fill -> (fix, rat, per, fil + 1)
        | Auto -> (fix, rat, per, fil + 1))
      (0, 0., 0., 0) children
  in
  let remaining =
    max 0 (available_main - fixed - int_of_float (percents *. float available_main /. 100.))
  in
  let alloc_child c =
    match c.basis with
    | Px n -> n
    | Ratio r when ratios > 0. ->
        int_of_float (r /. ratios *. float remaining)
    | Ratio _ -> 0
    | Percent p ->
        int_of_float (p /. 100. *. float available_main)
    | Fill | Auto ->
        if fills > 0 then remaining / max 1 fills else remaining
  in
  List.map alloc_child children

let distribute justify gap sizes =
  match justify with
  | Start -> (0, gap)
  | End -> (0, gap)
  | Center -> (0, gap)
  | Space_between ->
      let spaces =
        if List.length sizes <= 1 then gap else gap
      in
      (0, spaces)
  | Space_around -> (0, gap)

let render_row t ~size =
  let child_sizes = compute_sizes Row t.padding t.gap size t.children in
  let _offset, gap = distribute t.justify t.gap child_sizes in
  let max_h = size.LTerm_geom.rows - t.padding.top - t.padding.bottom in
  let rendered =
    List.map2
      (fun c w ->
        let child_size =
          {LTerm_geom.rows = max_h; cols = max 0 w}
        in
        let block = pad_block (split_lines (c.render ~size:child_size)) ~width:w ~height:max_h in
        block)
      t.children child_sizes
  in
  let lines =
    List.init max_h (fun row ->
        let buf = Buffer.create (size.LTerm_geom.cols + 2) in
        Buffer.add_string buf (String.make t.padding.left ' ') ;
        let rec emit idx blocks =
          match blocks with
          | [] -> ()
          | blk :: rest ->
              let line =
                match List.nth_opt blk row with Some s -> s | None -> ""
              in
              if idx > 0 then Buffer.add_string buf (String.make gap.h ' ') ;
              Buffer.add_string buf line ;
              emit (idx + 1) rest
        in
        emit 0 rendered ;
        Buffer.add_string buf (String.make t.padding.right ' ') ;
        Buffer.contents buf)
  in
  lines

let render_column t ~size =
  let child_sizes = compute_sizes Column t.padding t.gap size t.children in
  let max_w = size.LTerm_geom.cols - t.padding.left - t.padding.right in
  let blocks =
    List.map2
      (fun c h ->
        let child_size = {LTerm_geom.rows = max 0 h; cols = max_w} in
        let blk =
          pad_block (split_lines (c.render ~size:child_size)) ~width:max_w
            ~height:h
        in
        blk)
      t.children child_sizes
  in
  let rows =
    size.LTerm_geom.rows - t.padding.top - t.padding.bottom
  in
  let all_lines = List.concat blocks |> take rows in
  let with_pad =
    List.map
      (fun line ->
        let vis = W.visible_chars_count line in
        let pad_right = max 0 (size.LTerm_geom.cols - t.padding.left - t.padding.right - vis) in
        String.make t.padding.left ' ' ^ line ^ String.make pad_right ' ')
      all_lines
  in
  with_pad

let render t ~size =
  let lines =
    match t.direction with
    | Row -> render_row t ~size
    | Column -> render_column t ~size
  in
  String.concat "\n" lines
