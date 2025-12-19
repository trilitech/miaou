(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

(* Global render notification system.

   Widgets can call [request_render] to schedule a re-render.
   The driver checks [should_render] periodically and performs the render.

   This is useful for widgets that need to update after a delay
   (e.g., debounced validation, animations, timers).
*)

let pending = Atomic.make false

let request_render () = Atomic.set pending true

let should_render () =
  if Atomic.get pending then (
    Atomic.set pending false ;
    true)
  else false

let clear () = Atomic.set pending false
