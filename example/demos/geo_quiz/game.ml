(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

module Globe = Miaou_widgets_display.Globe_widget
module FB = Miaou_widgets_display.Framebuffer_widget

(* ---------- types ---------- *)

type mode = Menu | Round | Round_end | Game_over

type round_result = {
  city : Cities.city;
  guess_lat : float;
  guess_lon : float;
  distance_km : float;
  distance_score : int;
  time_bonus : int;
  total : int;
  timed_out : bool;
}

type state = {
  mode : mode;
  difficulty : int; (* 1..5 *)
  round_idx : int; (* 0-based, total rounds = num_rounds *)
  num_rounds : int;
  pool : Cities.city array; (* refreshed when difficulty changes *)
  current : Cities.city option;
  cursor_lat : float; (* current crosshair lat *)
  cursor_lon : float; (* current crosshair lon *)
  round_start : float; (* clock.elapsed at round start *)
  round_deadline_s : float; (* seconds *)
  results : round_result list; (* most-recent first *)
  globe : Globe.t;
  map_fb : FB.t;
  map_bg_cache : (bytes * int * int) ref;
      (* Cached pre-rendered (coastline + graticule) at (px_w, px_h). The
       per-frame render copies this and overlays pins, avoiding the cost of
       redrawing 60K coastline lines every tick. *)
  map_render_cache : (string * string) ref;
      (* (key, ansi_output) — re-encoding the framebuffer is the dominant cost
       per frame, so we cache the final ANSI string and only re-render when
       the cache key (cursor / pins / size) changes. *)
  rng : Random.State.t;
  next_page : string option;
}

(* ---------- constants ---------- *)

let num_rounds_default = 10

let round_deadline_default = 30.0

(* ---------- scoring ---------- *)

let max_distance_for_tier tier = if tier <= 3 then 5000.0 else 2500.0

let score_round ~tier ~city ~guess_lat ~guess_lon ~elapsed_in_round ~timed_out =
  let distance_km =
    Globe.haversine_km
      ~lat1:city.Cities.lat
      ~lon1:city.Cities.lon
      ~lat2:guess_lat
      ~lon2:guess_lon
  in
  let max_d = max_distance_for_tier tier in
  let dscore =
    if timed_out then 0
    else max 0 (int_of_float (1000.0 *. (1.0 -. (distance_km /. max_d))))
  in
  let remaining = Float.max 0.0 (round_deadline_default -. elapsed_in_round) in
  let tbonus =
    if timed_out then 0 else min 300 (int_of_float (remaining *. 10.0))
  in
  {
    city;
    guess_lat;
    guess_lon;
    distance_km;
    distance_score = dscore;
    time_bonus = tbonus;
    total = dscore + tbonus;
    timed_out;
  }

let total_score s = List.fold_left (fun acc r -> acc + r.total) 0 s.results

let max_total_score s =
  let per_round = 1000 + 300 in
  s.num_rounds * per_round

(* ---------- state ---------- *)

let pick_city ~rng pool =
  if Array.length pool = 0 then None
  else Some pool.(Random.State.int rng (Array.length pool))

let init () =
  let coast = Lazy.force Coastline.points in
  let globe = Globe.create ~is_land:Landmask.is_land ~coastline:coast () in
  let map_fb = FB.create () in
  let map_bg_cache = ref (Bytes.empty, 0, 0) in
  let map_render_cache = ref ("", "") in
  let rng = Random.State.make_self_init () in
  let difficulty = 1 in
  let pool = Cities.pool ~tier:difficulty in
  {
    mode = Menu;
    difficulty;
    round_idx = 0;
    num_rounds = num_rounds_default;
    pool;
    current = None;
    cursor_lat = 0.0;
    cursor_lon = 0.0;
    round_start = 0.0;
    round_deadline_s = round_deadline_default;
    results = [];
    globe;
    map_fb;
    map_bg_cache;
    map_render_cache;
    rng;
    next_page = None;
  }

let cycle_difficulty s ~delta =
  let d =
    let n = s.difficulty + delta in
    if n < 1 then 1 else if n > 5 then 5 else n
  in
  if d = s.difficulty then s
  else
    let pool = Cities.pool ~tier:d in
    {s with difficulty = d; pool}

let now_elapsed () =
  match Miaou_interfaces.Clock.get () with
  | Some clk -> clk.elapsed ()
  | None -> 0.0

let start_round s =
  match pick_city ~rng:s.rng s.pool with
  | None -> s (* empty pool — should never happen with our blob *)
  | Some city ->
      {
        s with
        mode = Round;
        current = Some city;
        cursor_lat = 0.0;
        cursor_lon = 0.0;
        round_start = now_elapsed ();
      }

let lock_in s ~timed_out =
  match s.current with
  | None -> s
  | Some city ->
      let elapsed_in_round = now_elapsed () -. s.round_start in
      let result =
        score_round
          ~tier:s.difficulty
          ~city
          ~guess_lat:s.cursor_lat
          ~guess_lon:s.cursor_lon
          ~elapsed_in_round
          ~timed_out
      in
      {s with mode = Round_end; results = result :: s.results}

let next_or_finish s =
  let next_idx = s.round_idx + 1 in
  if next_idx >= s.num_rounds then {s with mode = Game_over}
  else start_round {s with round_idx = next_idx}

let reset_to_menu s =
  let s' = init () in
  {
    s' with
    difficulty = s.difficulty;
    rng = s.rng;
    map_fb = s.map_fb;
    map_bg_cache = s.map_bg_cache;
    map_render_cache = s.map_render_cache;
  }

(* Cursor movement on the world map. The map is equirectangular with the
   user-visible width/height; we step in lat/lon directly. *)

let clamp_lat l = Float.max (-89.0) (Float.min 89.0 l)

let wrap_lon l =
  let l = mod_float (l +. 540.0) 360.0 -. 180.0 in
  l

let move_cursor s ~dlat ~dlon =
  {
    s with
    cursor_lat = clamp_lat (s.cursor_lat +. dlat);
    cursor_lon = wrap_lon (s.cursor_lon +. dlon);
  }

(* ---------- timer registration ---------- *)

let register_round_timer ~deadline_s =
  match Miaou_interfaces.Timer.get () with
  | None -> ()
  | Some timer -> timer.set_timeout ~id:"geo_quiz_deadline" deadline_s

let drain_deadline () =
  match Miaou_interfaces.Timer.get () with
  | None -> false
  | Some timer ->
      let fired = timer.drain_fired () in
      List.mem "geo_quiz_deadline" fired

(* Tick the globe rotation in Menu mode. *)
let tick_menu_globe s ~dt = {s with globe = Globe.advance s.globe ~dt}
