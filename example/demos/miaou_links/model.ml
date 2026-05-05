(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

module Arcade_kit = Demo_shared.Arcade_kit

(** Game model for MIAOU Links — a chill top-down golf game.

    The course is a tile grid; the ball lives in continuous (x, y, z)
    coordinates within that grid (z used only during flight for a
    parabolic arc). Friction depends on the tile under the ball;
    wind nudges the ball constantly. *)

(* ---------- tiles ---------- *)

type tile = Tee | Fairway | Rough | Sand | Water | Green | Cup | Wall_oob

let tile_of_char = function
  | '#' -> Wall_oob
  | '~' -> Water
  | '.' -> Fairway
  | 'R' -> Rough
  | 'T' -> Tee
  | 'G' -> Green
  | 'S' -> Sand
  | 'C' -> Cup
  | _ -> Fairway

(* ---------- ball ---------- *)

type ball = {
  mutable x : float;
  mutable y : float;
  mutable z : float;
  mutable vx : float;
  mutable vy : float;
  mutable vz : float;
  mutable in_flight : bool;
}

let make_ball () =
  {x = 0.; y = 0.; z = 0.; vx = 0.; vy = 0.; vz = 0.; in_flight = false}

(* ---------- club ---------- *)

type club = Driver | Iron | Wedge | Putter

let club_label = function
  | Driver -> "Driver"
  | Iron -> "Iron"
  | Wedge -> "Wedge"
  | Putter -> "Putter"

(* Max distance scaling and launch angle (controls vz at swing time). *)
let club_max_speed = function
  | Driver -> 22.0
  | Iron -> 17.0
  | Wedge -> 11.0
  | Putter -> 8.0

let club_launch = function
  | Driver -> 7.0 (* high arc *)
  | Iron -> 5.0
  | Wedge -> 8.5 (* highest, short distance *)
  | Putter -> 0.0 (* on the ground *)

let next_club = function
  | Driver -> Iron
  | Iron -> Wedge
  | Wedge -> Putter
  | Putter -> Driver

(* ---------- hole ---------- *)

type hole = {
  layout : tile array array; (* row-major: layout.(y).(x) *)
  width : int;
  height : int;
  tee : int * int;
  cup : int * int;
  par : int;
  wind : float * float;
}

let parse_hole (rows : string array) ~par ~wind =
  let h = Array.length rows in
  let w = if h = 0 then 0 else String.length rows.(0) in
  let layout = Array.make_matrix h w Wall_oob in
  let tee = ref (1, 1) in
  let cup = ref (w - 2, h / 2) in
  for y = 0 to h - 1 do
    let row = rows.(y) in
    let row_w = String.length row in
    for x = 0 to w - 1 do
      let c = if x < row_w then row.[x] else '#' in
      let t = tile_of_char c in
      layout.(y).(x) <- t ;
      match t with
      | Tee ->
          tee := (x, y) ;
          layout.(y).(x) <- Fairway
      | Cup -> cup := (x, y)
      | _ -> ()
    done
  done ;
  {layout; width = w; height = h; tee = !tee; cup = !cup; par; wind}

let load_hole_idx i =
  let rows, par, wind = Courses.holes.(i) in
  parse_hole rows ~par ~wind

let tile_at (h : hole) ~x ~y =
  if x < 0 || y < 0 || x >= h.width || y >= h.height then Wall_oob
  else h.layout.(y).(x)

let tile_at_ball (h : hole) (b : ball) =
  let x = int_of_float b.x in
  let y = int_of_float b.y in
  tile_at h ~x ~y

(* ---------- game ---------- *)

type game = {
  mutable hole_idx : int;
  mutable hole : hole;
  ball : ball;
  mutable strokes : int;
  (* prior position before the latest swing (for water-replay). *)
  mutable prev_x : float;
  mutable prev_y : float;
  mutable club : club;
  (* per-swing wind shifted ±10% from the hole's base wind. *)
  mutable shot_wind : float * float;
  (* short-lived banner text shown above the HUD. *)
  mutable last_event : string;
  mutable last_event_t : float;
  (* Celebration stars timer: counts down from 0.5 s on hole-clear. *)
  mutable celebration_t : float;
  (* Water penalty overlay: counts down from 1.2 s; position is the splash. *)
  mutable water_penalty_t : float;
  mutable water_penalty_pos : float * float;
  (* OOB penalty overlay: counts down from 1.2 s; position is OOB entry. *)
  mutable oob_penalty_t : float;
  mutable oob_penalty_pos : float * float;
  (* Cached static terrain buffer: (px_w * px_h, buffer).
     Built once per hole/resolution and reused every frame.
     Water tiles are painted on top each frame (time-varying shimmer). *)
  mutable bg_cache : (int * Bytes.t) option;
  (* Wind gust system: timer counts down to trigger a gust; remaining counts
     down while the gust is active; delta is the extra wind added during the
     gust. A gust at swing time is included in shot_wind. *)
  mutable gust_timer : float;
  mutable gust_remaining : float;
  mutable gust_delta : float * float;
  (* Landing divot visual: counts down from ~0.5 when ball touches down. *)
  mutable ball_land_t : float;
  (* Chip-in flag: set when ball was in-flight (z > 1.0) on entering the cup. *)
  mutable chip_in : bool;
}

let make_game ~hole_idx =
  let hole = load_hole_idx hole_idx in
  let tx, ty = hole.tee in
  let ball = make_ball () in
  ball.x <- float_of_int tx +. 0.5 ;
  ball.y <- float_of_int ty +. 0.5 ;
  {
    hole_idx;
    hole;
    ball;
    strokes = 0;
    prev_x = ball.x;
    prev_y = ball.y;
    club = Driver;
    shot_wind = hole.wind;
    last_event = "";
    last_event_t = 0.0;
    celebration_t = 0.0;
    water_penalty_t = 0.0;
    water_penalty_pos = (0.0, 0.0);
    oob_penalty_t = 0.0;
    oob_penalty_pos = (0.0, 0.0);
    bg_cache = None;
    (* First gust triggers between 2 and 8 seconds into the hole. *)
    gust_timer = 2.0 +. Random.float 6.0;
    gust_remaining = 0.0;
    gust_delta = (0.0, 0.0);
    ball_land_t = 0.0;
    chip_in = false;
  }

let reset_to_tee (g : game) =
  let tx, ty = g.hole.tee in
  g.ball.x <- float_of_int tx +. 0.5 ;
  g.ball.y <- float_of_int ty +. 0.5 ;
  g.ball.z <- 0.0 ;
  g.ball.vx <- 0.0 ;
  g.ball.vy <- 0.0 ;
  g.ball.vz <- 0.0 ;
  g.ball.in_flight <- false ;
  g.strokes <- 0 ;
  g.prev_x <- g.ball.x ;
  g.prev_y <- g.ball.y

(* ---------- top-level state ---------- *)

type powering_data = {
  mutable game : game;
  mutable aim_angle : float;
  mutable meter01 : float;
  mutable rising : bool;
}

type aiming_data = {mutable a_game : game; mutable a_aim : float}

type flight_data = {mutable f_game : game; mutable f_t : float}

type clear_data = {mutable c_game : game}

type summary_data = {
  mutable scorecard : int array; (* strokes per played hole *)
  mutable best_under_par : int; (* persisted under-par best *)
}

(* ---------- shop / perk-pick / boss-intro substates ---------- *)

type shop_data = {
  mutable s_options : (int * int) array;
      (* (perk_index, cost) — perk_index into perks_catalogue *)
  mutable s_cursor : int;
}

type perk_pick_data = {
  mutable pp_options : int array; (* indices into perks_catalogue; usually 3 *)
  mutable pp_cursor : int;
}

type boss_intro_data = {mutable bi_name : string; mutable bi_t : float}

type run_complete_data = {
  mutable rc_final_score : int;
  mutable rc_coins_earned : int;
  mutable rc_under_par : int;
}

type hole_preview_data = {mutable hp_game : game; mutable hp_t : float}

type state =
  | Title
  | New_run_intro
  | In_shop of shop_data
  | Course_select of {mutable cursor : int}
  | Hole_preview of hole_preview_data
  | Aiming of aiming_data
  | Powering of powering_data
  | In_flight of flight_data
  | Hole_clear of clear_data
  | Perk_pick of perk_pick_data
  | Boss_intro of boss_intro_data
  | Run_complete of run_complete_data
  | Run_failed of run_complete_data
  | Card_summary of summary_data

(* ---------- perks ---------- *)

type perk =
  | Plus_one_stamina
  | Wind_breaker
  | Sand_legs
  | Power_swing
  | Putter_genius
  | Lucky_bounce
  | Stroke_saver
  | Coin_magnet
  | Eagle_eye
  | Storm_caller
  | Birdie_bonus
  | Iron_will
  | Backspin
  | Double_down
  | Rough_ready
  | Albatross_alert

let all_perks =
  [|
    Plus_one_stamina;
    Wind_breaker;
    Sand_legs;
    Power_swing;
    Putter_genius;
    Lucky_bounce;
    Stroke_saver;
    Coin_magnet;
    Eagle_eye;
    Storm_caller;
    Birdie_bonus;
    Iron_will;
    Backspin;
    Double_down;
    Rough_ready;
    Albatross_alert;
  |]

let perk_label = function
  | Plus_one_stamina -> "+1 Stamina"
  | Wind_breaker -> "Wind Breaker"
  | Sand_legs -> "Sand Legs"
  | Power_swing -> "Power Swing"
  | Putter_genius -> "Putter Genius"
  | Lucky_bounce -> "Lucky Bounce"
  | Stroke_saver -> "Stroke Saver"
  | Coin_magnet -> "Coin Magnet"
  | Eagle_eye -> "Eagle Eye"
  | Storm_caller -> "Storm Caller"
  | Birdie_bonus -> "Birdie Bonus"
  | Iron_will -> "Iron Will"
  | Backspin -> "Backspin"
  | Double_down -> "Double Down"
  | Rough_ready -> "Rough Ready"
  | Albatross_alert -> "Albatross!"

let perk_glyph = function
  | Plus_one_stamina -> "+S"
  | Wind_breaker -> "Wb"
  | Sand_legs -> "Sl"
  | Power_swing -> "Pw"
  | Putter_genius -> "Pg"
  | Lucky_bounce -> "Lb"
  | Stroke_saver -> "Ss"
  | Coin_magnet -> "Cm"
  | Eagle_eye -> "Ee"
  | Storm_caller -> "Sc"
  | Birdie_bonus -> "Bb"
  | Iron_will -> "Iw"
  | Backspin -> "Bs"
  | Double_down -> "Dd"
  | Rough_ready -> "Rr"
  | Albatross_alert -> "Al"

let perk_desc = function
  | Plus_one_stamina -> "Recover one stroke right now."
  | Wind_breaker -> "Wind effect halved this run."
  | Sand_legs -> "No friction penalty in sand."
  | Power_swing -> "Driver max distance +20%."
  | Putter_genius -> "Putter accuracy +5% (less spread)."
  | Lucky_bounce -> "25% chance to redirect water shots."
  | Stroke_saver -> "Every 4th hole grants +1 stamina."
  | Coin_magnet -> "+50% coins from this run."
  | Eagle_eye -> "Longer aim arrow, snap-to-cup helper."
  | Storm_caller -> "Wind benefits you, hurts hazards."
  | Birdie_bonus -> "Each birdie awards +2 coins."
  | Iron_will -> "Ignore first water penalty this run."
  | Backspin -> "Ball reverses 20% on green landing — stops near the cup."
  | Double_down -> "Birdie or better: coins doubled for the hole."
  | Rough_ready -> "Rough terrain doesn't slow you down."
  | Albatross_alert -> "2+ under par: bonus +4 coins."

(* Cost in coins for the pre-run shop. *)
let perk_shop_cost = function
  | Plus_one_stamina -> 12
  | Wind_breaker -> 18
  | Sand_legs -> 14
  | Power_swing -> 22
  | Putter_genius -> 16
  | Lucky_bounce -> 24
  | Stroke_saver -> 20
  | Coin_magnet -> 30
  | Eagle_eye -> 18
  | Storm_caller -> 28
  | Birdie_bonus -> 14
  | Iron_will -> 16
  | Backspin -> 20
  | Double_down -> 15
  | Rough_ready -> 16
  | Albatross_alert -> 20

(* ---------- run state ---------- *)

type run = {
  mutable hole_seq : int array; (* indices into Courses.holes *)
  mutable run_pos : int; (* current index in hole_seq *)
  mutable stamina : int; (* total strokes left across the run *)
  mutable max_stamina : int;
  mutable run_score : int; (* total strokes used across the run *)
  mutable active_perks : perk list; (* picked / bought during run *)
  mutable iron_will_used : bool;
  mutable run_seed : int;
}

let holes_per_run = 9

let run_starting_stamina = 45

let make_run ~seed ~start_perks =
  let st = Random.State.make [|seed; 0xBEEF|] in
  let pool = Courses.count in
  let hole_seq =
    Array.init holes_per_run (fun i ->
        if i mod 3 = 2 && Courses.boss_count > 0 then
          (* Every 3rd is a boss hole; pick from boss pool. *)
          let bi = Random.State.int st Courses.boss_count in
          Courses.boss_indices.(bi)
        else Random.State.int st pool)
  in
  {
    hole_seq;
    run_pos = 0;
    stamina = run_starting_stamina;
    max_stamina = run_starting_stamina;
    run_score = 0;
    active_perks = start_perks;
    iron_will_used = false;
    run_seed = seed;
  }

let run_is_boss_hole (r : run) =
  let pos = r.run_pos in
  pos mod 3 = 2

(* ---------- top-level state ---------- *)

type t = {
  mutable mode : state;
  mutable mode_t : float;
  particles : Arcade_kit.Particles.t;
  fx : Arcade_kit.Screen_fx.t;
  rng : Random.State.t;
  mutable best_under_par : int;
  mutable scorecard : int array;
  mutable next_page : string option;
  (* roguelite *)
  mutable coins : int;
  mutable best_run_score : int;
  mutable run : run option;
  mutable last_birdies : int;
  (* Eagle/albatross stamina-restore banner timer. *)
  mutable eagle_stamina_restore_t : float;
  (* Wind gust visual timer: set to 1.5 when a gust triggers, counts down. *)
  mutable gust_visual_t : float;
}

let particle_capacity = 256

let has_perk (s : t) p =
  match s.run with None -> false | Some r -> List.mem p r.active_perks

(* Persistent coin store via a parallel score-store entry. *)
let coins_demo_key = "miaou_links_coins"

let best_run_demo_key = "miaou_links_best_run"

let load_coins () = Arcade_kit.Score_store.load ~demo:coins_demo_key

let save_coins c = Arcade_kit.Score_store.save ~demo:coins_demo_key c

let add_coins (s : t) n =
  s.coins <- s.coins + n ;
  save_coins s.coins

let spend_coins (s : t) n =
  if s.coins >= n then begin
    s.coins <- s.coins - n ;
    save_coins s.coins ;
    true
  end
  else false

let init () =
  let best = Arcade_kit.Score_store.load ~demo:"miaou_links" in
  let coins = load_coins () in
  let best_run = Arcade_kit.Score_store.load ~demo:best_run_demo_key in
  {
    mode = Title;
    mode_t = 0.0;
    particles = Arcade_kit.Particles.create ~capacity:particle_capacity;
    fx = Arcade_kit.Screen_fx.create ();
    rng = Random.State.make [|0xC0FF; 0xEEEE|];
    best_under_par = best;
    scorecard = Array.make Courses.count 0;
    next_page = None;
    coins;
    best_run_score = best_run;
    run = None;
    last_birdies = 0;
    eagle_stamina_restore_t = 0.0;
    gust_visual_t = 0.0;
  }

(* ---------- mode helpers ---------- *)

let begin_round (s : t) =
  s.scorecard <- Array.make Courses.count 0 ;
  s.mode <- Course_select {cursor = 0} ;
  s.mode_t <- 0.0

let begin_hole (s : t) ~idx =
  let g = make_game ~hole_idx:idx in
  s.mode <- Hole_preview {hp_game = g; hp_t = 0.0} ;
  s.mode_t <- 0.0

let aim_to_powering (a : aiming_data) =
  Powering {game = a.a_game; aim_angle = a.a_aim; meter01 = 0.0; rising = true}

(* ---------- physics ---------- *)

let friction_for_tile (s : t) tile =
  match tile with
  | Fairway | Tee -> 0.6
  | Green | Cup -> 0.15
  | Rough -> if has_perk s Rough_ready then 1.2 else 2.0
  | Sand -> if has_perk s Sand_legs then 0.9 else 4.0
  | Water -> 0.6 (* ignored — we trigger the water rule before friction *)
  | Wall_oob -> 0.0

let stop_eps = 0.05

(* Reflect ball velocity off a wall when the next position would be
   out-of-bounds. We do an axis-aligned check separately. *)
let resolve_walls (g : game) =
  let h = g.hole in
  let nx = g.ball.x +. (g.ball.vx *. (1.0 /. 60.0)) in
  let ny = g.ball.y +. (g.ball.vy *. (1.0 /. 60.0)) in
  if tile_at h ~x:(int_of_float nx) ~y:(int_of_float g.ball.y) = Wall_oob then
    g.ball.vx <- -.g.ball.vx *. 0.6 ;
  if tile_at h ~x:(int_of_float g.ball.x) ~y:(int_of_float ny) = Wall_oob then
    g.ball.vy <- -.g.ball.vy *. 0.6

(* Distance from (x,y) to cup centre. *)
let dist_to_cup (g : game) =
  let cx, cy = g.hole.cup in
  let dx = g.ball.x -. (float_of_int cx +. 0.5) in
  let dy = g.ball.y -. (float_of_int cy +. 0.5) in
  sqrt ((dx *. dx) +. (dy *. dy))

let ball_speed (b : ball) = sqrt ((b.vx *. b.vx) +. (b.vy *. b.vy))

(* Shift the hole-wind by ±10% per shot (deterministic-ish using rng).
   Wind_breaker halves wind magnitude. Storm_caller doubles it (risky).
   If a gust is currently active, its delta is folded in so it affects the shot. *)
let pick_shot_wind (s : t) (g : game) =
  let bx, by = g.hole.wind in
  let scale =
    let s1 = if has_perk s Wind_breaker then 0.5 else 1.0 in
    let s2 = if has_perk s Storm_caller then 1.8 else 1.0 in
    s1 *. s2
  in
  let jx = Random.State.float s.rng 0.2 -. 0.1 in
  let jy = Random.State.float s.rng 0.2 -. 0.1 in
  let gx, gy = if g.gust_remaining > 0.0 then g.gust_delta else (0.0, 0.0) in
  ((bx *. scale *. (1.0 +. jx)) +. gx, (by *. scale *. (1.0 +. jy)) +. gy)

let effective_max_speed (s : t) club =
  let base = club_max_speed club in
  if club = Driver && has_perk s Power_swing then base *. 1.2 else base

let swing (s : t) (p : powering_data) =
  let g = p.game in
  let speed = effective_max_speed s g.club *. p.meter01 in
  (* Putter genius narrows the spread a hair (lessens random wind jitter). *)
  let acc_bonus =
    if g.club = Putter && has_perk s Putter_genius then 0.95 else 1.0
  in
  g.ball.vx <- cos p.aim_angle *. speed *. acc_bonus ;
  g.ball.vy <- sin p.aim_angle *. speed *. acc_bonus ;
  g.ball.vz <- club_launch g.club *. p.meter01 ;
  g.ball.in_flight <- g.ball.vz > 0.05 ;
  g.strokes <- g.strokes + 1 ;
  (match s.run with Some r -> r.stamina <- max 0 (r.stamina - 1) | None -> ()) ;
  g.prev_x <- g.ball.x ;
  g.prev_y <- g.ball.y ;
  g.shot_wind <- pick_shot_wind s g ;
  g.last_event <-
    Printf.sprintf
      "Stroke %d (%s, %d%%)"
      g.strokes
      (club_label g.club)
      (int_of_float (p.meter01 *. 100.0)) ;
  g.last_event_t <- 0.8

(* Advance the wind-gust system.  Decrement the pending timer; when it fires,
   pick a random gust delta (±30% of hole wind magnitude, minimum 0.15) and set
   the gust duration.  While active, decrement the remaining counter. *)
let tick_gust (s : t) (g : game) ~dt =
  if g.gust_remaining > 0.0 then begin
    g.gust_remaining <- Float.max 0.0 (g.gust_remaining -. dt)
  end
  else begin
    g.gust_timer <- g.gust_timer -. dt ;
    if g.gust_timer <= 0.0 then begin
      (* Trigger a new gust. *)
      let base_x, base_y = g.hole.wind in
      let mag =
        Float.max 0.15 (sqrt ((base_x *. base_x) +. (base_y *. base_y)))
      in
      let angle = Random.State.float s.rng (2.0 *. Float.pi) in
      let strength = mag *. (0.2 +. Random.State.float s.rng 0.2) in
      g.gust_delta <- (strength *. cos angle, strength *. sin angle) ;
      g.gust_remaining <- 1.5 ;
      (* Set gust visual timer so the view can show whoosh marks. *)
      s.gust_visual_t <- 1.5 ;
      (* Next gust between 3 and 8 seconds later. *)
      g.gust_timer <- 3.0 +. Random.State.float s.rng 5.0
    end
  end

let tick_ball (s : t) (g : game) ~dt =
  let b = g.ball in
  if b.in_flight then begin
    let prev_z = b.z in
    b.x <- b.x +. (b.vx *. dt) ;
    b.y <- b.y +. (b.vy *. dt) ;
    (* Wind nudge while flying. *)
    let wx, wy = g.shot_wind in
    b.vx <- b.vx +. (wx *. dt) ;
    b.vy <- b.vy +. (wy *. dt) ;
    (* Gravity-ish. *)
    b.vz <- b.vz -. (12.0 *. dt) ;
    b.z <- b.z +. (b.vz *. dt) ;
    if b.z <= 0.0 then begin
      b.z <- 0.0 ;
      b.in_flight <- false ;
      (* On landing, lose some forward speed. *)
      b.vx <- b.vx *. 0.7 ;
      b.vy <- b.vy *. 0.7 ;
      (* Tile-specific landing modifiers. *)
      let landing_tile = tile_at_ball g.hole b in
      (match landing_tile with
      | Rough ->
          (* 10% speed reduction on rough landing. *)
          b.vx <- b.vx *. 0.9 ;
          b.vy <- b.vy *. 0.9
      | Sand ->
          (* Sand: clamp speed to 1.5 and add a 45°-rotated drift component. *)
          let spd = ball_speed b in
          let max_sand_spd = 1.5 in
          if spd > max_sand_spd then begin
            let scale = max_sand_spd /. spd in
            b.vx <- b.vx *. scale ;
            b.vy <- b.vy *. scale
          end ;
          (* Sideways drift: 5% of the clamped velocity rotated 45°. *)
          let drift_frac = 0.05 in
          let cos45 = 0.7071 in
          let sin45 = 0.7071 in
          let dvx = ((b.vx *. cos45) -. (b.vy *. sin45)) *. drift_frac in
          let dvy = ((b.vx *. sin45) +. (b.vy *. cos45)) *. drift_frac in
          b.vx <- b.vx +. dvx ;
          b.vy <- b.vy +. dvy
      | Green | Cup ->
          (* Backspin: on green landing, apply a 20% reverse velocity to
             simulate the ball checking and stopping near the cup. *)
          if has_perk s Backspin then begin
            b.vx <- b.vx *. -0.2 ;
            b.vy <- b.vy *. -0.2
          end
      | _ -> ()) ;
      (* Dirt/divot burst on landing — tan/sand particles. *)
      Arcade_kit.Particles.spawn_burst
        s.particles
        ~x:b.x
        ~y:b.y
        ~n:8
        ~speed:8.0
        ~life:0.4
        ~hue:6
        ~rng:s.rng ;
      (* Landing divot visual: set timer so view renders a fading ring. *)
      g.ball_land_t <- 0.5 ;
      (* Chip-in detection: ball was high (z > 1.0 before landing) and
         lands directly in the cup capture zone. *)
      if prev_z > 1.0 && dist_to_cup g < 0.7 then g.chip_in <- true
    end
  end
  else begin
    let t = tile_at_ball g.hole b in
    let f = friction_for_tile s t in
    let v = ball_speed b in
    if v > 0.0 then begin
      let drag = f *. dt in
      let new_v = Float.max 0.0 (v -. drag) in
      let scale = if v > 0.0 then new_v /. v else 0.0 in
      b.vx <- b.vx *. scale ;
      b.vy <- b.vy *. scale
    end ;
    let prev_bx = b.x in
    let prev_by = b.y in
    b.x <- b.x +. (b.vx *. dt) ;
    b.y <- b.y +. (b.vy *. dt) ;
    (* OOB check: if the ball rolled into an out-of-bounds tile, revert
       the position, stop the ball, and apply a +1 stroke penalty. *)
    if tile_at_ball g.hole b = Wall_oob then begin
      g.oob_penalty_pos <- (b.x, b.y) ;
      b.x <- prev_bx ;
      b.y <- prev_by ;
      b.vx <- 0.0 ;
      b.vy <- 0.0 ;
      g.strokes <- g.strokes + 1 ;
      (match s.run with
      | Some r -> r.stamina <- max 0 (r.stamina - 1)
      | None -> ()) ;
      g.last_event <- "OUT OF BOUNDS +1" ;
      g.last_event_t <- 1.8 ;
      g.oob_penalty_t <- 1.2
    end
  end ;
  (* Tick down ball_land_t after every frame, regardless of in_flight. *)
  if g.ball_land_t > 0.0 then
    g.ball_land_t <- Float.max 0.0 (g.ball_land_t -. dt) ;
  resolve_walls g ;
  (* ball-trail particles — bright white/green, more visible *)
  if b.in_flight && Random.State.float s.rng 1.0 < 0.7 then
    Arcade_kit.Particles.spawn
      s.particles
      ~x:b.x
      ~y:b.y
      ~vx:0.0
      ~vy:0.0
      ~life:0.4
      ~hue:1

let stroke_penalty_water (s : t) (g : game) =
  let splash_x = g.ball.x in
  let splash_y = g.ball.y in
  (* Iron_will: ignore the very first water of the run (one-shot). *)
  let iron_will_active =
    match s.run with
    | Some r when has_perk s Iron_will && not r.iron_will_used ->
        r.iron_will_used <- true ;
        true
    | _ -> false
  in
  (* Lucky_bounce: 25% chance to redirect — keep velocity, push ball
     back to the prior fairway position WITHOUT the stroke penalty. *)
  let lucky = has_perk s Lucky_bounce && Random.State.float s.rng 1.0 < 0.25 in
  g.ball.x <- g.prev_x ;
  g.ball.y <- g.prev_y ;
  g.ball.z <- 0.0 ;
  g.ball.vx <- 0.0 ;
  g.ball.vy <- 0.0 ;
  g.ball.vz <- 0.0 ;
  g.ball.in_flight <- false ;
  if iron_will_active then begin
    g.last_event <- "Iron Will saved you" ;
    g.last_event_t <- 1.4
  end
  else if lucky then begin
    g.last_event <- "Lucky bounce!" ;
    g.last_event_t <- 1.4
  end
  else begin
    g.strokes <- g.strokes + 1 ;
    (match s.run with
    | Some r -> r.stamina <- max 0 (r.stamina - 1)
    | None -> ()) ;
    g.last_event <- "Splash! +1 stroke" ;
    g.last_event_t <- 1.4 ;
    (* Show water penalty overlay above the splash site. *)
    g.water_penalty_t <- 1.2 ;
    g.water_penalty_pos <- (splash_x, splash_y)
  end ;
  Arcade_kit.Screen_fx.flash s.fx ~intensity:0.5 ~duration:0.3 ;
  Arcade_kit.Particles.spawn_burst
    s.particles
    ~x:splash_x
    ~y:splash_y
    ~n:24
    ~speed:3.0
    ~life:0.7
    ~hue:3
    ~rng:s.rng ;
  (* Outer ring of finer mist *)
  Arcade_kit.Particles.spawn_burst
    s.particles
    ~x:splash_x
    ~y:splash_y
    ~n:12
    ~speed:5.0
    ~life:0.4
    ~hue:3
    ~rng:s.rng

(* Returns true when the ball has entered the cup. Eagle_eye widens the
   capture radius slightly. *)
let try_cup_in (s : t) (g : game) =
  let radius = if has_perk s Eagle_eye then 0.85 else 0.6 in
  if dist_to_cup g < radius && ball_speed g.ball < 0.5 && not g.ball.in_flight
  then true
  else false

let ball_settled (g : game) =
  (not g.ball.in_flight) && ball_speed g.ball < stop_eps

(* ---------- handlers per state ---------- *)

let aim_step_small = 0.03

let aim_step_big = 0.1

let rotate_aim (a : aiming_data) ~step = a.a_aim <- a.a_aim +. step

let rotate_aim_powering (p : powering_data) ~step =
  p.aim_angle <- p.aim_angle +. step

let cycle_club (g : game) = g.club <- next_club g.club

(* ---------- main tick ---------- *)

let advance_powering (p : powering_data) ~dt =
  let rate = 1.6 in
  if p.rising then begin
    p.meter01 <- p.meter01 +. (rate *. dt) ;
    if p.meter01 >= 1.0 then begin
      p.meter01 <- 1.0 ;
      p.rising <- false
    end
  end
  else begin
    p.meter01 <- p.meter01 -. (rate *. dt) ;
    if p.meter01 <= 0.0 then begin
      p.meter01 <- 0.0 ;
      p.rising <- true
    end
  end

let advance_flight (s : t) (f : flight_data) ~dt =
  f.f_t <- f.f_t +. dt ;
  let g = f.f_game in
  tick_ball s g ~dt ;
  (* Did the ball hit water (only applies when not in flight). *)
  let t = tile_at_ball g.hole g.ball in
  if (not g.ball.in_flight) && t = Water then stroke_penalty_water s g ;
  (* In the cup? *)
  if try_cup_in s g then begin
    let was_hole_in_one = g.strokes = 1 in
    if was_hole_in_one then begin
      (* Bonus on any hole-in-one: stamina +3, coins +8. *)
      (match s.run with
      | Some r -> r.stamina <- min (r.max_stamina + 3) (r.stamina + 3)
      | None -> ()) ;
      add_coins s 8 ;
      g.last_event <- "HOLE-IN-ONE! +3 Stam +$8" ;
      g.last_event_t <- 2.0
    end
    else begin
      g.last_event <- "In the cup!" ;
      g.last_event_t <- 1.4
    end ;
    g.celebration_t <- 0.5 ;
    s.scorecard.(g.hole_idx) <- g.strokes ;
    Arcade_kit.Particles.spawn_burst
      s.particles
      ~x:g.ball.x
      ~y:g.ball.y
      ~n:24
      ~speed:2.5
      ~life:0.9
      ~hue:8
      ~rng:s.rng ;
    s.mode <- Hole_clear {c_game = g} ;
    s.mode_t <- 0.0
  end
  else if ball_settled g then begin
    (* Either back to aiming for the next stroke. *)
    s.mode <- Aiming {a_game = g; a_aim = 0.0}
  end ;
  if g.last_event_t > 0.0 then g.last_event_t <- g.last_event_t -. dt ;
  if g.water_penalty_t > 0.0 then
    g.water_penalty_t <- Float.max 0.0 (g.water_penalty_t -. dt) ;
  if g.oob_penalty_t > 0.0 then
    g.oob_penalty_t <- Float.max 0.0 (g.oob_penalty_t -. dt)

let tick (s : t) ~dt =
  s.mode_t <- s.mode_t +. dt ;
  if s.eagle_stamina_restore_t > 0.0 then
    s.eagle_stamina_restore_t <- Float.max 0.0 (s.eagle_stamina_restore_t -. dt) ;
  if s.gust_visual_t > 0.0 then
    s.gust_visual_t <- Float.max 0.0 (s.gust_visual_t -. dt) ;
  Arcade_kit.Particles.tick s.particles ~dt ~ax:0.0 ~ay:0.0 ;
  Arcade_kit.Screen_fx.tick s.fx ~dt ;
  match s.mode with
  | Title | Course_select _ | New_run_intro | In_shop _ | Perk_pick _
  | Run_complete _ | Run_failed _ ->
      ()
  | Hole_preview hp ->
      hp.hp_t <- hp.hp_t +. dt ;
      (* Auto-advance to Aiming after 2 seconds. *)
      if hp.hp_t >= 2.0 then begin
        s.mode <- Aiming {a_game = hp.hp_game; a_aim = 0.0} ;
        s.mode_t <- 0.0
      end
  | Boss_intro bi ->
      bi.bi_t <- bi.bi_t +. dt ;
      if bi.bi_t > 1.7 then begin
        (* Auto-advance into Aiming on the boss hole. *)
        match s.run with
        | None -> ()
        | Some r ->
            let idx = r.hole_seq.(r.run_pos) in
            let g = make_game ~hole_idx:idx in
            s.mode <- Aiming {a_game = g; a_aim = 0.0} ;
            s.mode_t <- 0.0
      end
  | Aiming a ->
      let g = a.a_game in
      tick_gust s g ~dt ;
      if g.water_penalty_t > 0.0 then
        g.water_penalty_t <- Float.max 0.0 (g.water_penalty_t -. dt) ;
      if g.oob_penalty_t > 0.0 then
        g.oob_penalty_t <- Float.max 0.0 (g.oob_penalty_t -. dt)
  | Powering p ->
      tick_gust s p.game ~dt ;
      advance_powering p ~dt
  | In_flight f ->
      tick_gust s f.f_game ~dt ;
      advance_flight s f ~dt
  | Hole_clear c ->
      let g = c.c_game in
      if g.celebration_t > 0.0 then
        g.celebration_t <- Float.max 0.0 (g.celebration_t -. dt)
  | Card_summary _ -> ()

(* ---------- card / round flow ---------- *)

(* Legacy "tour" round flow (retained for backwards compat — Course_select). *)
let advance_after_hole (s : t) (g : game) =
  let next = g.hole_idx + 1 in
  if next >= Courses.count then begin
    let total = Array.fold_left ( + ) 0 s.scorecard in
    let under_par = Courses.par_total - total in
    s.best_under_par <-
      Arcade_kit.Score_store.record ~demo:"miaou_links" under_par ;
    s.mode <-
      Card_summary
        {scorecard = Array.copy s.scorecard; best_under_par = s.best_under_par} ;
    s.mode_t <- 0.0
  end
  else begin
    let g' = make_game ~hole_idx:next in
    s.mode <- Hole_preview {hp_game = g'; hp_t = 0.0} ;
    s.mode_t <- 0.0
  end

(* ---------- roguelite run flow ---------- *)

(* Pick three random distinct perk indices for the perk-pick screen. *)
let pick_three_perks (s : t) =
  let n = Array.length all_perks in
  let chosen = Array.make 3 (-1) in
  let i = ref 0 in
  let attempts = ref 0 in
  while !i < 3 && !attempts < 200 do
    incr attempts ;
    let cand = Random.State.int s.rng n in
    let ok = ref true in
    for k = 0 to !i - 1 do
      if chosen.(k) = cand then ok := false
    done ;
    if !ok then begin
      chosen.(!i) <- cand ;
      incr i
    end
  done ;
  chosen

(* Build the pre-run shop. We list ~5 random perks with costs the player can
   buy from persistent coins. *)
let build_shop (s : t) =
  let n = Array.length all_perks in
  let count = 5 in
  let chosen = Array.make count (-1, 0) in
  let i = ref 0 in
  let attempts = ref 0 in
  while !i < count && !attempts < 200 do
    incr attempts ;
    let cand = Random.State.int s.rng n in
    let ok = ref true in
    for k = 0 to !i - 1 do
      if fst chosen.(k) = cand then ok := false
    done ;
    if !ok then begin
      let cost = perk_shop_cost all_perks.(cand) in
      chosen.(!i) <- (cand, cost) ;
      incr i
    end
  done ;
  {s_options = chosen; s_cursor = 0}

let begin_new_run (s : t) =
  let seed = Random.State.int s.rng 0x3FFFFFFF in
  s.run <- Some (make_run ~seed ~start_perks:[]) ;
  s.last_birdies <- 0 ;
  s.scorecard <- Array.make Courses.count 0 ;
  s.mode <- In_shop (build_shop s) ;
  s.mode_t <- 0.0

(* Boot the first hole of the current run, possibly via Boss_intro. *)
let begin_run_hole (s : t) =
  match s.run with
  | None -> ()
  | Some r ->
      if r.run_pos >= Array.length r.hole_seq then begin
        (* Run complete — transition to Run_complete. *)
        let total = r.run_score in
        let par_used =
          let acc = ref 0 in
          Array.iter
            (fun idx ->
              let _, p, _ = Courses.holes.(idx) in
              acc := !acc + p)
            r.hole_seq ;
          !acc
        in
        let under = par_used - total in
        let coin_mult = if has_perk s Coin_magnet then 1.5 else 1.0 in
        let base_coins =
          (* Base 5 coins per hole completed + bonus per under-par stroke. *)
          (Array.length r.hole_seq * 5) + (max 0 under * 4)
        in
        let earned = int_of_float (float_of_int base_coins *. coin_mult) in
        add_coins s earned ;
        if under > 0 then
          s.best_run_score <-
            Arcade_kit.Score_store.record ~demo:best_run_demo_key under ;
        s.mode <-
          Run_complete
            {
              rc_final_score = total;
              rc_coins_earned = earned;
              rc_under_par = under;
            } ;
        s.mode_t <- 0.0
      end
      else if r.stamina <= 0 then begin
        (* Out of stamina — run failed. *)
        s.mode <-
          Run_failed
            {
              rc_final_score = r.run_score;
              rc_coins_earned = 0;
              rc_under_par = 0;
            } ;
        s.mode_t <- 0.0
      end
      else begin
        let idx = r.hole_seq.(r.run_pos) in
        if run_is_boss_hole r then begin
          let names =
            [|
              "Cliffside Crucible";
              "Eye of the Storm";
              "Cauldron Carry";
              "Tempest Tee";
            |]
          in
          let name = names.(r.run_pos / 3 mod Array.length names) in
          s.mode <- Boss_intro {bi_name = name; bi_t = 0.0} ;
          s.mode_t <- 0.0
        end
        else begin
          let g = make_game ~hole_idx:idx in
          s.mode <- Hole_preview {hp_game = g; hp_t = 0.0} ;
          s.mode_t <- 0.0
        end
      end

(* Apply an immediate-effect perk (e.g. +1 Stamina is consumed straight away).
   Most perks are "long-term" and just append to active_perks. *)
let apply_perk (s : t) (p : perk) =
  match s.run with
  | None -> ()
  | Some r ->
      (match p with
      | Plus_one_stamina -> r.stamina <- min (r.max_stamina + 1) (r.stamina + 1)
      | _ -> ()) ;
      r.active_perks <- p :: r.active_perks

let buy_from_shop (s : t) (sd : shop_data) =
  let pi, cost = sd.s_options.(sd.s_cursor) in
  if pi < 0 then ()
  else if spend_coins s cost then begin
    apply_perk s all_perks.(pi) ;
    (* Mark as bought by zeroing out — set perk index to -1. *)
    sd.s_options.(sd.s_cursor) <- (-1, 0)
  end

let leave_shop (s : t) = begin_run_hole s

let advance_after_run_hole (s : t) (g : game) =
  match s.run with
  | None -> advance_after_hole s g (* fallback to legacy flow *)
  | Some r ->
      r.run_score <- r.run_score + g.strokes ;
      let _, par, _ = Courses.holes.(g.hole_idx) in
      let delta = g.strokes - par in
      (* Base per-hole coin award: 5 coins for completion, +2 per stroke under par. *)
      let hole_coins = 5 + (max 0 (-delta) * 2) in
      (* Double Down: birdie or better doubles the hole coin reward. *)
      let hole_coins =
        if has_perk s Double_down && delta < 0 then hole_coins * 2
        else hole_coins
      in
      add_coins s hole_coins ;
      if delta < 0 then begin
        s.last_birdies <- s.last_birdies + 1 ;
        if has_perk s Birdie_bonus then add_coins s 2
      end ;
      (* Albatross_alert: 2+ under par awards +4 bonus coins. *)
      if has_perk s Albatross_alert && delta <= -2 then add_coins s 4 ;
      (* Eagle (or better) stamina restore: free +1 stamina for eagle or albatross. *)
      if delta <= -2 then begin
        (match s.run with
        | Some r2 -> r2.stamina <- min (r2.max_stamina + 2) (r2.stamina + 1)
        | None -> ()) ;
        s.eagle_stamina_restore_t <- 1.5
      end ;
      (* Stroke_saver: every 4th hole grants +1 stamina. *)
      let pos_after = r.run_pos + 1 in
      if has_perk s Stroke_saver && pos_after mod 4 = 0 then
        r.stamina <- min (r.max_stamina + 2) (r.stamina + 1) ;
      r.run_pos <- pos_after ;
      if r.run_pos >= Array.length r.hole_seq then begin
        begin_run_hole s
      end
      else begin
        (* Offer a perk pick before the next hole. *)
        let opts = pick_three_perks s in
        s.mode <- Perk_pick {pp_options = opts; pp_cursor = 0} ;
        s.mode_t <- 0.0
      end

let pick_perk (s : t) (pp : perk_pick_data) =
  let pi = pp.pp_options.(pp.pp_cursor) in
  if pi >= 0 then apply_perk s all_perks.(pi) ;
  begin_run_hole s

(* Yardage per tile for the distance-to-cup HUD readout. *)
let yardage_per_tile = 14.0

(* Distance from ball position to cup, in mock yards. *)
let dist_to_cup_yards (g : game) =
  let cx, cy = g.hole.cup in
  let dx = g.ball.x -. (float_of_int cx +. 0.5) in
  let dy = g.ball.y -. (float_of_int cy +. 0.5) in
  int_of_float (sqrt ((dx *. dx) +. (dy *. dy)) *. yardage_per_tile)

(* ---------- HUD-helper accessors (used by view) ---------- *)

let aim_for_hud (s : t) =
  match s.mode with
  | Aiming a -> Some a.a_aim
  | Powering p -> Some p.aim_angle
  | _ -> None

let club_for_hud (s : t) =
  match s.mode with
  | Aiming a -> Some a.a_game.club
  | Powering p -> Some p.game.club
  | In_flight f -> Some f.f_game.club
  | _ -> None

(* Return the effective display wind: base shot_wind plus active gust delta. *)
let display_wind (g : game) =
  let wx, wy = g.shot_wind in
  if g.gust_remaining > 0.0 then
    let gx, gy = g.gust_delta in
    (wx +. gx, wy +. gy)
  else (wx, wy)

(* True when a gust is currently active. *)
let gust_active (g : game) = g.gust_remaining > 0.0
