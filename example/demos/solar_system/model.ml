(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(* Static body table. Distances in millions of km, periods in Earth days,
   radii in km, colours as base RGB triples (used as the fully-lit shade
   in the renderer). *)

type body = {
  name : string;
  short : string;
  orbit_mkm : float;
  orbit_period_d : float;
  spin_period_d : float;
  radius_km : float;
  base_color : int * int * int;
  has_ring : bool;
}

let sun =
  {
    name = "Sun";
    short = "Sun";
    orbit_mkm = 0.0;
    orbit_period_d = 1.0;
    spin_period_d = 27.0;
    radius_km = 696340.0;
    base_color = (255, 220, 80);
    has_ring = false;
  }

let planets =
  [|
    {
      name = "Mercury";
      short = "Mer";
      orbit_mkm = 57.9;
      orbit_period_d = 88.0;
      spin_period_d = 58.6;
      radius_km = 2440.0;
      base_color = (170, 165, 160);
      has_ring = false;
    };
    {
      name = "Venus";
      short = "Ven";
      orbit_mkm = 108.2;
      orbit_period_d = 224.7;
      spin_period_d = 243.0;
      radius_km = 6052.0;
      base_color = (235, 210, 160);
      has_ring = false;
    };
    {
      name = "Earth";
      short = "Ear";
      orbit_mkm = 149.6;
      orbit_period_d = 365.25;
      spin_period_d = 1.0;
      radius_km = 6371.0;
      base_color = (90, 140, 220);
      has_ring = false;
    };
    {
      name = "Mars";
      short = "Mar";
      orbit_mkm = 227.9;
      orbit_period_d = 687.0;
      spin_period_d = 1.03;
      radius_km = 3390.0;
      base_color = (210, 110, 70);
      has_ring = false;
    };
    {
      name = "Jupiter";
      short = "Jup";
      orbit_mkm = 778.6;
      orbit_period_d = 4333.0;
      spin_period_d = 0.41;
      radius_km = 69911.0;
      base_color = (220, 175, 130);
      has_ring = false;
    };
    {
      name = "Saturn";
      short = "Sat";
      orbit_mkm = 1433.5;
      orbit_period_d = 10759.0;
      spin_period_d = 0.45;
      radius_km = 58232.0;
      base_color = (235, 215, 165);
      has_ring = true;
    };
    {
      name = "Uranus";
      short = "Ura";
      orbit_mkm = 2872.5;
      orbit_period_d = 30687.0;
      spin_period_d = 0.72;
      radius_km = 25362.0;
      base_color = (160, 215, 230);
      has_ring = false;
    };
    {
      name = "Neptune";
      short = "Nep";
      orbit_mkm = 4495.1;
      orbit_period_d = 60190.0;
      spin_period_d = 0.67;
      radius_km = 24622.0;
      base_color = (60, 95, 200);
      has_ring = false;
    };
  |]

(* ---------- runtime state ---------- *)

(* Time multiplier (simulated days per real second). *)
type speed = X1 | X10 | X100 | X1000 | X10000

let speed_factor = function
  | X1 -> 1.0
  | X10 -> 10.0
  | X100 -> 100.0
  | X1000 -> 1000.0
  | X10000 -> 10000.0

let speed_label = function
  | X1 -> "x1"
  | X10 -> "x10"
  | X100 -> "x100"
  | X1000 -> "x1000"
  | X10000 -> "x10k"

let speed_of_digit = function
  | "1" -> Some X1
  | "2" -> Some X10
  | "3" -> Some X100
  | "4" -> Some X1000
  | "5" -> Some X10000
  | _ -> None

type state = {
  t_days : float;
  paused : bool;
  speed : speed;
  show_orbits : bool;
  show_labels : bool;
  show_panel : bool;
  next_page : string option;
}

let init () =
  {
    t_days = 0.0;
    paused = false;
    speed = X100;
    show_orbits = true;
    show_labels = true;
    show_panel = true;
    next_page = None;
  }

let advance s ~dt_real =
  if s.paused then s
  else {s with t_days = s.t_days +. (dt_real *. speed_factor s.speed)}

(* Position of a body at time [t] in solar-system units (mkm). *)
let body_xy body ~t_days =
  if body.orbit_period_d <= 0.0 then (0.0, 0.0)
  else
    let phase = 2.0 *. Float.pi *. t_days /. body.orbit_period_d in
    (body.orbit_mkm *. cos phase, body.orbit_mkm *. sin phase)

(* Spin phase of a body at time [t] (radians, modulo 2π). *)
let spin_phase body ~t_days =
  if body.spin_period_d <= 0.0 then 0.0
  else
    let p = mod_float (t_days /. body.spin_period_d) 1.0 in
    let p = if p < 0.0 then p +. 1.0 else p in
    2.0 *. Float.pi *. p
