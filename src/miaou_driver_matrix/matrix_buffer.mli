(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(** Double-buffered terminal grid for the Matrix driver.

    Maintains two cell grids (front and back). The back buffer is the write
    target during rendering, while the front buffer holds the last displayed
    state for diff computation. After rendering, buffers are swapped via O(1)
    pointer swap.

    Thread-safe: All operations use internal mutex for cross-domain safety. *)

type t

(** Create a new buffer with given dimensions.
    Both front and back are initialized to empty cells. *)
val create : rows:int -> cols:int -> t

(** Resize the buffer in-place, preserving content where possible.
    New cells are initialized to empty. Marks buffer as dirty. *)
val resize : t -> rows:int -> cols:int -> unit

(** Get number of rows. *)
val rows : t -> int

(** Get number of columns. *)
val cols : t -> int

(** Get dimensions as (rows, cols) tuple. Thread-safe. *)
val size : t -> int * int

(** {2 Back Buffer Operations (Write Target)} *)

(** Set a cell in the back buffer.
    Out-of-bounds writes are silently ignored. Thread-safe. *)
val set : t -> row:int -> col:int -> Matrix_cell.t -> unit

(** Set cell by copying character and style from another cell.
    More efficient than set when you have a cell to copy from. Thread-safe. *)
val set_from : t -> row:int -> col:int -> Matrix_cell.t -> unit

(** Get a cell from the back buffer.
    Returns empty cell for out-of-bounds reads. Thread-safe. *)
val get_back : t -> row:int -> col:int -> Matrix_cell.t

(** Clear the back buffer (fill with empty cells). Thread-safe. *)
val clear_back : t -> unit

(** Set character and style directly in back buffer. Thread-safe. *)
val set_char :
  t -> row:int -> col:int -> char:string -> style:Matrix_cell.style -> unit

(** {2 Front Buffer Operations (Last Rendered State)} *)

(** Get a cell from the front buffer.
    Returns empty cell for out-of-bounds reads. *)
val get_front : t -> row:int -> col:int -> Matrix_cell.t

(** {2 Buffer Management} *)

(** Swap front and back buffers. O(1) pointer swap. Thread-safe. *)
val swap : t -> unit

(** Check if a cell differs between front and back buffers. *)
val cell_changed : t -> row:int -> col:int -> bool

(** Mark all cells as needing redraw (for full refresh after resize).
    Thread-safe. *)
val mark_all_dirty : t -> unit

(** {2 Dirty Flag (for render domain)} *)

(** Mark buffer as needing render. *)
val mark_dirty : t -> unit

(** Check if buffer needs render. *)
val is_dirty : t -> bool

(** Clear dirty flag after render. *)
val clear_dirty : t -> unit

(** {2 Batch Operations} *)

(** Record of unlocked operations available within [with_back_buffer]. *)
type batch_ops = {
  clear : unit -> unit;  (** Clear back buffer *)
  set_char :
    row:int -> col:int -> char:string -> style:Matrix_cell.style -> unit;
  get : row:int -> col:int -> Matrix_cell.t;  (** Get cell from back buffer *)
  rows : int;  (** Current row count *)
  cols : int;  (** Current column count *)
}

(** Execute function with buffer lock held. Marks dirty after.
    The callback receives [batch_ops] for safe unlocked access. *)
val with_back_buffer : t -> (batch_ops -> 'a) -> 'a
