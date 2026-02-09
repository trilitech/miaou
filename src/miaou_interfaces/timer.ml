(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

[@@@warning "-32-34-37-69"]

type kind = Interval | Timeout

type timer_entry = {
  id : string;
  kind : kind;
  interval_s : float;
  mutable deadline : float;
}

type state = {mutable timers : timer_entry list; mutable fired : string list}

type t = {
  set_interval : id:string -> float -> unit;
  set_timeout : id:string -> float -> unit;
  clear : string -> unit;
  drain_fired : unit -> string list;
  active_ids : unit -> string list;
}

let key : t Capability.key = Capability.create ~name:"Timer"

let set v = Capability.set key v

let get () = Capability.get key

let require () = Capability.require key

let create_state () = {timers = []; fired = []}

let register (s : state) =
  let cap : t =
    {
      set_interval =
        (fun ~id interval_s ->
          let clock = Clock.require () in
          let now = clock.now () in
          (* Remove any existing timer with same id *)
          s.timers <- List.filter (fun e -> e.id <> id) s.timers ;
          let entry =
            {id; kind = Interval; interval_s; deadline = now +. interval_s}
          in
          s.timers <- entry :: s.timers);
      set_timeout =
        (fun ~id delay_s ->
          let clock = Clock.require () in
          let now = clock.now () in
          s.timers <- List.filter (fun e -> e.id <> id) s.timers ;
          let entry =
            {
              id;
              kind = Timeout;
              interval_s = delay_s;
              deadline = now +. delay_s;
            }
          in
          s.timers <- entry :: s.timers);
      clear = (fun id -> s.timers <- List.filter (fun e -> e.id <> id) s.timers);
      drain_fired =
        (fun () ->
          let f = s.fired in
          s.fired <- [] ;
          f);
      active_ids = (fun () -> List.map (fun e -> e.id) s.timers);
    }
  in
  set cap

let tick (s : state) =
  let clock = Clock.require () in
  let now = clock.now () in
  let fired = ref [] in
  let remaining = ref [] in
  List.iter
    (fun (entry : timer_entry) ->
      if now >= entry.deadline then begin
        fired := entry.id :: !fired ;
        match entry.kind with
        | Interval ->
            (* Reschedule: advance deadline by interval.  If we missed
               multiple intervals (e.g. long tick), snap to next future
               deadline rather than firing a burst. *)
            let next = entry.deadline +. entry.interval_s in
            let next =
              if next <= now then
                (* We're behind — snap to the next future deadline *)
                let missed =
                  Float.to_int ((now -. entry.deadline) /. entry.interval_s)
                in
                entry.deadline +. (float_of_int (missed + 1) *. entry.interval_s)
              else next
            in
            entry.deadline <- next ;
            remaining := entry :: !remaining
        | Timeout ->
            (* One-shot: don't keep it *)
            ()
      end
      else remaining := entry :: !remaining)
    s.timers ;
  s.timers <- List.rev !remaining ;
  s.fired <- List.rev_append !fired s.fired

let clear_all (s : state) =
  s.timers <- [] ;
  s.fired <- []
