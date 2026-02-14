(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

(** Multiline text input widget with cursor and scroll support. *)

open Miaou_widgets_display.Widgets

type t = {
  lines : string array;  (** Content lines *)
  cursor_row : int;  (** Current line (0-indexed) *)
  cursor_col : int;  (** Column position in current line *)
  scroll_offset : int;  (** First visible line *)
  width : int;  (** Display width *)
  height : int;  (** Visible lines count *)
  title : string option;
  placeholder : string option;
  cancelled : bool;
}

let create ?title ?(width = 60) ?(height = 10) ?(initial = "") ?placeholder () =
  let lines =
    if String.length initial = 0 then [|""|]
    else
      let split = String.split_on_char '\n' initial in
      Array.of_list split
  in
  {
    lines;
    cursor_row = Array.length lines - 1;
    cursor_col = String.length lines.(Array.length lines - 1);
    scroll_offset = 0;
    width;
    height;
    title;
    placeholder;
    cancelled = false;
  }

let open_centered ?title ?(width = 60) ?(height = 10) ?(initial = "")
    ?placeholder () =
  create ?title ~width ~height ~initial ?placeholder ()

(** Get current line content *)
let current_line t = t.lines.(t.cursor_row)

(** Update current line *)
let set_current_line t content =
  let lines = Array.copy t.lines in
  lines.(t.cursor_row) <- content ;
  {t with lines}

(** Insert a new line at cursor position *)
let insert_newline t =
  let line = current_line t in
  let left = String.sub line 0 t.cursor_col in
  let right =
    String.sub line t.cursor_col (String.length line - t.cursor_col)
  in
  let before = Array.sub t.lines 0 t.cursor_row in
  let after =
    Array.sub
      t.lines
      (t.cursor_row + 1)
      (Array.length t.lines - t.cursor_row - 1)
  in
  let new_lines = Array.concat [before; [|left; right|]; after] in
  let new_row = t.cursor_row + 1 in
  (* Adjust scroll if cursor would go below visible area *)
  let scroll_offset =
    if new_row >= t.scroll_offset + t.height then t.scroll_offset + 1
    else t.scroll_offset
  in
  {
    t with
    lines = new_lines;
    cursor_row = new_row;
    cursor_col = 0;
    scroll_offset;
  }

(** Delete character before cursor (backspace) *)
let backspace t =
  if t.cursor_col > 0 then
    let line = current_line t in
    let left = String.sub line 0 (t.cursor_col - 1) in
    let right =
      String.sub line t.cursor_col (String.length line - t.cursor_col)
    in
    set_current_line {t with cursor_col = t.cursor_col - 1} (left ^ right)
  else if t.cursor_row > 0 then
    (* Join with previous line *)
    let prev_line = t.lines.(t.cursor_row - 1) in
    let curr_line = current_line t in
    let new_col = String.length prev_line in
    let before = Array.sub t.lines 0 (t.cursor_row - 1) in
    let after =
      Array.sub
        t.lines
        (t.cursor_row + 1)
        (Array.length t.lines - t.cursor_row - 1)
    in
    let new_lines = Array.concat [before; [|prev_line ^ curr_line|]; after] in
    let new_row = t.cursor_row - 1 in
    let scroll_offset =
      if new_row < t.scroll_offset then max 0 (t.scroll_offset - 1)
      else t.scroll_offset
    in
    {
      t with
      lines = new_lines;
      cursor_row = new_row;
      cursor_col = new_col;
      scroll_offset;
    }
  else t

(** Delete character at cursor (delete key) *)
let delete t =
  let line = current_line t in
  if t.cursor_col < String.length line then
    let left = String.sub line 0 t.cursor_col in
    let right =
      String.sub line (t.cursor_col + 1) (String.length line - t.cursor_col - 1)
    in
    set_current_line t (left ^ right)
  else if t.cursor_row < Array.length t.lines - 1 then
    (* Join with next line *)
    let next_line = t.lines.(t.cursor_row + 1) in
    let before = Array.sub t.lines 0 t.cursor_row in
    let after =
      Array.sub
        t.lines
        (t.cursor_row + 2)
        (Array.length t.lines - t.cursor_row - 2)
    in
    let new_lines = Array.concat [before; [|line ^ next_line|]; after] in
    {t with lines = new_lines}
  else t

(** Insert character at cursor *)
let insert_char t ch =
  let line = current_line t in
  let left = String.sub line 0 t.cursor_col in
  let right =
    String.sub line t.cursor_col (String.length line - t.cursor_col)
  in
  set_current_line {t with cursor_col = t.cursor_col + 1} (left ^ ch ^ right)

(** Move cursor left *)
let move_left t =
  if t.cursor_col > 0 then {t with cursor_col = t.cursor_col - 1}
  else if t.cursor_row > 0 then
    let new_row = t.cursor_row - 1 in
    let scroll_offset =
      if new_row < t.scroll_offset then max 0 (t.scroll_offset - 1)
      else t.scroll_offset
    in
    {
      t with
      cursor_row = new_row;
      cursor_col = String.length t.lines.(new_row);
      scroll_offset;
    }
  else t

(** Move cursor right *)
let move_right t =
  let line = current_line t in
  if t.cursor_col < String.length line then
    {t with cursor_col = t.cursor_col + 1}
  else if t.cursor_row < Array.length t.lines - 1 then
    let new_row = t.cursor_row + 1 in
    let scroll_offset =
      if new_row >= t.scroll_offset + t.height then t.scroll_offset + 1
      else t.scroll_offset
    in
    {t with cursor_row = new_row; cursor_col = 0; scroll_offset}
  else t

(** Move cursor up *)
let move_up t =
  if t.cursor_row > 0 then
    let new_row = t.cursor_row - 1 in
    let new_col = min t.cursor_col (String.length t.lines.(new_row)) in
    let scroll_offset =
      if new_row < t.scroll_offset then max 0 (t.scroll_offset - 1)
      else t.scroll_offset
    in
    {t with cursor_row = new_row; cursor_col = new_col; scroll_offset}
  else {t with cursor_col = 0}

(** Move cursor down *)
let move_down t =
  if t.cursor_row < Array.length t.lines - 1 then
    let new_row = t.cursor_row + 1 in
    let new_col = min t.cursor_col (String.length t.lines.(new_row)) in
    let scroll_offset =
      if new_row >= t.scroll_offset + t.height then t.scroll_offset + 1
      else t.scroll_offset
    in
    {t with cursor_row = new_row; cursor_col = new_col; scroll_offset}
  else {t with cursor_col = String.length (current_line t)}

(** Move to start of line *)
let move_home t = {t with cursor_col = 0}

(** Move to end of line *)
let move_end t = {t with cursor_col = String.length (current_line t)}

(** Render the textarea *)
let render t ~focus:(_ : bool) =
  let total_lines = Array.length t.lines in
  let is_empty = total_lines = 1 && String.length t.lines.(0) = 0 in
  let buf = Buffer.create 256 in
  (* Title *)
  (match t.title with
  | Some title ->
      Buffer.add_string buf (titleize title) ;
      Buffer.add_char buf '\n'
  | None -> ()) ;
  (* Top border *)
  Buffer.add_string buf (fg 238 ("+" ^ String.make (t.width - 2) '-' ^ "+")) ;
  Buffer.add_char buf '\n' ;
  (* Content lines *)
  for i = 0 to t.height - 1 do
    let line_idx = t.scroll_offset + i in
    Buffer.add_string buf (fg 238 "|") ;
    let content =
      if is_empty && i = 0 then
        match t.placeholder with Some p -> dim p | None -> ""
      else if line_idx < total_lines then
        let line = t.lines.(line_idx) in
        if line_idx = t.cursor_row then
          (* Show cursor *)
          let left =
            String.sub line 0 (min t.cursor_col (String.length line))
          in
          let right =
            if t.cursor_col < String.length line then
              String.sub line t.cursor_col (String.length line - t.cursor_col)
            else ""
          in
          left ^ "_" ^ right
        else line
      else ""
    in
    (* Pad or truncate to width *)
    let visible_len = visible_chars_count content in
    let inner_width = t.width - 2 in
    let padded =
      if visible_len >= inner_width then
        let byte_idx = visible_byte_index_of_pos content (inner_width - 1) in
        String.sub content 0 byte_idx ^ "…"
      else content ^ String.make (inner_width - visible_len) ' '
    in
    Buffer.add_string buf padded ;
    Buffer.add_string buf (fg 238 "|") ;
    if i < t.height - 1 then Buffer.add_char buf '\n'
  done ;
  Buffer.add_char buf '\n' ;
  (* Bottom border *)
  Buffer.add_string buf (fg 238 ("+" ^ String.make (t.width - 2) '-' ^ "+")) ;
  (* Line indicator *)
  let indicator = Printf.sprintf " Line %d/%d" (t.cursor_row + 1) total_lines in
  Buffer.add_string buf (dim indicator) ;
  Buffer.contents buf

(** Handle key input *)
let on_key t ~key =
  let open Miaou_interfaces.Key_event in
  match key with
  | "A-Enter" | "Alt-Enter" ->
      (* Shift+Enter inserts newline *)
      (insert_newline t, Handled)
  | "Backspace" -> (backspace t, Handled)
  | "Delete" -> (delete t, Handled)
  | "Left" -> (move_left t, Handled)
  | "Right" -> (move_right t, Handled)
  | "Up" -> (move_up t, Handled)
  | "Down" -> (move_down t, Handled)
  | "Home" -> (move_home t, Handled)
  | "End" -> (move_end t, Handled)
  | "Esc" | "Escape" -> ({t with cancelled = true}, Handled)
  | "WheelUp" ->
      (* Scroll up by moving view, not cursor *)
      let new_scroll =
        max 0 (t.scroll_offset - Miaou_helpers.Mouse.wheel_scroll_lines)
      in
      ({t with scroll_offset = new_scroll}, Handled)
  | "WheelDown" ->
      let max_scroll = max 0 (Array.length t.lines - t.height + 2) in
      let new_scroll =
        min max_scroll (t.scroll_offset + Miaou_helpers.Mouse.wheel_scroll_lines)
      in
      ({t with scroll_offset = new_scroll}, Handled)
  | k when String.length k = 1 -> (insert_char t k, Handled)
  | key -> (
      (* Check for mouse click to position cursor *)
      match Miaou_helpers.Mouse.parse_click key with
      | Some {row; col} ->
          (* Account for box border (1 row for top border) *)
          let text_row = row - 1 + t.scroll_offset in
          let text_col = col - 1 in
          (* 1 for left border *)
          let max_row = Array.length t.lines - 1 in
          let new_row = max 0 (min max_row text_row) in
          let max_col = String.length t.lines.(new_row) in
          let new_col = max 0 (min max_col text_col) in
          ({t with cursor_row = new_row; cursor_col = new_col}, Handled)
      | None -> (t, Bubble))

let handle_key t ~key =
  let t', _ = on_key t ~key in
  t'

(** Get all text as a single string *)
let get_text t = String.concat "\n" (Array.to_list t.lines)

let value t = get_text t

(** Set text content *)
let set_text t s =
  let lines =
    if String.length s = 0 then [|""|]
    else Array.of_list (String.split_on_char '\n' s)
  in
  let cursor_row = min t.cursor_row (Array.length lines - 1) in
  let cursor_col = min t.cursor_col (String.length lines.(cursor_row)) in
  {t with lines; cursor_row; cursor_col}

let is_cancelled t = t.cancelled

let reset_cancelled t = {t with cancelled = false}

let cursor_position t = (t.cursor_row, t.cursor_col)

let line_count t = Array.length t.lines

let width t = t.width

let height t = t.height

let with_dimensions t ~width ~height =
  {t with width = max 10 width; height = max 3 height}
