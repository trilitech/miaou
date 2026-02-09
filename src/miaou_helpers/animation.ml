(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

type easing = Linear | Ease_in | Ease_out | Ease_in_out

type repeat = Once | Loop | Ping_pong

type t = {duration : float; easing : easing; repeat : repeat; elapsed : float}

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

let apply_easing easing t =
  match easing with
  | Linear -> t
  | Ease_in -> ease_in t
  | Ease_out -> ease_out t
  | Ease_in_out -> ease_in_out t

(* -- Core ----------------------------------------------------------------- *)

let create ~duration ?(easing = Linear) ?(repeat = Once) () =
  let duration = Float.max duration Float.epsilon in
  {duration; easing; repeat; elapsed = 0.0}

let tick anim ~dt =
  let elapsed = anim.elapsed +. Float.max 0.0 dt in
  {anim with elapsed}

let reset anim = {anim with elapsed = 0.0}

(** Compute the raw linear progress in [0, 1] depending on repeat mode. *)
let raw anim =
  if anim.elapsed <= 0.0 then 0.0
  else
    let ratio = anim.elapsed /. anim.duration in
    match anim.repeat with
    | Once -> Float.min 1.0 ratio
    | Loop ->
        let f = ratio -. floor ratio in
        (* fmod can drift; clamp *)
        Float.min 1.0 (Float.max 0.0 f)
    | Ping_pong ->
        (* Map ratio into a 0→1→0 triangle wave.
           Period = 2 * duration.  We use mod on the doubled-period. *)
        let period2 = ratio /. 2.0 in
        let phase = (period2 -. floor period2) *. 2.0 in
        (* phase is in [0, 2): 0..1 = forward, 1..2 = backward *)
        if phase <= 1.0 then Float.min 1.0 (Float.max 0.0 phase)
        else Float.min 1.0 (Float.max 0.0 (2.0 -. phase))

let value anim = apply_easing anim.easing (raw anim)

let finished anim =
  match anim.repeat with
  | Once -> anim.elapsed >= anim.duration
  | Loop | Ping_pong -> false

let elapsed anim = anim.elapsed

(* -- Interpolation -------------------------------------------------------- *)

let lerp a b anim =
  let v = value anim in
  a +. ((b -. a) *. v)

let lerp_int a b anim =
  let v = value anim in
  let f = float_of_int a +. (float_of_int (b - a) *. v) in
  int_of_float (Float.round f)
