(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

type easing =
  | Linear
  | Ease_in
  | Ease_out
  | Ease_in_out
  | Bounce
  | Custom of (float -> float)

type repeat = Once | Loop | Ping_pong

type t =
  | Single of single
  | Sequence of {
      steps : t array;
      mutable current : int;
      mutable elapsed_in_step : float;
    }

and single = {
  duration : float;
  easing : easing;
  repeat : repeat;
  elapsed : float;
}

(* -- Easing curves -------------------------------------------------------- *)

(** Cubic ease-in: f(t) = t^3 *)
let ease_in t = t *. t *. t

(** Cubic ease-out: f(t) = 1 - (1-t)^3 *)
let ease_out t =
  let u = 1.0 -. t in
  1.0 -. (u *. u *. u)

(** Cubic ease-in-out: piecewise cubic *)
let ease_in_out t =
  if t < 0.5 then 4.0 *. t *. t *. t
  else
    let u = (-2.0 *. t) +. 2.0 in
    1.0 -. (u *. u *. u /. 2.0)

(** Bounce: overshoots to ~1.1 then settles.
    Uses a quadratic overshoot: 1 + sin(pi*t) * 0.1 * (1-t) blended
    with the base progress.  Simplified to a cubic that peaks above 1:
      f(t) = 1 - (1-t)^2 * (1 - 3*t)
    This gives f(0)=0, f(0.7)≈1.1, f(1)=1. *)
let bounce t =
  if t >= 1.0 then 1.0
  else
    let u = 1.0 -. t in
    (* Quadratic ease-out with overshoot factor *)
    let base = 1.0 -. (u *. u) in
    let overshoot = Float.sin (t *. Float.pi) *. 0.1 in
    base +. overshoot

let apply_easing easing t =
  match easing with
  | Linear -> t
  | Ease_in -> ease_in t
  | Ease_out -> ease_out t
  | Ease_in_out -> ease_in_out t
  | Bounce -> bounce t
  | Custom f -> f t

(* -- Single helpers ------------------------------------------------------- *)

let single_duration s = s.duration

let single_raw s =
  if s.elapsed <= 0.0 then 0.0
  else
    let ratio = s.elapsed /. s.duration in
    match s.repeat with
    | Once -> Float.min 1.0 ratio
    | Loop ->
        let f = ratio -. floor ratio in
        Float.min 1.0 (Float.max 0.0 f)
    | Ping_pong ->
        let period2 = ratio /. 2.0 in
        let phase = (period2 -. floor period2) *. 2.0 in
        if phase <= 1.0 then Float.min 1.0 (Float.max 0.0 phase)
        else Float.min 1.0 (Float.max 0.0 (2.0 -. phase))

let single_value s = apply_easing s.easing (single_raw s)

let single_finished s =
  match s.repeat with
  | Once -> s.elapsed >= s.duration
  | Loop | Ping_pong -> false

(* -- Core ----------------------------------------------------------------- *)

let create ~duration ?(easing = Linear) ?(repeat = Once) () =
  let duration = Float.max duration Float.epsilon in
  Single {duration; easing; repeat; elapsed = 0.0}

let delay seconds =
  let duration = Float.max seconds Float.epsilon in
  Single {duration; easing = Linear; repeat = Once; elapsed = 0.0}

let rec tick anim ~dt =
  let dt = Float.max 0.0 dt in
  match anim with
  | Single s -> Single {s with elapsed = s.elapsed +. dt}
  | Sequence sq ->
      if sq.current >= Array.length sq.steps then anim (* already done *)
      else
        let step = sq.steps.(sq.current) in
        let step = tick step ~dt in
        sq.steps.(sq.current) <- step ;
        if finished step && sq.current < Array.length sq.steps - 1 then begin
          (* Carry over excess time into next step *)
          let excess = elapsed step -. step_duration step in
          let excess = Float.max 0.0 excess in
          let next = sq.current + 1 in
          let seq = Sequence {sq with current = next; elapsed_in_step = 0.0} in
          if excess > 0.0 then tick seq ~dt:excess else seq
        end
        else Sequence {sq with elapsed_in_step = sq.elapsed_in_step +. dt}

and finished anim =
  match anim with
  | Single s -> single_finished s
  | Sequence sq ->
      sq.current >= Array.length sq.steps
      || sq.current = Array.length sq.steps - 1
         && finished sq.steps.(sq.current)

and elapsed anim =
  match anim with
  | Single s -> s.elapsed
  | Sequence sq ->
      (* Total elapsed across all completed steps + current *)
      let total = ref 0.0 in
      for i = 0 to min sq.current (Array.length sq.steps - 1) do
        total := !total +. elapsed sq.steps.(i)
      done ;
      !total

and step_duration anim =
  match anim with
  | Single s -> single_duration s
  | Sequence sq ->
      let total = ref 0.0 in
      Array.iter (fun step -> total := !total +. step_duration step) sq.steps ;
      !total

let rec reset anim =
  match anim with
  | Single s -> Single {s with elapsed = 0.0}
  | Sequence sq ->
      Array.iteri (fun i step -> sq.steps.(i) <- reset step) sq.steps ;
      Sequence {sq with current = 0; elapsed_in_step = 0.0}

let rec value anim =
  match anim with
  | Single s -> single_value s
  | Sequence sq ->
      if sq.current >= Array.length sq.steps then
        (* Past end — return value of last step *)
        if Array.length sq.steps > 0 then
          value sq.steps.(Array.length sq.steps - 1)
        else 0.0
      else value sq.steps.(sq.current)

let rec raw anim =
  match anim with
  | Single s -> single_raw s
  | Sequence sq ->
      if sq.current >= Array.length sq.steps then
        if Array.length sq.steps > 0 then
          raw sq.steps.(Array.length sq.steps - 1)
        else 0.0
      else raw sq.steps.(sq.current)

(* -- Interpolation -------------------------------------------------------- *)

let lerp a b anim =
  let v = value anim in
  a +. ((b -. a) *. v)

let lerp_int a b anim =
  let v = value anim in
  let f = float_of_int a +. (float_of_int (b - a) *. v) in
  int_of_float (Float.round f)

(* -- Combinators ---------------------------------------------------------- *)

let sequence steps =
  match steps with
  | [] ->
      Single
        {
          duration = Float.epsilon;
          easing = Linear;
          repeat = Once;
          elapsed = Float.epsilon;
        }
  | _ ->
      Sequence {steps = Array.of_list steps; current = 0; elapsed_in_step = 0.0}
