(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(** Clock capability — provides elapsed time since the last tick.

    Drivers register this capability before entering the main loop.
    The driver updates the internal state at the start of every tick so
    that pages and widgets can query timing information without calling
    [Unix.gettimeofday] themselves.

    {b Usage in pages / widgets}:
    {[
      let clock = Clock.require () in
      let dt = clock.dt () in
      (* dt is the seconds elapsed since the previous tick *)
    ]}

    {b Usage in drivers}:
    {[
      let clock_state = Clock.create_state () in
      Clock.register clock_state ;
      (* At the top of every tick: *)
      Clock.tick clock_state ;
    ]}
*)

(** Mutable driver-side state.  Drivers create one of these, register it,
    and call {!tick} at the start of every tick iteration. *)
type state

(** The read-only view exposed to pages and widgets via the capability
    registry. *)
type t = {
  dt : unit -> float;
      (** Seconds elapsed since the previous tick.  Returns [0.] on the
          first tick. *)
  now : unit -> float;
      (** Wall-clock time at the start of the current tick (equivalent to
          [Unix.gettimeofday ()] but cached — zero-cost to call multiple
          times within the same tick). *)
  elapsed : unit -> float;
      (** Seconds elapsed since the clock was created (i.e. since the
          driver started the main loop). *)
}

(** {1 Capability access} *)

val key : t Capability.key

val set : t -> unit

val get : unit -> t option

val require : unit -> t

(** {1 Driver-side API} *)

(** Create a new clock state, recording the current wall-clock time as
    the origin. *)
val create_state : unit -> state

(** Register the clock state as a capability so that pages and widgets
    can access it via {!get} / {!require}. *)
val register : state -> unit

(** Advance the clock.  Call this at the top of every tick iteration.
    Updates [dt], [now], and [elapsed] atomically. *)
val tick : state -> unit
