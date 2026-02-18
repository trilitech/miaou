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
    Does not start the reader fiber — call {!start} for that.
    @param handle_sigint If false, SIGINT (Ctrl+C) is not intercepted,
      allowing the app to receive it as a key event. Default: true *)
val create : ?handle_sigint:bool -> Matrix_terminal.t -> t

(** Start the background reader fiber.  Must be called after entering
    terminal raw mode, from inside an Eio switch (uses
    {!Miaou_helpers.Fiber_runtime.spawn}). *)
val start : t -> unit

(** Signal the reader fiber to stop. *)
val stop : t -> unit

(** Drain all pending events from the queue (oldest first).
    Returns the empty list when nothing is buffered. *)
val drain : t -> Matrix_io.event list
