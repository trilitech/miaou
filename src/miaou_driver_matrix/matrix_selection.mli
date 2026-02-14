(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(** Terminal text selection for the Matrix driver.

    Handles mouse-based text selection with visual highlighting and
    clipboard integration. Selection works globally across any rendered
    content - no widget-specific code required.

    {b Usage}:
    {[
      let selection = Matrix_selection.create () in
      (* On mouse press: *)
      Matrix_selection.start_selection selection ~row ~col ~get_char ~cols ;
      (* On mouse drag: *)
      Matrix_selection.update_selection selection ~row ~col ;
      (* On mouse release: *)
      match Matrix_selection.finish_selection selection ~get_char ~cols with
      | Some text -> Matrix_selection.copy_to_clipboard text
      | None -> ()
    ]}

    Selection is drawn using reverse video style as an overlay on
    the normal buffer content. *)

(** Selection state. *)
type t

(** Create a new selection state (no active selection). *)
val create : unit -> t

(** Whether a selection drag is currently in progress. *)
val is_active : t -> bool

(** Whether there is a non-empty selection (even if drag finished). *)
val has_selection : t -> bool

(** Whether the selection is a single point (single click, no drag).
    Used to distinguish clicks from text selection. *)
val is_single_point : t -> bool

(** Whether this is a multi-click (double or triple click).
    Used to pass double-clicks to widgets. *)
val is_multi_click : t -> bool

(** Get the click count (1 = single, 2 = double, 3 = triple). *)
val click_count : t -> int

(** Check if a cell at (row, col) is within the current selection. *)
val is_selected : t -> row:int -> col:int -> bool

(** Start a new selection at the given position (on mouse press).
    Detects double-click (select word) and triple-click (select line).
    @param get_char Function to get character at (row, col) from buffer
    @param cols Number of columns in the buffer *)
val start_selection :
  t ->
  row:int ->
  col:int ->
  get_char:(row:int -> col:int -> string) ->
  cols:int ->
  unit

(** Update the selection endpoint (on mouse drag). *)
val update_selection : t -> row:int -> col:int -> unit

(** Finish selection and extract the selected text.
    @param get_char Function to get character at (row, col) from buffer
    @param cols Number of columns in the buffer
    @return Selected text with trailing spaces trimmed, or None if no selection *)
val finish_selection :
  t -> get_char:(row:int -> col:int -> string) -> cols:int -> string option

(** Clear the current selection. *)
val clear : t -> unit

(** Apply selection highlight overlay to buffer cells.
    Cells within selection have their reverse style set.
    @param set_style Function to modify cell style at (row, col)
    @param rows Number of rows in buffer
    @param cols Number of columns in buffer *)
val apply_highlight :
  t ->
  set_style:(row:int -> col:int -> reverse:bool -> unit) ->
  rows:int ->
  cols:int ->
  unit

(** Copy text to system clipboard using the Clipboard capability.
    Does nothing if Clipboard capability is not registered. *)
val copy_to_clipboard : string -> unit
