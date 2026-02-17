(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

module W = Miaou_widgets_display.Widgets
module Helpers = Miaou_helpers.Helpers
module Style_context = Miaou_style.Style_context

type track =
  | Px of int
  | Fr of float
  | Percent of float
  | Auto
  | MinMax of int * int

type placement = {row : int; col : int; row_span : int; col_span : int}

type grid_child = {
  render : size:LTerm_geom.size -> string;
  placement : placement;
}

type t = {
  rows : track list;
  cols : track list;
  row_gap : int;
  col_gap : int;
  padding : Flex_layout.padding;
  children : grid_child list;
}

let default_padding : Flex_layout.padding =
  {left = 0; right = 0; top = 0; bottom = 0}

let create ~rows ~cols ?(row_gap = 0) ?(col_gap = 0)
    ?(padding = default_padding) children =
  {rows; cols; row_gap; col_gap; padding; children}

let cell ~row ~col render =
  {render; placement = {row; col; row_span = 1; col_span = 1}}

let span ~row ~col ~row_span ~col_span render =
  {render; placement = {row; col; row_span; col_span}}

(* Resolve track sizes to concrete pixel values. *)
let resolve_tracks tracks available =
  let n = List.length tracks in
  let sizes = Array.make n 0 in
  let used = ref 0 in
  (* Pass 1: fixed, percent, minmax base *)
  List.iteri
    (fun i t ->
      match t with
      | Px p ->
          let v = max 0 p in
          sizes.(i) <- v ;
          used := !used + v
      | Percent p ->
          let v = max 0 (int_of_float (p /. 100. *. float available)) in
          sizes.(i) <- v ;
          used := !used + v
      | MinMax (mn, _) ->
          let v = max 0 mn in
          sizes.(i) <- v ;
          used := !used + v
      | Fr _ | Auto -> ())
    tracks ;
  (* Pass 2: distribute remaining to Fr/Auto *)
  let remaining = max 0 (available - !used) in
  let total_fr =
    List.fold_left
      (fun acc t ->
        match t with Fr f -> acc +. f | Auto -> acc +. 1. | _ -> acc)
      0.
      tracks
  in
  if total_fr > 0. then
    List.iteri
      (fun i t ->
        match t with
        | Fr f ->
            sizes.(i) <- max 0 (int_of_float (f /. total_fr *. float remaining))
        | Auto ->
            sizes.(i) <-
              max 0 (int_of_float (1. /. total_fr *. float remaining))
        | _ -> ())
      tracks ;
  (* Pass 3: give leftover to MinMax up to their max *)
  let total_used = Array.fold_left ( + ) 0 sizes in
  let leftover = ref (max 0 (available - total_used)) in
  if !leftover > 0 then
    List.iteri
      (fun i t ->
        match t with
        | MinMax (_, mx) ->
            let room = max 0 (mx - sizes.(i)) in
            let give = min room !leftover in
            sizes.(i) <- sizes.(i) + give ;
            leftover := !leftover - give
        | _ -> ())
      tracks ;
  sizes

let split_lines s = String.split_on_char '\n' s

let truncate_visible s width =
  let idx = Helpers.visible_byte_index_of_pos s width in
  String.sub s 0 idx

let pad_line line width =
  let vis = W.visible_chars_count line in
  if vis >= width then truncate_visible line width
  else line ^ String.make (width - vis) ' '

let pad_block lines ~width ~height =
  let padded = List.map (fun l -> pad_line l width) lines in
  let len = List.length padded in
  if len >= height then List.filteri (fun i _ -> i < height) padded
  else padded @ List.init (height - len) (fun _ -> String.make width ' ')

(* Compute the pixel width of a column span including inner gaps. *)
let span_width col_sizes col_gap start count =
  let w = ref 0 in
  for c = start to start + count - 1 do
    w := !w + col_sizes.(c)
  done ;
  !w + max 0 ((count - 1) * col_gap)

(* Compute the pixel height of a row span including inner gaps. *)
let span_height row_sizes row_gap start count =
  let h = ref 0 in
  for r = start to start + count - 1 do
    h := !h + row_sizes.(r)
  done ;
  !h + max 0 ((count - 1) * row_gap)

let render t ~size =
  let inner_w = size.LTerm_geom.cols - t.padding.left - t.padding.right in
  let inner_h = size.LTerm_geom.rows - t.padding.top - t.padding.bottom in
  let n_rows = List.length t.rows in
  let n_cols = List.length t.cols in
  if n_rows = 0 || n_cols = 0 then ""
  else
    let col_gap_total = max 0 ((n_cols - 1) * t.col_gap) in
    let row_gap_total = max 0 ((n_rows - 1) * t.row_gap) in
    let col_sizes = resolve_tracks t.cols (max 0 (inner_w - col_gap_total)) in
    let row_sizes = resolve_tracks t.rows (max 0 (inner_h - row_gap_total)) in
    (* Pre-render all children into blocks of lines. *)
    let child_count = List.length t.children in
    let rendered =
      t.children
      |> List.mapi (fun idx child -> (idx, child))
      |> List.filter_map (fun (idx, child) ->
          let p = child.placement in
          if p.row < 0 || p.row >= n_rows || p.col < 0 || p.col >= n_cols then
            None
          else
            let rs = min p.row_span (n_rows - p.row) in
            let cs = min p.col_span (n_cols - p.col) in
            let w = span_width col_sizes t.col_gap p.col cs in
            let h = span_height row_sizes t.row_gap p.row rs in
            let child_size = {LTerm_geom.rows = max 0 h; cols = max 0 w} in
            (* Set up style context for this child with index info for :nth-child selectors *)
            let lines =
              Style_context.with_child_context
                ~widget_name:"grid-cell"
                ~index:idx
                ~count:child_count
                (fun () -> split_lines (child.render ~size:child_size))
            in
            let block = pad_block lines ~width:w ~height:h in
            Some (p, cs, rs, block))
    in
    (* Build a "covered" map: for each cell, which rendered child covers it
     and what is the column offset within the span. *)
    let owner = Array.init n_rows (fun _ -> Array.make n_cols None) in
    List.iter
      (fun (p, cs, rs, block) ->
        for r = p.row to p.row + rs - 1 do
          for c = p.col to p.col + cs - 1 do
            owner.(r).(c) <- Some (p, cs, block)
          done
        done)
      rendered ;
    (* Assemble output line by line. *)
    let buf = Buffer.create (inner_w * inner_h) in
    let left_pad = String.make t.padding.left ' ' in
    let blank_line = String.make inner_w ' ' in
    (* Top padding *)
    for _ = 1 to t.padding.top do
      Buffer.add_string buf left_pad ;
      Buffer.add_string buf blank_line ;
      Buffer.add_char buf '\n'
    done ;
    (* For each grid row *)
    for row = 0 to n_rows - 1 do
      let row_h = row_sizes.(row) in
      (* line offset within this grid row's portion of spanning blocks *)
      let row_line_offset =
        let off = ref 0 in
        (* lines consumed by prior rows in a row-spanning block are accounted
         for by computing the offset from the placement start row. *)
        off := 0 ;
        !off
      in
      ignore row_line_offset ;
      for line_idx = 0 to row_h - 1 do
        Buffer.add_string buf left_pad ;
        let col = ref 0 in
        while !col < n_cols do
          if !col > 0 then Buffer.add_string buf (String.make t.col_gap ' ') ;
          match owner.(row).(!col) with
          | None ->
              Buffer.add_string buf (String.make col_sizes.(!col) ' ') ;
              incr col
          | Some (p, cs, block) ->
              if !col = p.col then begin
                (* This is the start column of the span — output the full
                 span width from the pre-rendered block. *)
                let abs_line =
                  let off = ref 0 in
                  for r = p.row to row - 1 do
                    off := !off + row_sizes.(r) + t.row_gap
                  done ;
                  !off + line_idx
                in
                let line =
                  match List.nth_opt block abs_line with
                  | Some l -> l
                  | None ->
                      String.make (span_width col_sizes t.col_gap p.col cs) ' '
                in
                Buffer.add_string buf line ;
                col := !col + cs
              end
              else begin
                (* We're inside a span but not at its start column. The start
                 column already emitted the full span, so skip. However this
                 should not happen because we jump col by cs above. If it
                 does, emit blank. *)
                Buffer.add_string buf (String.make col_sizes.(!col) ' ') ;
                incr col
              end
        done ;
        if row < n_rows - 1 || line_idx < row_h - 1 then
          Buffer.add_char buf '\n'
      done ;
      (* Row gap *)
      if row < n_rows - 1 then
        for _ = 1 to t.row_gap do
          Buffer.add_char buf '\n' ;
          Buffer.add_string buf left_pad ;
          Buffer.add_string buf blank_line
        done
    done ;
    Buffer.contents buf
