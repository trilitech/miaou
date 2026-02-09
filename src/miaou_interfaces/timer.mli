(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(** Page-scoped timer callbacks for periodic and one-shot state updates.

    Timers are registered by pages/widgets and checked by the driver on
    every tick.  When a timer's deadline is reached, it is marked as
    "fired" for the current tick.  Pages consume fired timers in their
    [refresh] function (or [service_cycle]) by calling {!drain_fired}.

    All timers are automatically cleared on page navigation via
    {!clear_all}, giving page-scoped lifecycle with zero page
    cooperation.

    {b Usage in pages}:
    {[
      (* In init or on_key: register a 5-second periodic refresh *)
      let timer = Timer.require () in
      timer.set_interval ~id:"poll" 5.0 ;

      (* In refresh: check which timers fired *)
      let fired = timer.drain_fired () in
      if List.mem "poll" fired then
        (* re-fetch data *)
    ]}

    {b Usage in drivers}:
    {[
      let timer_state = Timer.create_state () in
      Timer.register timer_state ;
      (* At the top of every tick: *)
      Timer.tick timer_state ;
      (* On page switch: *)
      Timer.clear_all timer_state ;
    ]} *)

(** {1 Timer kinds} *)

(** Whether a timer repeats or fires once. *)
type kind =
  | Interval  (** Repeats every [interval_s] seconds. *)
  | Timeout  (** Fires once after [delay_s] seconds, then auto-removes. *)

(** {1 Mutable driver-side state} *)

(** Opaque driver-side state.  Drivers create one, register it, and
    call {!tick} on each loop iteration. *)
type state

(** {1 Read-only capability view} *)

(** The interface exposed to pages and widgets via the capability
    registry. *)
type t = {
  set_interval : id:string -> float -> unit;
      (** [set_interval ~id interval_s] registers (or replaces) a
          repeating timer with the given [id].  It will first fire
          after [interval_s] seconds, then repeat. *)
  set_timeout : id:string -> float -> unit;
      (** [set_timeout ~id delay_s] registers a one-shot timer.  It
          fires once after [delay_s] seconds and is then automatically
          removed. *)
  clear : string -> unit;
      (** [clear id] removes the timer with the given [id].  No-op if
          no such timer exists. *)
  drain_fired : unit -> string list;
      (** Return the list of timer IDs that fired since the last call
          to [drain_fired] (or since the last {!tick}), and reset the
          fired set.  Typically called in [refresh]. *)
  active_ids : unit -> string list;
      (** Return the IDs of all currently registered timers. *)
}

(** {1 Capability access} *)

val key : t Capability.key

val set : t -> unit

val get : unit -> t option

val require : unit -> t

(** {1 Driver-side API} *)

(** Create a new empty timer state.  Uses [Clock.require ()] to
    obtain the current time, so the Clock capability must be
    registered first. *)
val create_state : unit -> state

(** Register the timer state as a capability so that pages and widgets
    can access it via {!get} / {!require}. *)
val register : state -> unit

(** Advance timers.  Call this at the top of every tick iteration,
    after {!Clock.tick}.  Checks all registered timers against the
    current clock time, marks due ones as fired, reschedules intervals,
    and removes expired timeouts. *)
val tick : state -> unit

(** Remove all registered timers.  Call this on page navigation to
    ensure timers don't leak across pages. *)
val clear_all : state -> unit
