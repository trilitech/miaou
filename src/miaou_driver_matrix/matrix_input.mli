(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(** Terminal input handling for the Matrix driver.

    A dedicated Eio fiber reads keyboard and mouse input from the terminal,
    parsing escape sequences into events which are pushed into a
    mutex-protected queue.  The main tick loop drains the queue each tick,
    giving sub-millisecond input latency regardless of TPS.

    Lifecycle: {!create} -> {!start} -> (main loop calls {!drain}) -> {!stop}.
*)

(** Input reader state. *)
type t

(** Create a new input reader for the given terminal.
    Does not start the reader fiber — call {!start} for that. *)
val create : Matrix_terminal.t -> t

(** Start the background reader fiber.  Must be called after entering
    terminal raw mode, from inside an Eio switch (uses
    {!Miaou_helpers.Fiber_runtime.spawn}). *)
val start : t -> unit

(** Signal the reader fiber to stop. *)
val stop : t -> unit

(** Drain all pending events from the queue (oldest first).
    Returns the empty list when nothing is buffered. *)
val drain : t -> Matrix_io.event list

(** Legacy poll — drains the queue and returns the first event, or
    [Idle] when the queue is empty.
    @param timeout_ms Ignored (kept for API compatibility). *)
val poll : t -> timeout_ms:int -> Matrix_io.event

(** No-op — retained for API compatibility.
    With the decoupled reader, consecutive keys are naturally batched
    in the queue and processed each tick. *)
val drain_nav_keys : t -> Matrix_io.event -> int

(** No-op — retained for API compatibility. *)
val drain_esc_keys : t -> int
