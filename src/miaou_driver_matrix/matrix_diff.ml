(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

type change =
  | MoveTo of int * int
  | SetStyle of Matrix_cell.style
  | WriteChar of string
  | WriteRun of string * int

(* Compute diff between front and back buffers *)
let compute buffer =
  let rows = Matrix_buffer.rows buffer in
  let cols = Matrix_buffer.cols buffer in
  let changes = ref [] in

  (* Track current cursor position and style to minimize emissions *)
  let cursor_row = ref 0 in
  let cursor_col = ref 0 in
  let current_style = ref Matrix_cell.default_style in

  (* Emit a change, prepending to list (we'll reverse at the end) *)
  let emit change = changes := change :: !changes in

  (* Move cursor if not already at target position *)
  let move_to row col =
    if row <> !cursor_row || col <> !cursor_col then begin
      emit (MoveTo (row, col)) ;
      cursor_row := row ;
      cursor_col := col
    end
  in

  (* Set style if different from current *)
  let set_style style =
    if not (Matrix_cell.style_equal style !current_style) then begin
      emit (SetStyle style) ;
      current_style := style
    end
  in

  (* Write a character and advance cursor *)
  let write_char char =
    emit (WriteChar char) ;
    incr cursor_col ;
    (* Handle wrap - cursor stays at end of line in most terminals *)
    if !cursor_col >= cols then cursor_col := cols - 1
  in

  (* Scan through buffer *)
  for row = 0 to rows - 1 do
    for col = 0 to cols - 1 do
      let front = Matrix_buffer.get_front buffer ~row ~col in
      let back = Matrix_buffer.get_back buffer ~row ~col in

      if not (Matrix_cell.equal front back) then begin
        (* Cell changed - need to update *)
        move_to row col ;
        set_style back.style ;
        write_char back.char
      end
    done
  done ;

  (* Return changes in correct order *)
  List.rev !changes

(* Compute diff for a specific region *)
let compute_region buffer ~row ~col ~width ~height =
  let rows = Matrix_buffer.rows buffer in
  let cols = Matrix_buffer.cols buffer in
  let changes = ref [] in

  let cursor_row = ref 0 in
  let cursor_col = ref 0 in
  let current_style = ref Matrix_cell.default_style in

  let emit change = changes := change :: !changes in

  let move_to r c =
    if r <> !cursor_row || c <> !cursor_col then begin
      emit (MoveTo (r, c)) ;
      cursor_row := r ;
      cursor_col := c
    end
  in

  let set_style style =
    if not (Matrix_cell.style_equal style !current_style) then begin
      emit (SetStyle style) ;
      current_style := style
    end
  in

  let write_char char =
    emit (WriteChar char) ;
    incr cursor_col
  in

  (* Clamp region to buffer bounds *)
  let end_row = min (row + height) rows in
  let end_col = min (col + width) cols in

  for r = row to end_row - 1 do
    for c = col to end_col - 1 do
      let front = Matrix_buffer.get_front buffer ~row:r ~col:c in
      let back = Matrix_buffer.get_back buffer ~row:r ~col:c in

      if not (Matrix_cell.equal front back) then begin
        move_to r c ;
        set_style back.style ;
        write_char back.char
      end
    done
  done ;

  List.rev !changes

(* Count changed cells *)
let count_changes buffer =
  let rows = Matrix_buffer.rows buffer in
  let cols = Matrix_buffer.cols buffer in
  let count = ref 0 in

  for row = 0 to rows - 1 do
    for col = 0 to cols - 1 do
      if Matrix_buffer.cell_changed buffer ~row ~col then incr count
    done
  done ;

  !count
