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
  | Mouse of int * int  (** Click at (row, col), 1-indexed *)
  | Resize  (** Viewport was resized *)
  | Refresh  (** Time for service_cycle - rate limited *)
  | Idle  (** No input, not time for refresh *)
  | Quit  (** Exit signal received *)

(** I/O operations provided by a backend. *)
type t = {
  write : string -> unit;
      (** Write an ANSI string to the output (terminal or WebSocket). *)
  poll : timeout_ms:int -> event;
      (** Poll for the next input event with timeout. *)
  drain : unit -> event list;
      (** Drain all pending events from the input queue (oldest first).
          Returns the empty list when nothing is buffered. *)
  drain_nav_keys : event -> int;
      (** Drain consecutive identical navigation keys to prevent scroll lag.
          No-op when the decoupled reader is active.
          Returns count of drained events. *)
  drain_esc_keys : unit -> int;
      (** Drain pending Esc keys to prevent double-Esc navigation.
          No-op when the decoupled reader is active.
          Returns count of drained events. *)
  size : unit -> int * int;
      (** Get current viewport dimensions as (rows, cols). *)
  invalidate_size_cache : unit -> unit;
      (** Invalidate cached size (e.g. after resize event). *)
}
