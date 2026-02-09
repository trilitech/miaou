(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

[@@@warning "-32-34-37-69"]

type state = {
  origin : float;
  mutable prev_tick : float;
  mutable cur_tick : float;
}

type t = {dt : unit -> float; now : unit -> float; elapsed : unit -> float}

let key : t Capability.key = Capability.create ~name:"Clock"

let set v = Capability.set key v

let get () = Capability.get key

let require () = Capability.require key

let create_state () =
  let now = Unix.gettimeofday () in
  {origin = now; prev_tick = now; cur_tick = now}

let register (s : state) =
  let cap : t =
    {
      dt = (fun () -> s.cur_tick -. s.prev_tick);
      now = (fun () -> s.cur_tick);
      elapsed = (fun () -> s.cur_tick -. s.origin);
    }
  in
  set cap

let tick (s : state) =
  let now = Unix.gettimeofday () in
  s.prev_tick <- s.cur_tick ;
  s.cur_tick <- now
