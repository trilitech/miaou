(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(** DDA ray casting for MIAOU Crypt. One ray per framebuffer column;
    each ray walks the tile grid until it hits a blocking tile, then
    returns the perpendicular distance, the wall side (N/S vs E/W),
    the texture-x coord on the hit cell, and the world-space hit
    point so [view.ml] can drive subtle brick texturing. *)

type wall_side =
  | NS (* hit a horizontal wall edge — y constant *)
  | EW (* hit a vertical wall edge — x constant *)

type hit = {
  perp_dist : float;
  side : wall_side;
  tex_x : float; (* 0..1 across the wall slice *)
  hit_x : float; (* world-space x of the hit point *)
  hit_y : float; (* world-space y of the hit point *)
  tile : Model.tile;
  map_x : int;
  map_y : int;
}

(* Field of view: 66°. Player.facing is cardinal so the camera
   plane is just facing rotated 90° clockwise, scaled by tan(fov/2). *)
let camera_plane_scale = 0.66

let camera_plane (facing : Model.facing) =
  let fdx = float_of_int facing.dx in
  let fdy = float_of_int facing.dy in
  (* plane = facing rotated +90° in screen coords: (fdy, -fdx) puts
     "left of screen" on the player's left when +y is south. *)
  let pdx = fdy in
  let pdy = -.fdx in
  (pdx *. camera_plane_scale, pdy *. camera_plane_scale)

let max_dda_steps = 32

(* DDA from [(px, py)] in direction [(dx, dy)]; returns [None] if no hit
   within [max_dda_steps] cells (open void), else [Some hit]. *)
let cast_ray (floor : Model.floor) ~px ~py ~dx ~dy =
  let map_x = ref (int_of_float px) in
  let map_y = ref (int_of_float py) in
  let delta_dist_x = if dx = 0.0 then infinity else Float.abs (1.0 /. dx) in
  let delta_dist_y = if dy = 0.0 then infinity else Float.abs (1.0 /. dy) in
  let step_x, side_dist_x_init =
    if dx < 0.0 then (-1, (px -. float_of_int !map_x) *. delta_dist_x)
    else (1, (float_of_int (!map_x + 1) -. px) *. delta_dist_x)
  in
  let step_y, side_dist_y_init =
    if dy < 0.0 then (-1, (py -. float_of_int !map_y) *. delta_dist_y)
    else (1, (float_of_int (!map_y + 1) -. py) *. delta_dist_y)
  in
  let side_dist_x = ref side_dist_x_init in
  let side_dist_y = ref side_dist_y_init in
  let side = ref EW in
  let hit = ref None in
  let steps = ref 0 in
  while !hit = None && !steps < max_dda_steps do
    incr steps ;
    if !side_dist_x < !side_dist_y then begin
      side_dist_x := !side_dist_x +. delta_dist_x ;
      map_x := !map_x + step_x ;
      side := EW
    end
    else begin
      side_dist_y := !side_dist_y +. delta_dist_y ;
      map_y := !map_y + step_y ;
      side := NS
    end ;
    let t = Model.tile_at floor ~x:!map_x ~y:!map_y in
    if Model.is_blocking t then hit := Some t
  done ;
  match !hit with
  | None -> None
  | Some tile ->
      let perp_dist =
        if !side = EW then Float.max 0.001 (!side_dist_x -. delta_dist_x)
        else Float.max 0.001 (!side_dist_y -. delta_dist_y)
      in
      let hit_x = px +. (perp_dist *. dx) in
      let hit_y = py +. (perp_dist *. dy) in
      let wall_x = if !side = EW then hit_y else hit_x in
      let tex_x = wall_x -. Float.floor wall_x in
      Some
        {
          perp_dist;
          side = !side;
          tex_x;
          hit_x;
          hit_y;
          tile;
          map_x = !map_x;
          map_y = !map_y;
        }

(* ---------- column → screen mapping ---------- *)

(* For a column [col] of [n_cols], compute the ray direction. Player
   forward is [(fdx, fdy)], camera plane is [(pdx, pdy)]. The
   resulting unit-ish direction is [(forward + camera_x*plane)] where
   [camera_x] sweeps [-1..1]. *)
let column_ray (player : Model.player) ~col ~n_cols =
  let fdx = float_of_int player.facing.dx in
  let fdy = float_of_int player.facing.dy in
  let pdx, pdy = camera_plane player.facing in
  let camera_x = (2.0 *. float_of_int col /. float_of_int n_cols) -. 1.0 in
  (fdx +. (pdx *. camera_x), fdy +. (pdy *. camera_x))

(* ---------- shading ---------- *)

(* Distance ramp. Brightest at distance 0, near-black at [max_view].
   Posterised to 8 levels for a smooth-ish gradient that still fights
   Octant banding. Wraps a torch boost when the player has a lit
   torch — extends the bright range. *)
let max_view_distance = 12.0

let shade_factor ?(torch_timer = 0.0) ~dist () =
  (* With a lit torch, visibility extends to 16 tiles (up from 12). *)
  let extra = if torch_timer > 0.0 then 4.0 else 0.0 in
  let max_view = max_view_distance +. extra in
  let d = Float.min dist max_view in
  let t = d /. max_view in
  (* 8-stop posterisation. *)
  let step = int_of_float (t *. 8.0) in
  let step = max 0 (min 7 step) in
  let table = [|1.0; 0.85; 0.70; 0.56; 0.43; 0.32; 0.22; 0.13|] in
  table.(step)

(* Side dimming: EW walls are slightly dimmer than NS for cheap fake
   lighting (Wolfenstein convention). 0.85 multiplier. *)
let side_factor = function EW -> 0.82 | NS -> 1.0

(* Subtle "brick" texture: alternate horizontal mortar lines and
   vertical brick joints. Returns a multiplier in [0.78, 1.0]. *)
let texture_factor (hit : hit) =
  let v_in_cell =
    (* Render-y goes from 0 (top of slice) to 1 (bottom); but we want a
       world-anchored band so adjacent columns line up. We use the
       texture x-coord plus the floor() of the world-z (faked from the
       hit y) — reading the hit coords is cleaner. *)
    let v = if hit.side = EW then hit.hit_y else hit.hit_x in
    v -. Float.floor v
  in
  (* Mortar bands at 0..0.06 and 0.50..0.56 (two-row brick course). *)
  let in_mortar_h =
    v_in_cell < 0.06 || (v_in_cell >= 0.50 && v_in_cell < 0.56)
  in
  let in_mortar_v =
    let row = int_of_float (v_in_cell *. 2.0) in
    let offset = if row mod 2 = 0 then 0.0 else 0.50 in
    let tx = hit.tex_x +. offset in
    let tx = tx -. Float.floor tx in
    tx < 0.05 || tx > 0.95
  in
  if in_mortar_h || in_mortar_v then 0.78 else 1.0

(* Posterise a 0..1 multiplier to 6 levels per channel — kills the
   nasty Octant banding on smooth gradients. *)
let posterise mul =
  let levels = 6.0 in
  let q = Float.floor (mul *. levels) /. levels in
  Float.max 0.0 (Float.min 1.0 q)

(* Vertical stripe texture: every 4th x-position (in tile-space) gets a
   15% brightness boost, mimicking stone block seams. *)
let stripe_factor (hit : hit) =
  (* Use the tile-relative x-coord (tex_x * tile_width), quantised to
     integer steps. The stripe repeats every 4 units. *)
  let col_in_tile = int_of_float (hit.tex_x *. 16.0) in
  if col_in_tile mod 4 = 0 then 1.15 else 1.0

(* Per-floor danger tint: floors 5-6 (Lich) get a red shift; floor 7
   (Dragon) gets an amber shift. *)
let floor_tint ~floor_no =
  if floor_no >= 7 then (1.12, 0.95, 0.75) (* amber *)
  else if floor_no >= 5 then (1.10, 0.90, 0.90) (* slight red *)
  else (1.0, 1.0, 1.0)

(* Tile-grid stone pattern: every 3rd tile row (map_y mod 3 = 0) is a
   horizontal mortar course → 15% darker.  Even-column tiles get a +5%
   seam highlight for vertical joints. *)
let tile_grid_factor (hit : hit) =
  let row_mortar = hit.map_y mod 3 = 0 in
  let col_highlight = hit.map_x mod 2 = 0 in
  let f = if row_mortar then 0.85 else 1.0 in
  let f = if col_highlight then f *. 1.05 else f in
  f

(* Compute the final wall pixel colour for a slice column using the
   hit metadata + the per-row position [row_t] in [0,1] (top..bottom).
   [row_t] is used to add subtle vertical banding so the slice doesn't
   look like a flat fill. [floor_no] drives danger tinting. *)
let wall_rgb (hit : hit) ~row_t ~torch_timer ~floor_no =
  let base_r, base_g, base_b =
    match hit.tile with
    | Model.Door {locked = true; _} -> (210, 100, 60) (* warm copper *)
    | Model.Door {locked = false; _} -> (170, 120, 75) (* timber *)
    | _ ->
        (* Floor-themed stone tint: deeper floors trend cooler/redder. *)
        (180, 158, 138)
  in
  let dist_mul = shade_factor ~torch_timer ~dist:hit.perp_dist () in
  let side_mul = side_factor hit.side in
  let tex_mul = texture_factor hit in
  let stripe_mul = stripe_factor hit in
  (* Soft brick courses: every 0.25 of slice height, drop 6%. *)
  let band_mul =
    let v = row_t *. 4.0 in
    let v = v -. Float.floor v in
    if v < 0.04 then 0.86 else 1.0
  in
  (* Torch palette warming: when active, push the colour ramp a touch
     toward orange. *)
  let warm_r, warm_g, warm_b =
    if torch_timer > 0.0 then begin
      let t = Float.min 1.0 (torch_timer /. 30.0) in
      let warm = 0.25 *. t in
      ( int_of_float (float_of_int base_r *. (1.0 +. (warm *. 0.4))),
        int_of_float (float_of_int base_g *. (1.0 -. (warm *. 0.05))),
        int_of_float (float_of_int base_b *. (1.0 -. (warm *. 0.20))) )
    end
    else (base_r, base_g, base_b)
  in
  let tr, tg, tb = floor_tint ~floor_no in
  let grid_mul = tile_grid_factor hit in
  let mul =
    posterise
      (dist_mul *. side_mul *. tex_mul *. band_mul *. stripe_mul *. grid_mul)
  in
  let f c tint =
    max 0 (min 255 (int_of_float (float_of_int c *. mul *. tint)))
  in
  let r, g, b = (f warm_r tr, f warm_g tg, f warm_b tb) in
  (* Stairway glow: stairs columns shine with a warm yellow boost so the
     descent point is immediately obvious in the 3-D view. *)
  match hit.tile with
  | Model.Stairs -> (min 255 (r + 80), min 255 (g + 80), max 0 (b - 10))
  | _ -> (r, g, b)
