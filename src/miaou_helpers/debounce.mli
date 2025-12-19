(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(** Generic debounce timer for deferring operations during rapid input.

    This module provides a thread-safe debounce mechanism useful for:
    - Deferring expensive validation until typing pauses
    - Rate-limiting filesystem operations during path editing
    - Coalescing rapid UI events

    Example usage:
    {[
      let debouncer = Debounce.create ~debounce_ms:250 ()

      (* On each input event *)
      let on_input () =
        Debounce.mark debouncer;
        Render_notify.request_render ()

      (* In service_cycle *)
      let service_cycle state _ =
        if Debounce.check_and_clear debouncer then
          run_expensive_operation state
        else
          state
    ]} *)

type t
(** A debounce timer instance. *)

val create : ?debounce_ms:int -> unit -> t
(** Create a new debounce timer.
    @param debounce_ms Minimum time in milliseconds between the last event
                       and when [is_ready] returns true. Default: 250ms. *)

val mark : t -> unit
(** Mark that an event occurred. Resets the debounce timer and sets pending. *)

val is_ready : t -> bool
(** Check if the debounce period has elapsed since the last event.
    Returns true if there's a pending event and enough time has passed. *)

val clear : t -> unit
(** Clear the pending state after handling the debounced event. *)

val has_pending : t -> bool
(** Check if there's a pending event (regardless of whether debounce elapsed). *)

val debounce_ms : t -> int
(** Get the configured debounce period in milliseconds. *)

val check_and_clear : t -> bool
(** Convenience: check if ready and automatically clear if so.
    Returns true if the action should be performed now. *)
