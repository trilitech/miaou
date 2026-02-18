(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(** Terminal text selection for the Matrix driver.

    Handles mouse-based text selection with visual highlighting and
    clipboard integration. Selection is drawn as an overlay on the
    rendered buffer using reverse video style. *)

module Clipboard = Miaou_interfaces.Clipboard

type point = {row : int; col : int}

(** Click mode for double/triple click detection *)
type click_mode = Single | Word | Line

type t = {
  mutable anchor : point option;
      (** Starting point of selection (where mouse was pressed) *)
  mutable current : point option;
      (** Current end point of selection (where mouse is now) *)
  mutable active : bool;  (** Whether a selection drag is in progress *)
  mutable last_click_time : float;
      (** Time of last click for multi-click detection *)
  mutable last_click_pos : point option;  (** Position of last click *)
  mutable click_count : int;
      (** Number of rapid clicks (1=single, 2=double, 3=triple) *)
  mutable click_mode : click_mode;
      (** Current selection mode based on click count *)
}

(** Maximum time between clicks to count as multi-click (seconds) *)
let multi_click_threshold = 0.4

(** Maximum distance between clicks to count as multi-click *)
let multi_click_distance = 2

let create () =
  {
    anchor = None;
    current = None;
    active = false;
    last_click_time = 0.0;
    last_click_pos = None;
    click_count = 0;
    click_mode = Single;
  }

let is_active t = t.active

let has_selection t =
  match (t.anchor, t.current) with Some _, Some _ -> true | _ -> false

let is_single_point t =
  match (t.anchor, t.current) with
  | Some a, Some c ->
      (* Consider it a single point (click, not selection) if anchor == current,
         regardless of click_mode. This allows double-clicks to be passed to widgets
         instead of being captured for word selection. Word/line selection only
         makes sense when the user drags. *)
      a.row = c.row && a.col = c.col
  | _ -> false

let is_multi_click t = t.click_count >= 2

let click_count t = t.click_count

(** Normalize selection bounds to (start, end) where start <= end.
    Selection is treated as a linear range through the buffer. *)
let get_bounds t =
  match (t.anchor, t.current) with
  | Some a, Some c ->
      let a_linear = (a.row, a.col) in
      let c_linear = (c.row, c.col) in
      if a_linear <= c_linear then Some (a, c) else Some (c, a)
  | _ -> None

(** Check if a cell is within the current selection. *)
let is_selected t ~row ~col =
  match get_bounds t with
  | None -> false
  | Some (start, stop) ->
      let pos = (row, col) in
      let start_pos = (start.row, start.col) in
      let stop_pos = (stop.row, stop.col) in
      pos >= start_pos && pos <= stop_pos

(** Check if a character is part of a word (not whitespace or box-drawing) *)
let is_word_char ch =
  let len = String.length ch in
  if len = 0 then false
  else if len = 1 then
    let c = ch.[0] in
    (c >= 'a' && c <= 'z')
    || (c >= 'A' && c <= 'Z')
    || (c >= '0' && c <= '9')
    || c = '_' || c = '-'
  else
    (* Multi-byte UTF-8: assume it's a word char unless it's box-drawing *)
    let code = Char.code ch.[0] in
    (* Box-drawing chars are in U+2500-U+257F, which starts with 0xE2 0x94 or 0xE2 0x95 *)
    not
      (len >= 3 && code = 0xE2
      && (Char.code ch.[1] = 0x94 || Char.code ch.[1] = 0x95))

(** Check if a character is a box-drawing character *)
let is_box_char ch =
  let len = String.length ch in
  if len >= 3 then
    let c0 = Char.code ch.[0] in
    let c1 = Char.code ch.[1] in
    (* Box-drawing: U+2500-U+257F = E2 94 80 to E2 95 BF *)
    c0 = 0xE2 && (c1 = 0x94 || c1 = 0x95)
  else false

(** Find word boundaries at the given position *)
let find_word_bounds ~get_char ~col ~cols =
  let start_col = ref col in
  let end_col = ref col in
  (* Find start of word *)
  while !start_col > 0 && is_word_char (get_char ~col:(!start_col - 1)) do
    decr start_col
  done ;
  (* Find end of word *)
  while !end_col < cols - 1 && is_word_char (get_char ~col:(!end_col + 1)) do
    incr end_col
  done ;
  (!start_col, !end_col)

(** Find line boundaries, stopping at box-drawing characters *)
let find_line_bounds ~get_char ~col ~cols =
  let start_col = ref col in
  let end_col = ref col in
  (* Find start of line segment (stop at box chars) *)
  while !start_col > 0 && not (is_box_char (get_char ~col:(!start_col - 1))) do
    decr start_col
  done ;
  (* Find end of line segment (stop at box chars) *)
  while
    !end_col < cols - 1 && not (is_box_char (get_char ~col:(!end_col + 1)))
  do
    incr end_col
  done ;
  (!start_col, !end_col)

(** Start a new selection at the given position.
    Handles single/double/triple click for char/word/line selection. *)
let start_selection t ~row ~col ~get_char ~cols =
  let now = Unix.gettimeofday () in
  let point = {row; col} in

  (* Check for multi-click *)
  let is_nearby =
    match t.last_click_pos with
    | Some p ->
        abs (p.row - row) <= 1 && abs (p.col - col) <= multi_click_distance
    | None -> false
  in
  let time_ok = now -. t.last_click_time < multi_click_threshold in

  if is_nearby && time_ok then t.click_count <- min 3 (t.click_count + 1)
  else t.click_count <- 1 ;

  t.last_click_time <- now ;
  t.last_click_pos <- Some point ;

  (* Set selection mode based on click count *)
  t.click_mode <-
    (match t.click_count with 1 -> Single | 2 -> Word | _ -> Line) ;

  (* Set anchor and current based on mode *)
  (match t.click_mode with
  | Single ->
      t.anchor <- Some point ;
      t.current <- Some point
  | Word ->
      let get_char ~col = get_char ~row ~col in
      let start_col, end_col = find_word_bounds ~get_char ~col ~cols in
      t.anchor <- Some {row; col = start_col} ;
      t.current <- Some {row; col = end_col}
  | Line ->
      let get_char ~col = get_char ~row ~col in
      let start_col, end_col = find_line_bounds ~get_char ~col ~cols in
      t.anchor <- Some {row; col = start_col} ;
      t.current <- Some {row; col = end_col}) ;

  t.active <- true

(** Update the current selection endpoint during drag. *)
let update_selection t ~row ~col = if t.active then t.current <- Some {row; col}

(** Complete selection and return the selected text.
    Extracts characters from the buffer within the selection bounds. *)
let finish_selection t ~get_char ~cols =
  t.active <- false ;
  match get_bounds t with
  | None -> None
  | Some (start, stop) ->
      let buf = Buffer.create 256 in
      for row = start.row to stop.row do
        let col_start = if row = start.row then start.col else 0 in
        let col_end = if row = stop.row then stop.col else cols - 1 in
        for col = col_start to col_end do
          let ch = get_char ~row ~col in
          Buffer.add_string buf ch
        done ;
        (* Add newline between rows, but not after the last row *)
        if row < stop.row then Buffer.add_char buf '\n'
      done ;
      (* Trim trailing spaces from each line *)
      let text = Buffer.contents buf in
      let lines = String.split_on_char '\n' text in
      let trimmed =
        List.map
          (fun line ->
            let len = String.length line in
            let rec find_end i =
              if i <= 0 then 0
              else if line.[i - 1] <> ' ' then i
              else find_end (i - 1)
            in
            String.sub line 0 (find_end len))
          lines
      in
      Some (String.concat "\n" trimmed)

(** Clear the current selection. *)
let clear t =
  t.anchor <- None ;
  t.current <- None ;
  t.active <- false

(** Apply selection highlighting to the buffer.
    Modifies cells within selection to use reverse video style. *)
let apply_highlight t ~set_style ~rows ~cols =
  if has_selection t then
    for row = 0 to rows - 1 do
      for col = 0 to cols - 1 do
        if is_selected t ~row ~col then set_style ~row ~col ~reverse:true
      done
    done

(** Copy selection to clipboard and show optional toast. *)
let copy_to_clipboard text =
  match Clipboard.get () with Some clip -> clip.copy text | None -> ()
