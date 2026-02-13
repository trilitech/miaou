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

type t = {
  mutable anchor : point option;
      (** Starting point of selection (where mouse was pressed) *)
  mutable current : point option;
      (** Current end point of selection (where mouse is now) *)
  mutable active : bool;  (** Whether a selection drag is in progress *)
}

let create () = {anchor = None; current = None; active = false}

let is_active t = t.active

let has_selection t =
  match (t.anchor, t.current) with Some _, Some _ -> true | _ -> false

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

(** Start a new selection at the given position. *)
let start_selection t ~row ~col =
  let point = {row; col} in
  t.anchor <- Some point ;
  t.current <- Some point ;
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
