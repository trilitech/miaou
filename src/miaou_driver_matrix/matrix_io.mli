(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(** I/O abstraction for the Matrix driver.

    Defines event types and I/O interfaces that decouple the main loop
    from a specific terminal implementation. This enables reuse of the
    Matrix rendering engine (buffer, diff, ANSI writer) with different
    backends (terminal, WebSocket, etc.). *)

(** Input events produced by any backend. *)
type event =
  | Key of string  (** Named key or character *)
  | MousePress of int * int
      (** Mouse button pressed at (row, col), 1-indexed *)
  | Mouse of int * int
      (** Mouse button released (click) at (row, col), 1-indexed *)
  | MouseDrag of int * int  (** Mouse motion while button held, at (row, col) *)
  | Resize  (** Viewport was resized *)
  | Refresh  (** Time for service_cycle - rate limited *)
  | Idle  (** No input, not time for refresh *)
  | Quit  (** Exit signal received *)

(** I/O operations provided by a backend. *)
type t = {
  write : string -> unit;
      (** Write an ANSI string to the output (terminal or WebSocket). *)
  drain : unit -> event list;
      (** Drain all pending events from the input queue (oldest first).
          Returns the empty list when nothing is buffered. *)
  size : unit -> int * int;
      (** Get current viewport dimensions as (rows, cols). *)
  invalidate_size_cache : unit -> unit;
      (** Invalidate cached size (e.g. after resize event). *)
}
