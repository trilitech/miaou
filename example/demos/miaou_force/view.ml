(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

module FB = Miaou_widgets_display.Framebuffer_widget
module Caps = Miaou_widgets_display.Terminal_caps
module W = Miaou_widgets_display.Widgets
module Arcade_kit = Demo_shared.Arcade_kit

(* ---------- ANSI / cell helpers ---------- *)

let visible_width s =
  let n = String.length s in
  let i = ref 0 in
  let cells = ref 0 in
  while !i < n do
    let c = Char.code s.[!i] in
    if c = 0x1b && !i + 1 < n && s.[!i + 1] = '[' then begin
      i := !i + 2 ;
      while !i < n && (Char.code s.[!i] < 0x40 || Char.code s.[!i] > 0x7E) do
        incr i
      done ;
      if !i < n then incr i
    end
    else if c < 0x80 then begin
      incr cells ;
      incr i
    end
    else if c < 0xC0 then incr i
    else if c < 0xE0 then begin
      incr cells ;
      i := !i + 2
    end
    else if c < 0xF0 then begin
      incr cells ;
      i := !i + 3
    end
    else begin
      incr cells ;
      i := !i + 4
    end
  done ;
  !cells

(* ---------- pixel helpers ---------- *)

let put_px bytes ~px_w ~px_h ~x ~y ~r ~g ~b =
  if x >= 0 && x < px_w && y >= 0 && y < px_h then begin
    let off = ((y * px_w) + x) * 3 in
    Bytes.set bytes off (Char.chr r) ;
    Bytes.set bytes (off + 1) (Char.chr g) ;
    Bytes.set bytes (off + 2) (Char.chr b)
  end

let fill_rect bytes ~px_w ~px_h ~x ~y ~w ~h ~r ~g ~b =
  for dy = 0 to h - 1 do
    for dx = 0 to w - 1 do
      put_px bytes ~px_w ~px_h ~x:(x + dx) ~y:(y + dy) ~r ~g ~b
    done
  done

let fill_disc bytes ~px_w ~px_h ~cx ~cy ~radius ~r ~g ~b =
  let r2 = radius * radius in
  for dy = -radius to radius do
    for dx = -radius to radius do
      if (dx * dx) + (dy * dy) <= r2 then
        put_px bytes ~px_w ~px_h ~x:(cx + dx) ~y:(cy + dy) ~r ~g ~b
    done
  done

(* ---------- level palette helpers ---------- *)

(* Each level has a different colour scheme for stars, terrain, and tints. *)

type palette_colors = {
  (* Terrain fill colours. *)
  t_r : int;
  t_g : int;
  t_b : int;
  (* Star far layer tint (additive over grey). *)
  s_r_add : int;
  s_g_add : int;
  s_b_add : int;
  (* Sky/void background colour. *)
  bg_r : int;
  bg_g : int;
  bg_b : int;
}

let palette_of_level = function
  | Model.Palette_rocky ->
      {
        t_r = 1;
        t_g = 0;
        t_b = 0;
        (* rocky brown/grey — multiplier fracs *)
        s_r_add = 10;
        s_g_add = 5;
        s_b_add = 0;
        bg_r = 0;
        bg_g = 0;
        bg_b = 0;
      }
  | Model.Palette_asteroid ->
      {
        t_r = 0;
        t_g = 1;
        t_b = 1;
        s_r_add = 0;
        s_g_add = 8;
        s_b_add = 20;
        bg_r = 0;
        bg_g = 3;
        bg_b = 12;
      }
  | Model.Palette_core ->
      {
        t_r = 1;
        t_g = 0;
        t_b = 0;
        s_r_add = 20;
        s_g_add = 0;
        s_b_add = 0;
        bg_r = 10;
        bg_g = 0;
        bg_b = 0;
      }

(* ---------- parallax stars ---------- *)

(* Two layers of stars stored once per (px_w, px_h) seed. We avoid
   per-frame allocation by keying on dimensions; in practice the size
   only changes on resize. *)

type star_field = {
  far : (int * int * int) array;
  (* (x, y, brightness) *)
  near : (int * int * int) array;
}

let star_cache : (int * int, star_field) Hashtbl.t = Hashtbl.create 4

let make_stars ~px_w ~px_h =
  match Hashtbl.find_opt star_cache (px_w, px_h) with
  | Some sf -> sf
  | None ->
      let st = Random.State.make [|0xCAFE; px_w; px_h|] in
      let n_far = max 30 (px_w * px_h / 4000) in
      let n_near = max 12 (px_w * px_h / 9000) in
      let far =
        Array.init n_far (fun _ ->
            let x = Random.State.int st px_w in
            let y = Random.State.int st px_h in
            let b = 70 + Random.State.int st 60 in
            (x, y, b))
      in
      let near =
        Array.init n_near (fun _ ->
            let x = Random.State.int st px_w in
            let y = Random.State.int st px_h in
            let b = 160 + Random.State.int st 70 in
            (x, y, b))
      in
      let sf = {far; near} in
      Hashtbl.add star_cache (px_w, px_h) sf ;
      sf

(* ---------- mid-layer rock formations ---------- *)

(* 10 rock blobs positioned at fixed world offsets and scrolling at 60% of
   world speed. Derived purely from world_x — no per-frame state needed. *)
let draw_rocks bytes ~px_w ~px_h ~world_x ~palette =
  let pal = palette_of_level palette in
  (* Rock colour: dark grey with a hint of the level palette. *)
  let rr = 30 + (pal.t_r * 15) in
  let rg = 25 + (pal.t_g * 15) in
  let rb = 25 + (pal.t_b * 15) in
  (* 10 rocks with evenly distributed world-base positions. *)
  let spacing = 220.0 in
  for i = 0 to 9 do
    let wx_base = float_of_int i *. spacing in
    (* Rock y position: vary by index for a natural look. *)
    let cy_frac =
      match i mod 5 with
      | 0 -> 0.2
      | 1 -> 0.35
      | 2 -> 0.65
      | 3 -> 0.8
      | _ -> 0.5
    in
    let cy = int_of_float (cy_frac *. float_of_int px_h) in
    (* Rock size: alternate between 3 sizes. *)
    let radius = match i mod 3 with 0 -> 5 | 1 -> 4 | _ -> 6 in
    (* Screen x: derived from world position, wrapping around. *)
    let scroll_mid = world_x *. 0.6 in
    let raw_x = wx_base -. scroll_mid in
    (* Wrap into [0, px_w) range using mod_float. *)
    let wrapped =
      let m = mod_float raw_x (float_of_int px_w) in
      if m < 0.0 then m +. float_of_int px_w else m
    in
    let cx = int_of_float wrapped in
    (* Only draw if the disc fits partly on screen. *)
    if cx + radius >= 0 && cx - radius < px_w then
      fill_disc bytes ~px_w ~px_h ~cx ~cy ~radius ~r:rr ~g:rg ~b:rb
  done

let draw_stars bytes ~px_w ~px_h ~world_x ~palette =
  let pal = palette_of_level palette in
  (* Fill background with level-specific void colour. *)
  if pal.bg_r > 0 || pal.bg_g > 0 || pal.bg_b > 0 then begin
    for y = 0 to px_h - 1 do
      for x = 0 to px_w - 1 do
        put_px bytes ~px_w ~px_h ~x ~y ~r:pal.bg_r ~g:pal.bg_g ~b:pal.bg_b
      done
    done
  end ;
  let sf = make_stars ~px_w ~px_h in
  (* Far layer: scrolls slowly. *)
  let scroll_far = int_of_float (world_x *. 0.25) in
  Array.iter
    (fun (x, y, b) ->
      let x' = (((x - scroll_far) mod px_w) + px_w) mod px_w in
      let rb = min 255 (b + pal.s_r_add) in
      let gb = min 255 (b + pal.s_g_add) in
      let bb = min 255 (b + 10 + pal.s_b_add) in
      put_px bytes ~px_w ~px_h ~x:x' ~y ~r:rb ~g:gb ~b:bb)
    sf.far ;
  (* Mid layer: rock blobs scrolling at 60% speed. *)
  draw_rocks bytes ~px_w ~px_h ~world_x ~palette ;
  (* Near layer: scrolls faster, brighter. *)
  let scroll_near = int_of_float (world_x *. 0.7) in
  Array.iter
    (fun (x, y, b) ->
      let x' = (((x - scroll_near) mod px_w) + px_w) mod px_w in
      put_px bytes ~px_w ~px_h ~x:x' ~y ~r:b ~g:b ~b)
    sf.near

(* ---------- terrain band ---------- *)

(* Simple top + bottom rocky strip that scrolls with the world. We sample
   a cheap pseudo-random height function so the band looks organic
   without per-frame allocation. Level 3 uses narrower corridors. *)

let terrain_height ~world_x ~px_w ~level_num =
  let _ = px_w in
  fun screen_x ->
    let wx = float_of_int screen_x +. world_x in
    let h =
      4.0
      +. (2.5 *. sin (wx *. 0.07))
      +. (1.5 *. sin (wx *. 0.21))
      +. (1.0 *. sin (wx *. 0.5))
    in
    (* Level 3: deeper corridors. *)
    let extra = if level_num >= 3 then 4.0 else 0.0 in
    max 2 (int_of_float (h +. extra))

let draw_terrain bytes ~px_w ~px_h ~world_x ~palette ~level_num =
  let pal = palette_of_level palette in
  for x = 0 to px_w - 1 do
    let h_top = terrain_height ~world_x ~px_w ~level_num x in
    let h_bot = terrain_height ~world_x:(world_x +. 137.0) ~px_w ~level_num x in
    for y = 0 to h_top - 1 do
      let shade = 30 + (y * 12) in
      let tr =
        (shade * if pal.t_r > 0 then 1 else 0)
        + (shade / 3 * if pal.t_r = 0 then 1 else 0)
      in
      let tg =
        (shade * if pal.t_g > 0 then 1 else 0)
        + (shade / 3 * if pal.t_g = 0 then 1 else 0)
      in
      let tb =
        (shade * if pal.t_b > 0 then 1 else 0)
        + (shade / 3 * if pal.t_b = 0 then 1 else 0)
      in
      put_px
        bytes
        ~px_w
        ~px_h
        ~x
        ~y
        ~r:(min 255 tr)
        ~g:(min 255 (tg / 2))
        ~b:(min 255 (tb / 3))
    done ;
    for dy = 0 to h_bot - 1 do
      let y = px_h - 1 - dy in
      let shade = 30 + (dy * 12) in
      let tr =
        (shade * if pal.t_r > 0 then 1 else 0)
        + (shade / 3 * if pal.t_r = 0 then 1 else 0)
      in
      let tg =
        (shade * if pal.t_g > 0 then 1 else 0)
        + (shade / 3 * if pal.t_g = 0 then 1 else 0)
      in
      let tb =
        (shade * if pal.t_b > 0 then 1 else 0)
        + (shade / 3 * if pal.t_b = 0 then 1 else 0)
      in
      put_px
        bytes
        ~px_w
        ~px_h
        ~x
        ~y
        ~r:(min 255 tr)
        ~g:(min 255 (tg / 2))
        ~b:(min 255 (tb / 3))
    done
  done

(* ---------- ship sprite ---------- *)

(* A small horizontal arrowhead. Coords are pixel offsets relative to
   the ship's centre (px). *)

let draw_ship bytes ~px_w ~px_h ~cx ~cy ~invuln ~charge ~shield_flash
    ~pickup_flash =
  (* Blink during invuln. *)
  let blink = invuln > 0.0 && int_of_float (invuln *. 12.0) mod 2 = 0 in
  (* Shield flash: ship glows gold when shield is hit. *)
  let sf = shield_flash > 0.0 in
  (* Pickup flash: ship flashes pure white for 0.2s after picking up a power-up. *)
  let pf = pickup_flash > 0.0 in
  if blink && (not sf) && not pf then ()
  else begin
    let r_body = if pf then 255 else if sf then 255 else 200 in
    let g_body = if pf then 255 else if sf then 220 else 230 in
    let b_body = if pf then 255 else if sf then 100 else 255 in
    (* Body: white-blue (or gold when shield flash). *)
    fill_rect
      bytes
      ~px_w
      ~px_h
      ~x:(cx - 3)
      ~y:(cy - 1)
      ~w:6
      ~h:3
      ~r:r_body
      ~g:g_body
      ~b:b_body ;
    (* Nose: cyan triangle pip; brighter as charge builds. *)
    let nose_r =
      if charge > 0.5 then 220 + int_of_float (35.0 *. charge) else 120
    in
    let nose_g = 240 in
    let nose_b = 255 in
    put_px bytes ~px_w ~px_h ~x:(cx + 3) ~y:cy ~r:nose_r ~g:nose_g ~b:nose_b ;
    put_px bytes ~px_w ~px_h ~x:(cx + 4) ~y:cy ~r:nose_r ~g:255 ~b:255 ;
    (* Charge glow: posterised palette around the nose tip. *)
    if charge > 0.25 then begin
      let lvl = charge in
      let gr = 200 + int_of_float (55.0 *. lvl) in
      let gb = 255 in
      put_px bytes ~px_w ~px_h ~x:(cx + 5) ~y:cy ~r:gr ~g:gr ~b:gb ;
      if charge > 0.5 then begin
        put_px bytes ~px_w ~px_h ~x:(cx + 5) ~y:(cy - 1) ~r:gr ~g:200 ~b:gb ;
        put_px bytes ~px_w ~px_h ~x:(cx + 5) ~y:(cy + 1) ~r:gr ~g:200 ~b:gb
      end ;
      if charge > 0.85 then begin
        (* Almost-full charge: bright halo. *)
        put_px bytes ~px_w ~px_h ~x:(cx + 6) ~y:cy ~r:255 ~g:255 ~b:255 ;
        put_px bytes ~px_w ~px_h ~x:(cx + 6) ~y:(cy - 1) ~r:200 ~g:240 ~b:255 ;
        put_px bytes ~px_w ~px_h ~x:(cx + 6) ~y:(cy + 1) ~r:200 ~g:240 ~b:255 ;
        put_px bytes ~px_w ~px_h ~x:(cx + 7) ~y:cy ~r:255 ~g:255 ~b:255
      end
    end ;
    (* Wings *)
    put_px bytes ~px_w ~px_h ~x:(cx - 2) ~y:(cy - 2) ~r:140 ~g:160 ~b:200 ;
    put_px bytes ~px_w ~px_h ~x:(cx - 1) ~y:(cy - 2) ~r:140 ~g:160 ~b:200 ;
    put_px bytes ~px_w ~px_h ~x:(cx - 2) ~y:(cy + 2) ~r:140 ~g:160 ~b:200 ;
    put_px bytes ~px_w ~px_h ~x:(cx - 1) ~y:(cy + 2) ~r:140 ~g:160 ~b:200 ;
    (* Engine plume — flicker *)
    let flick = (cx + cy) land 1 in
    let r = if flick = 0 then 255 else 240 in
    put_px bytes ~px_w ~px_h ~x:(cx - 4) ~y:cy ~r ~g:160 ~b:60 ;
    put_px bytes ~px_w ~px_h ~x:(cx - 5) ~y:cy ~r:200 ~g:80 ~b:30
  end

let draw_force bytes ~px_w ~px_h ~cx ~cy ~detached ~upgraded =
  let ring_r, glow_r = if detached then (200, 240) else (160, 200) in
  (* Upgraded force: magenta core instead of white/purple. *)
  let core_r, core_g, core_b =
    if upgraded then (255, 80, 255) else (255, 255, 255)
  in
  fill_disc bytes ~px_w ~px_h ~cx ~cy ~radius:1 ~r:core_r ~g:core_g ~b:core_b ;
  let ring_g = if upgraded then 80 else 140 in
  let ring_b = if upgraded then 255 else glow_r in
  put_px bytes ~px_w ~px_h ~x:cx ~y:(cy - 2) ~r:ring_r ~g:ring_g ~b:ring_b ;
  put_px bytes ~px_w ~px_h ~x:cx ~y:(cy + 2) ~r:ring_r ~g:ring_g ~b:ring_b ;
  put_px bytes ~px_w ~px_h ~x:(cx - 2) ~y:cy ~r:ring_r ~g:ring_g ~b:ring_b ;
  put_px bytes ~px_w ~px_h ~x:(cx + 2) ~y:cy ~r:ring_r ~g:ring_g ~b:ring_b ;
  (* Wider hitbox indicator when upgraded: extra cardinal points. *)
  if upgraded then begin
    put_px bytes ~px_w ~px_h ~x:cx ~y:(cy - 4) ~r:180 ~g:60 ~b:220 ;
    put_px bytes ~px_w ~px_h ~x:cx ~y:(cy + 4) ~r:180 ~g:60 ~b:220 ;
    put_px bytes ~px_w ~px_h ~x:(cx - 4) ~y:cy ~r:180 ~g:60 ~b:220 ;
    put_px bytes ~px_w ~px_h ~x:(cx + 4) ~y:cy ~r:180 ~g:60 ~b:220
  end ;
  if detached then begin
    (* Trailing sparks. *)
    put_px bytes ~px_w ~px_h ~x:(cx - 3) ~y:(cy - 1) ~r:120 ~g:120 ~b:200 ;
    put_px bytes ~px_w ~px_h ~x:(cx - 3) ~y:(cy + 1) ~r:120 ~g:120 ~b:200
  end

(* ---------- enemies ---------- *)

let draw_enemy bytes ~px_w ~px_h (e : Model.enemy) =
  let cx = int_of_float e.x in
  let cy = int_of_float e.y in
  let flash = e.hit_flash > 0.0 in
  let with_flash r g b = if flash then (255, 240, 240) else (r, g, b) in
  (* Spawn fade-in: skip checkerboard pixels during first 0.3s. *)
  let fading_in = e.age < 0.3 in
  let put_px_raw = put_px in
  let put_px bytes ~px_w ~px_h ~x ~y ~r ~g ~b =
    if fading_in && (x + y) mod 2 = 0 then ()
    else put_px_raw bytes ~px_w ~px_h ~x ~y ~r ~g ~b
  in
  let fill_rect bytes ~px_w ~px_h ~x ~y ~w ~h ~r ~g ~b =
    if fading_in then
      for dy = 0 to h - 1 do
        for dx = 0 to w - 1 do
          put_px bytes ~px_w ~px_h ~x:(x + dx) ~y:(y + dy) ~r ~g ~b
        done
      done
    else fill_rect bytes ~px_w ~px_h ~x ~y ~w ~h ~r ~g ~b
  in
  let fill_disc bytes ~px_w ~px_h ~cx ~cy ~radius ~r ~g ~b =
    if fading_in then begin
      let r2 = radius * radius in
      for dy = -radius to radius do
        for dx = -radius to radius do
          if (dx * dx) + (dy * dy) <= r2 then
            put_px bytes ~px_w ~px_h ~x:(cx + dx) ~y:(cy + dy) ~r ~g ~b
        done
      done
    end
    else fill_disc bytes ~px_w ~px_h ~cx ~cy ~radius ~r ~g ~b
  in
  match e.kind with
  | Model.Grunt ->
      let r, g, b = with_flash 220 90 90 in
      fill_rect bytes ~px_w ~px_h ~x:(cx - 2) ~y:(cy - 1) ~w:4 ~h:3 ~r ~g ~b ;
      put_px bytes ~px_w ~px_h ~x:(cx - 3) ~y:cy ~r:255 ~g:140 ~b:90
  | Model.Diver ->
      let r, g, b = with_flash 230 170 60 in
      fill_rect bytes ~px_w ~px_h ~x:(cx - 2) ~y:(cy - 1) ~w:4 ~h:2 ~r ~g ~b ;
      put_px bytes ~px_w ~px_h ~x:cx ~y:(cy + 1) ~r:255 ~g:200 ~b:80
  | Model.Turret ->
      let r, g, b = with_flash 160 200 100 in
      fill_disc bytes ~px_w ~px_h ~cx ~cy ~radius:3 ~r ~g ~b ;
      (* Barrel points toward the player based on face_dir (updated each tick). *)
      let bx, by =
        match e.face_dir with
        | 0 -> (cx + 4, cy) (* right *)
        | 1 -> (cx, cy - 4) (* up *)
        | 3 -> (cx, cy + 4) (* down *)
        | _ -> (cx - 4, cy)
        (* left (default) *)
      in
      put_px bytes ~px_w ~px_h ~x:bx ~y:by ~r:80 ~g:255 ~b:120 ;
      put_px bytes ~px_w ~px_h ~x:cx ~y:cy ~r:255 ~g:255 ~b:80
  | Model.Strafer ->
      (* Sleek diamond, magenta. *)
      let r, g, b = with_flash 220 60 200 in
      put_px bytes ~px_w ~px_h ~x:cx ~y:(cy - 2) ~r ~g ~b ;
      fill_rect bytes ~px_w ~px_h ~x:(cx - 1) ~y:(cy - 1) ~w:3 ~h:1 ~r ~g ~b ;
      fill_rect bytes ~px_w ~px_h ~x:(cx - 2) ~y:cy ~w:5 ~h:1 ~r ~g ~b ;
      fill_rect bytes ~px_w ~px_h ~x:(cx - 1) ~y:(cy + 1) ~w:3 ~h:1 ~r ~g ~b ;
      put_px bytes ~px_w ~px_h ~x:cx ~y:(cy + 2) ~r ~g ~b ;
      (* Glowing trail. *)
      put_px bytes ~px_w ~px_h ~x:(cx + 3) ~y:cy ~r:255 ~g:180 ~b:220
  | Model.Shielded ->
      (* Heavy purple core with a cyan shield ring when shield > 0. *)
      let r, g, b = with_flash 100 60 160 in
      fill_disc bytes ~px_w ~px_h ~cx ~cy ~radius:3 ~r ~g ~b ;
      fill_disc bytes ~px_w ~px_h ~cx ~cy ~radius:1 ~r:200 ~g:160 ~b:255 ;
      if e.shield > 0 then begin
        (* Wide pulsing ring at radius ~6, driven by phase for frequency. *)
        let pulse_phase = e.phase *. 5.0 in
        let pulse_amp = 0.5 +. (0.5 *. sin pulse_phase) in
        let rr = int_of_float (60.0 +. (180.0 *. pulse_amp)) in
        let gg = int_of_float (160.0 +. (95.0 *. pulse_amp)) in
        let bb = 255 in
        (* 8-point ring at approx radius 6 *)
        put_px bytes ~px_w ~px_h ~x:(cx + 6) ~y:cy ~r:rr ~g:gg ~b:bb ;
        put_px bytes ~px_w ~px_h ~x:(cx - 6) ~y:cy ~r:rr ~g:gg ~b:bb ;
        put_px bytes ~px_w ~px_h ~x:cx ~y:(cy + 6) ~r:rr ~g:gg ~b:bb ;
        put_px bytes ~px_w ~px_h ~x:cx ~y:(cy - 6) ~r:rr ~g:gg ~b:bb ;
        (* Diagonal points at approx 45° (4, 4 ≈ radius 5.7) *)
        let d = 4 in
        put_px bytes ~px_w ~px_h ~x:(cx + d) ~y:(cy + d) ~r:rr ~g:gg ~b:bb ;
        put_px bytes ~px_w ~px_h ~x:(cx + d) ~y:(cy - d) ~r:rr ~g:gg ~b:bb ;
        put_px bytes ~px_w ~px_h ~x:(cx - d) ~y:(cy + d) ~r:rr ~g:gg ~b:bb ;
        put_px bytes ~px_w ~px_h ~x:(cx - d) ~y:(cy - d) ~r:rr ~g:gg ~b:bb
      end
  | Model.Mine ->
      (* Spiked round bomb, fuse glow when triggered. *)
      let warm = e.mine_fuse > 0.0 in
      let r, g, b = if warm then (255, 200, 80) else with_flash 170 130 60 in
      fill_disc bytes ~px_w ~px_h ~cx ~cy ~radius:2 ~r ~g ~b ;
      put_px bytes ~px_w ~px_h ~x:(cx - 3) ~y:cy ~r ~g ~b ;
      put_px bytes ~px_w ~px_h ~x:(cx + 3) ~y:cy ~r ~g ~b ;
      put_px bytes ~px_w ~px_h ~x:cx ~y:(cy - 3) ~r ~g ~b ;
      put_px bytes ~px_w ~px_h ~x:cx ~y:(cy + 3) ~r ~g ~b ;
      if warm then put_px bytes ~px_w ~px_h ~x:cx ~y:cy ~r:255 ~g:255 ~b:200
  | Model.Splitter ->
      (* Orange-yellow triangle — suggests fragmentation. *)
      let r, g, b = with_flash 255 160 40 in
      put_px bytes ~px_w ~px_h ~x:cx ~y:(cy - 2) ~r ~g ~b ;
      put_px bytes ~px_w ~px_h ~x:(cx - 1) ~y:(cy - 1) ~r ~g ~b ;
      put_px bytes ~px_w ~px_h ~x:(cx + 1) ~y:(cy - 1) ~r ~g ~b ;
      fill_rect bytes ~px_w ~px_h ~x:(cx - 2) ~y:cy ~w:5 ~h:1 ~r ~g ~b ;
      put_px bytes ~px_w ~px_h ~x:cx ~y:(cy + 1) ~r:255 ~g:200 ~b:80 ;
      (* Crack lines suggesting imminent split. *)
      put_px bytes ~px_w ~px_h ~x:(cx - 1) ~y:cy ~r:200 ~g:100 ~b:20 ;
      put_px bytes ~px_w ~px_h ~x:(cx + 1) ~y:cy ~r:200 ~g:100 ~b:20
  | Model.Laser_emitter ->
      (* Teal-cyan angular turret that glows when charging. *)
      let charging = e.laser_charge > 0.0 in
      let firing = e.laser_fire_t > 0.0 in
      let r, g, b =
        if firing then (255, 60, 60)
        else if charging then
          let p = e.laser_charge /. 1.5 in
          ( int_of_float (80.0 +. (p *. 120.0)),
            int_of_float (200.0 +. (p *. 55.0)),
            int_of_float (200.0 +. (p *. 55.0)) )
        else with_flash 60 180 180
      in
      fill_disc bytes ~px_w ~px_h ~cx ~cy ~radius:4 ~r ~g ~b ;
      fill_disc
        bytes
        ~px_w
        ~px_h
        ~cx:(cx - 2)
        ~cy
        ~radius:2
        ~r:(r / 2)
        ~g:255
        ~b:255 ;
      (* Barrel pointing left. *)
      put_px bytes ~px_w ~px_h ~x:(cx - 5) ~y:cy ~r:120 ~g:255 ~b:255 ;
      put_px bytes ~px_w ~px_h ~x:(cx - 6) ~y:cy ~r:80 ~g:200 ~b:200 ;
      (* Charge ring. *)
      if charging then begin
        let puls = int_of_float (e.phase *. 12.0) land 1 = 0 in
        let cr = if puls then 100 else 40 in
        let cg = if puls then 255 else 180 in
        let cb = if puls then 255 else 200 in
        put_px bytes ~px_w ~px_h ~x:cx ~y:(cy - 5) ~r:cr ~g:cg ~b:cb ;
        put_px bytes ~px_w ~px_h ~x:cx ~y:(cy + 5) ~r:cr ~g:cg ~b:cb ;
        put_px bytes ~px_w ~px_h ~x:(cx + 5) ~y:cy ~r:cr ~g:cg ~b:cb ;
        put_px bytes ~px_w ~px_h ~x:(cx - 5) ~y:(cy - 1) ~r:cr ~g:cg ~b:cb ;
        put_px bytes ~px_w ~px_h ~x:(cx - 5) ~y:(cy + 1) ~r:cr ~g:cg ~b:cb
      end ;
      (* Firing flash: bright red beam origin. *)
      if firing then begin
        fill_rect
          bytes
          ~px_w
          ~px_h
          ~x:(cx - 8)
          ~y:(cy - 1)
          ~w:3
          ~h:3
          ~r:255
          ~g:80
          ~b:80 ;
        put_px bytes ~px_w ~px_h ~x:(cx - 10) ~y:cy ~r:255 ~g:200 ~b:200
      end ;
      (* Charge telegraph: dotted red line from emitter to right edge when
         charging, so the player sees the threat axis clearly. *)
      if charging then begin
        let x = ref (cx + 6) in
        while !x < px_w do
          put_px_raw bytes ~px_w ~px_h ~x:!x ~y:cy ~r:200 ~g:30 ~b:30 ;
          x := !x + 4
        done
      end
  | Model.Boomerang ->
      (* Amber crescent/arc shape — 3×5 footprint. *)
      let r, g, b = with_flash 255 160 40 in
      (* Arc: top curve *)
      put_px bytes ~px_w ~px_h ~x:(cx - 1) ~y:(cy - 2) ~r ~g ~b ;
      put_px bytes ~px_w ~px_h ~x:cx ~y:(cy - 2) ~r ~g ~b ;
      put_px bytes ~px_w ~px_h ~x:(cx + 1) ~y:(cy - 2) ~r ~g ~b ;
      (* Mid spans *)
      put_px bytes ~px_w ~px_h ~x:(cx - 2) ~y:(cy - 1) ~r ~g ~b ;
      put_px bytes ~px_w ~px_h ~x:(cx + 2) ~y:(cy - 1) ~r ~g ~b ;
      (* Center *)
      put_px bytes ~px_w ~px_h ~x:(cx - 2) ~y:cy ~r ~g ~b ;
      put_px bytes ~px_w ~px_h ~x:(cx + 2) ~y:cy ~r ~g ~b ;
      (* Bottom tips *)
      put_px bytes ~px_w ~px_h ~x:(cx - 1) ~y:(cy + 1) ~r ~g ~b ;
      put_px bytes ~px_w ~px_h ~x:(cx + 1) ~y:(cy + 1) ~r ~g ~b ;
      (* Bright amber core glow *)
      put_px bytes ~px_w ~px_h ~x:cx ~y:cy ~r:255 ~g:220 ~b:120
  | Model.Carrier ->
      (* Large rectangular carrier ship, dark steel with pulsing cyan trim. *)
      let flash = e.hit_flash > 0.0 in
      let with_flash r g b = if flash then (255, 240, 240) else (r, g, b) in
      let r, g, b = with_flash 80 80 100 in
      (* Main hull: 12×8 *)
      fill_rect bytes ~px_w ~px_h ~x:(cx - 6) ~y:(cy - 4) ~w:12 ~h:8 ~r ~g ~b ;
      (* Hangar bay notches on the right side — two dark recesses. *)
      fill_rect
        bytes
        ~px_w
        ~px_h
        ~x:(cx + 4)
        ~y:(cy - 3)
        ~w:3
        ~h:2
        ~r:20
        ~g:20
        ~b:30 ;
      fill_rect
        bytes
        ~px_w
        ~px_h
        ~x:(cx + 4)
        ~y:(cy + 1)
        ~w:3
        ~h:2
        ~r:20
        ~g:20
        ~b:30 ;
      (* Pulsing cyan trim on edges — pulse from mode_t-equivalent (phase). *)
      let pulse_amp = 0.5 +. (0.5 *. sin (e.phase *. 4.0)) in
      let cr = int_of_float (40.0 +. (80.0 *. pulse_amp)) in
      let cg = int_of_float (160.0 +. (95.0 *. pulse_amp)) in
      let cb = int_of_float (180.0 +. (75.0 *. pulse_amp)) in
      (* Top edge *)
      fill_rect
        bytes
        ~px_w
        ~px_h
        ~x:(cx - 6)
        ~y:(cy - 4)
        ~w:12
        ~h:1
        ~r:cr
        ~g:cg
        ~b:cb ;
      (* Bottom edge *)
      fill_rect
        bytes
        ~px_w
        ~px_h
        ~x:(cx - 6)
        ~y:(cy + 3)
        ~w:12
        ~h:1
        ~r:cr
        ~g:cg
        ~b:cb ;
      (* Left edge *)
      fill_rect
        bytes
        ~px_w
        ~px_h
        ~x:(cx - 6)
        ~y:(cy - 4)
        ~w:1
        ~h:8
        ~r:cr
        ~g:cg
        ~b:cb ;
      (* Engine glow on back (right side since moving left). *)
      put_px bytes ~px_w ~px_h ~x:(cx + 7) ~y:(cy - 1) ~r:255 ~g:160 ~b:60 ;
      put_px bytes ~px_w ~px_h ~x:(cx + 7) ~y:cy ~r:255 ~g:120 ~b:40 ;
      put_px bytes ~px_w ~px_h ~x:(cx + 7) ~y:(cy + 1) ~r:255 ~g:160 ~b:60 ;
      put_px bytes ~px_w ~px_h ~x:(cx + 8) ~y:cy ~r:200 ~g:80 ~b:20
  | Model.Boss ->
      (* Palette shifts per phase. *)
      let core_r, core_g, core_b, glow_r, glow_g, glow_b =
        match e.boss_phase with
        | 2 -> (180, 60, 180, 255, 80, 255)
        | 3 -> (200, 30, 30, 255, 200, 60)
        | _ -> (160, 50, 60, 255, 120, 60)
      in
      let core_r, core_g, core_b = with_flash core_r core_g core_b in
      fill_disc
        bytes
        ~px_w
        ~px_h
        ~cx
        ~cy
        ~radius:8
        ~r:core_r
        ~g:core_g
        ~b:core_b ;
      fill_disc
        bytes
        ~px_w
        ~px_h
        ~cx:(cx - 4)
        ~cy
        ~radius:3
        ~r:glow_r
        ~g:glow_g
        ~b:glow_b ;
      fill_disc bytes ~px_w ~px_h ~cx ~cy ~radius:2 ~r:255 ~g:230 ~b:80 ;
      (* Phase indicator: little pips around the rim. *)
      for i = 0 to e.boss_phase - 1 do
        let a = Float.pi /. 4.0 *. float_of_int i in
        let px = cx + int_of_float (10.0 *. cos a) in
        let py = cy + int_of_float (10.0 *. sin a) in
        put_px bytes ~px_w ~px_h ~x:px ~y:py ~r:255 ~g:255 ~b:255
      done

(* ---------- pickups ---------- *)

(* Colour per pickup type: missile=red, speed=cyan, force=magenta, shield=gold,
   speed-burst=bright cyan/white spark. *)
let pickup_color = function
  | Model.Power_up_speed -> (80, 220, 255)
  | Model.Power_up_force_repair -> (255, 200, 80)
  | Model.Power_up_missile -> (255, 60, 60)
  | Model.Power_up_force_upgrade -> (255, 60, 255)
  | Model.Power_up_shield -> (255, 200, 40)
  | Model.Power_up_speed_burst -> (60, 255, 255)

let draw_pickup bytes ~px_w ~px_h ~world_t (pe : Model.pickup_entity) =
  let cx = int_of_float pe.px in
  let cy = int_of_float pe.py in
  let r, g, b = pickup_color pe.p_kind in
  (* Speed-burst has a special spark look: elongated diagonal sparks. *)
  if pe.p_kind = Model.Power_up_speed_burst then begin
    (* Bright cyan core. *)
    fill_disc bytes ~px_w ~px_h ~cx ~cy ~radius:1 ~r:255 ~g:255 ~b:255 ;
    (* Diagonal spark arms. *)
    let pulse = int_of_float (world_t *. 8.0) land 1 = 0 in
    let sr = if pulse then 60 else 30 in
    let sg = if pulse then 255 else 200 in
    let sb = if pulse then 255 else 220 in
    put_px bytes ~px_w ~px_h ~x:(cx - 3) ~y:(cy - 3) ~r:sr ~g:sg ~b:sb ;
    put_px bytes ~px_w ~px_h ~x:(cx + 3) ~y:(cy - 3) ~r:sr ~g:sg ~b:sb ;
    put_px bytes ~px_w ~px_h ~x:(cx - 3) ~y:(cy + 3) ~r:sr ~g:sg ~b:sb ;
    put_px bytes ~px_w ~px_h ~x:(cx + 3) ~y:(cy + 3) ~r:sr ~g:sg ~b:sb ;
    (* Cardinal extension. *)
    put_px bytes ~px_w ~px_h ~x:cx ~y:(cy - 4) ~r ~g ~b ;
    put_px bytes ~px_w ~px_h ~x:cx ~y:(cy + 4) ~r ~g ~b ;
    put_px bytes ~px_w ~px_h ~x:(cx - 5) ~y:cy ~r ~g ~b ;
    put_px bytes ~px_w ~px_h ~x:(cx + 5) ~y:cy ~r ~g ~b
  end
  else begin
    (* Outer glow ring — pulses with time. *)
    let pulse = int_of_float (world_t *. 6.0) land 1 = 0 in
    let gr = if pulse then r else r / 2 in
    let gg = if pulse then g else g / 2 in
    let gb_ = if pulse then b else b / 2 in
    fill_disc bytes ~px_w ~px_h ~cx ~cy ~radius:3 ~r:gr ~g:gg ~b:gb_ ;
    (* Bright centre core. *)
    fill_disc bytes ~px_w ~px_h ~cx ~cy ~radius:1 ~r:255 ~g:255 ~b:255 ;
    (* Cardinal sparkles. *)
    put_px bytes ~px_w ~px_h ~x:cx ~y:(cy - 4) ~r ~g ~b ;
    put_px bytes ~px_w ~px_h ~x:cx ~y:(cy + 4) ~r ~g ~b ;
    put_px bytes ~px_w ~px_h ~x:(cx - 4) ~y:cy ~r ~g ~b ;
    put_px bytes ~px_w ~px_h ~x:(cx + 4) ~y:cy ~r ~g ~b
  end

let draw_bullet ~ours bytes ~px_w ~px_h (b : Model.bullet) =
  let cx = int_of_float b.bx in
  let cy = int_of_float b.by in
  match b.b_kind with
  | Model.Bullet_beam ->
      (* Charge beam glow: 5-row strip centred on cy.
         Row offsets ±2 = dim, ±1 = mid, 0 = bright cyan core. *)
      (* Outer glow rows ±2: very dim cyan *)
      fill_rect
        bytes
        ~px_w
        ~px_h
        ~x:(cx - 4)
        ~y:(cy - 2)
        ~w:9
        ~h:1
        ~r:0
        ~g:120
        ~b:160 ;
      fill_rect
        bytes
        ~px_w
        ~px_h
        ~x:(cx - 4)
        ~y:(cy + 2)
        ~w:9
        ~h:1
        ~r:0
        ~g:120
        ~b:160 ;
      (* Mid glow rows ±1: medium cyan *)
      fill_rect
        bytes
        ~px_w
        ~px_h
        ~x:(cx - 4)
        ~y:(cy - 1)
        ~w:9
        ~h:1
        ~r:0
        ~g:160
        ~b:200 ;
      fill_rect
        bytes
        ~px_w
        ~px_h
        ~x:(cx - 4)
        ~y:(cy + 1)
        ~w:9
        ~h:1
        ~r:0
        ~g:160
        ~b:200 ;
      (* Core row: bright cyan/white *)
      fill_rect
        bytes
        ~px_w
        ~px_h
        ~x:(cx - 4)
        ~y:cy
        ~w:9
        ~h:1
        ~r:60
        ~g:220
        ~b:255 ;
      (* Bright centre pixels *)
      put_px bytes ~px_w ~px_h ~x:cx ~y:cy ~r:255 ~g:255 ~b:255 ;
      put_px bytes ~px_w ~px_h ~x:(cx + 1) ~y:cy ~r:255 ~g:255 ~b:255 ;
      put_px bytes ~px_w ~px_h ~x:(cx - 1) ~y:cy ~r:200 ~g:245 ~b:255
  | Model.Bullet_homing ->
      (* Pinkish pulsing pod. *)
      put_px bytes ~px_w ~px_h ~x:cx ~y:cy ~r:255 ~g:120 ~b:200 ;
      put_px bytes ~px_w ~px_h ~x:(cx - 1) ~y:cy ~r:200 ~g:60 ~b:160 ;
      put_px bytes ~px_w ~px_h ~x:(cx + 1) ~y:cy ~r:255 ~g:200 ~b:255 ;
      put_px bytes ~px_w ~px_h ~x:cx ~y:(cy - 1) ~r:255 ~g:160 ~b:220 ;
      put_px bytes ~px_w ~px_h ~x:cx ~y:(cy + 1) ~r:255 ~g:160 ~b:220
  | Model.Bullet_missile ->
      (* Red diagonal missile with a small trail. *)
      put_px bytes ~px_w ~px_h ~x:cx ~y:cy ~r:255 ~g:60 ~b:60 ;
      put_px bytes ~px_w ~px_h ~x:(cx - 1) ~y:cy ~r:200 ~g:40 ~b:40 ;
      put_px bytes ~px_w ~px_h ~x:cx ~y:(cy - 1) ~r:255 ~g:120 ~b:80 ;
      put_px bytes ~px_w ~px_h ~x:cx ~y:(cy + 1) ~r:255 ~g:120 ~b:80 ;
      (* Engine glow. *)
      put_px bytes ~px_w ~px_h ~x:(cx - 2) ~y:cy ~r:200 ~g:100 ~b:40
  | Model.Bullet_laser ->
      (* Wide horizontal red laser segment — 3 px tall. *)
      fill_rect
        bytes
        ~px_w
        ~px_h
        ~x:(cx - 1)
        ~y:(cy - 1)
        ~w:4
        ~h:3
        ~r:255
        ~g:60
        ~b:60 ;
      put_px bytes ~px_w ~px_h ~x:cx ~y:cy ~r:255 ~g:200 ~b:200 ;
      put_px bytes ~px_w ~px_h ~x:(cx + 1) ~y:cy ~r:255 ~g:255 ~b:255
  | Model.Bullet_normal ->
      if ours then begin
        put_px bytes ~px_w ~px_h ~x:cx ~y:cy ~r:255 ~g:255 ~b:255 ;
        put_px bytes ~px_w ~px_h ~x:(cx - 1) ~y:cy ~r:200 ~g:240 ~b:255 ;
        put_px bytes ~px_w ~px_h ~x:(cx - 2) ~y:cy ~r:80 ~g:160 ~b:255
      end
      else begin
        put_px bytes ~px_w ~px_h ~x:cx ~y:cy ~r:255 ~g:160 ~b:80 ;
        put_px bytes ~px_w ~px_h ~x:(cx - 1) ~y:cy ~r:255 ~g:80 ~b:60
      end

(* Tiny 3×5 pixel digit font for score popups. Each digit is a list of
   (dx, dy) offsets — origin is top-left. *)

let digit_pixels = function
  | '0' ->
      [
        (0, 0);
        (1, 0);
        (2, 0);
        (0, 1);
        (2, 1);
        (0, 2);
        (2, 2);
        (0, 3);
        (2, 3);
        (0, 4);
        (1, 4);
        (2, 4);
      ]
  | '1' -> [(1, 0); (0, 1); (1, 1); (1, 2); (1, 3); (0, 4); (1, 4); (2, 4)]
  | '2' ->
      [
        (0, 0);
        (1, 0);
        (2, 0);
        (2, 1);
        (0, 2);
        (1, 2);
        (2, 2);
        (0, 3);
        (0, 4);
        (1, 4);
        (2, 4);
      ]
  | '3' ->
      [
        (0, 0);
        (1, 0);
        (2, 0);
        (2, 1);
        (1, 2);
        (2, 2);
        (2, 3);
        (0, 4);
        (1, 4);
        (2, 4);
      ]
  | '4' ->
      [(0, 0); (2, 0); (0, 1); (2, 1); (0, 2); (1, 2); (2, 2); (2, 3); (2, 4)]
  | '5' ->
      [
        (0, 0);
        (1, 0);
        (2, 0);
        (0, 1);
        (0, 2);
        (1, 2);
        (2, 2);
        (2, 3);
        (0, 4);
        (1, 4);
        (2, 4);
      ]
  | '6' ->
      [
        (0, 0);
        (1, 0);
        (2, 0);
        (0, 1);
        (0, 2);
        (1, 2);
        (2, 2);
        (0, 3);
        (2, 3);
        (0, 4);
        (1, 4);
        (2, 4);
      ]
  | '7' -> [(0, 0); (1, 0); (2, 0); (2, 1); (2, 2); (1, 3); (1, 4)]
  | '8' ->
      [
        (0, 0);
        (1, 0);
        (2, 0);
        (0, 1);
        (2, 1);
        (0, 2);
        (1, 2);
        (2, 2);
        (0, 3);
        (2, 3);
        (0, 4);
        (1, 4);
        (2, 4);
      ]
  | '9' ->
      [
        (0, 0);
        (1, 0);
        (2, 0);
        (0, 1);
        (2, 1);
        (0, 2);
        (1, 2);
        (2, 2);
        (2, 3);
        (0, 4);
        (1, 4);
        (2, 4);
      ]
  | '+' -> [(1, 0); (1, 1); (0, 2); (1, 2); (2, 2); (1, 3); (1, 4)]
  | 'S' ->
      [
        (0, 0);
        (1, 0);
        (2, 0);
        (0, 1);
        (0, 2);
        (1, 2);
        (2, 2);
        (2, 3);
        (0, 4);
        (1, 4);
        (2, 4);
      ]
  | 'P' ->
      [
        (0, 0);
        (1, 0);
        (2, 0);
        (0, 1);
        (2, 1);
        (0, 2);
        (1, 2);
        (2, 2);
        (0, 3);
        (0, 4);
      ]
  | 'D' ->
      [
        (0, 0);
        (1, 0);
        (0, 1);
        (2, 1);
        (0, 2);
        (2, 2);
        (0, 3);
        (2, 3);
        (0, 4);
        (1, 4);
      ]
  | 'F' -> [(0, 0); (1, 0); (2, 0); (0, 1); (0, 2); (1, 2); (0, 3); (0, 4)]
  | 'M' ->
      [
        (0, 0);
        (2, 0);
        (0, 1);
        (1, 1);
        (2, 1);
        (0, 2);
        (2, 2);
        (0, 3);
        (2, 3);
        (0, 4);
        (2, 4);
      ]
  | 'L' -> [(0, 0); (0, 1); (0, 2); (0, 3); (0, 4); (1, 4); (2, 4)]
  | 'H' ->
      [
        (0, 0);
        (2, 0);
        (0, 1);
        (2, 1);
        (0, 2);
        (1, 2);
        (2, 2);
        (0, 3);
        (2, 3);
        (0, 4);
        (2, 4);
      ]
  | 'B' ->
      [
        (0, 0);
        (1, 0);
        (0, 1);
        (2, 1);
        (0, 2);
        (1, 2);
        (0, 3);
        (2, 3);
        (0, 4);
        (1, 4);
      ]
  | 'O' ->
      [
        (0, 0);
        (1, 0);
        (2, 0);
        (0, 1);
        (2, 1);
        (0, 2);
        (2, 2);
        (0, 3);
        (2, 3);
        (0, 4);
        (1, 4);
        (2, 4);
      ]
  | 'C' ->
      [(0, 0); (1, 0); (2, 0); (0, 1); (0, 2); (0, 3); (0, 4); (1, 4); (2, 4)]
  | 'E' ->
      [
        (0, 0);
        (1, 0);
        (2, 0);
        (0, 1);
        (0, 2);
        (1, 2);
        (2, 2);
        (0, 3);
        (0, 4);
        (1, 4);
        (2, 4);
      ]
  | 'A' ->
      [
        (1, 0);
        (0, 1);
        (2, 1);
        (0, 2);
        (1, 2);
        (2, 2);
        (0, 3);
        (2, 3);
        (0, 4);
        (2, 4);
      ]
  | 'R' ->
      [
        (0, 0);
        (1, 0);
        (0, 1);
        (2, 1);
        (0, 2);
        (1, 2);
        (0, 3);
        (2, 3);
        (0, 4);
        (2, 4);
      ]
  | 'V' ->
      [(0, 0); (2, 0); (0, 1); (2, 1); (0, 2); (2, 2); (0, 3); (2, 3); (1, 4)]
  | 'N' ->
      [
        (0, 0);
        (2, 0);
        (0, 1);
        (1, 1);
        (2, 1);
        (0, 2);
        (2, 2);
        (0, 3);
        (2, 3);
        (0, 4);
        (2, 4);
      ]
  | 'I' ->
      [(0, 0); (1, 0); (2, 0); (1, 1); (1, 2); (1, 3); (0, 4); (1, 4); (2, 4)]
  | 'T' -> [(0, 0); (1, 0); (2, 0); (1, 1); (1, 2); (1, 3); (1, 4)]
  | '!' -> [(1, 0); (1, 1); (1, 2); (1, 4)]
  | '*' ->
      [(1, 0); (0, 1); (1, 1); (2, 1); (1, 2); (0, 3); (1, 3); (2, 3); (1, 4)]
  | 'X' ->
      [(0, 0); (2, 0); (0, 1); (2, 1); (1, 2); (0, 3); (2, 3); (0, 4); (2, 4)]
  | 'K' ->
      [
        (0, 0);
        (2, 0);
        (0, 1);
        (1, 1);
        (0, 2);
        (1, 2);
        (0, 3);
        (1, 3);
        (0, 4);
        (2, 4);
      ]
  | 'W' ->
      [
        (0, 0);
        (2, 0);
        (0, 1);
        (2, 1);
        (0, 2);
        (2, 2);
        (0, 3);
        (1, 3);
        (2, 3);
        (0, 4);
        (2, 4);
      ]
  | ' ' -> []
  | _ -> []

let draw_text_pixels bytes ~px_w ~px_h ~x ~y ~text ~r ~g ~b =
  let cur_x = ref x in
  String.iter
    (fun c ->
      List.iter
        (fun (dx, dy) ->
          put_px bytes ~px_w ~px_h ~x:(!cur_x + dx) ~y:(y + dy) ~r ~g ~b)
        (digit_pixels c) ;
      cur_x := !cur_x + 4)
    text

let draw_popups bytes ~px_w ~px_h (s : Model.t) =
  Array.iter
    (fun (p : Model.score_popup) ->
      if p.sp_alive then begin
        (* Bright while young, fade as life drops. *)
        let life01 =
          if p.sp_life0 > 0.0 then p.sp_life /. p.sp_life0 else 0.0
        in
        let bright = int_of_float (160.0 +. (95.0 *. life01)) in
        draw_text_pixels
          bytes
          ~px_w
          ~px_h
          ~x:(int_of_float p.sp_x - 4)
          ~y:(int_of_float p.sp_y - 2)
          ~text:p.sp_text
          ~r:255
          ~g:bright
          ~b:120
      end)
    s.popups

let draw_particles bytes ~px_w ~px_h (s : Model.t) =
  Arcade_kit.Particles.iter s.particles ~f:(fun ~x ~y ~life01 ~hue:_ ->
      let r, g, b =
        Arcade_kit.Hue.rgb Arcade_kit.Hue.lava ~life01:(1.0 -. life01)
      in
      let _ = life01 in
      put_px bytes ~px_w ~px_h ~x:(int_of_float x) ~y:(int_of_float y) ~r ~g ~b)

(* ---------- boss health bar ---------- *)

let draw_boss_health_bar bytes ~px_w ~px_h (s : Model.t) =
  (* Find the live boss enemy. *)
  let boss_opt =
    let found = ref None in
    Array.iter
      (fun (e : Model.enemy) ->
        if e.alive && e.kind = Model.Boss then found := Some e)
      s.enemies ;
    !found
  in
  match boss_opt with
  | None -> ()
  | Some boss ->
      let bar_w = px_w * 6 / 10 in
      (* 60% of frame width *)
      let bar_x = (px_w - bar_w) / 2 in
      let bar_y = px_h - 8 in
      let bar_h = 4 in
      let hp_frac =
        if s.boss_hp_max > 0 then
          float_of_int (max 0 boss.hp) /. float_of_int s.boss_hp_max
        else 0.0
      in
      let fill_w = int_of_float (float_of_int bar_w *. hp_frac) in
      (* Flash white on boss hit — overrides colour. *)
      let flashing = boss.hit_flash > 0.0 in
      (* Label "BOSS" above bar. *)
      draw_text_pixels
        bytes
        ~px_w
        ~px_h
        ~x:(bar_x + (bar_w / 2) - 8)
        ~y:(bar_y - 7)
        ~text:"BOSS"
        ~r:255
        ~g:255
        ~b:255 ;
      (* White border around bar. *)
      fill_rect
        bytes
        ~px_w
        ~px_h
        ~x:(bar_x - 1)
        ~y:(bar_y - 1)
        ~w:(bar_w + 2)
        ~h:(bar_h + 2)
        ~r:180
        ~g:180
        ~b:180 ;
      (* Black background. *)
      fill_rect
        bytes
        ~px_w
        ~px_h
        ~x:bar_x
        ~y:bar_y
        ~w:bar_w
        ~h:bar_h
        ~r:20
        ~g:0
        ~b:0 ;
      (* Red HP fill — white if flashing. *)
      if fill_w > 0 then begin
        let fr = if flashing then 255 else 200 in
        let fg = if flashing then 255 else 20 in
        let fb_ = if flashing then 255 else 20 in
        fill_rect
          bytes
          ~px_w
          ~px_h
          ~x:bar_x
          ~y:bar_y
          ~w:fill_w
          ~h:bar_h
          ~r:fr
          ~g:fg
          ~b:fb_
      end

(* ---------- frame builder ---------- *)

let draw_hazards bytes ~px_w ~px_h (s : Model.t) =
  Array.iter
    (fun (h : Model.hazard) ->
      if h.h_alive then begin
        let hx = int_of_float (h.h_world_x -. s.world_x) in
        let cy = int_of_float h.h_y in
        let half = h.h_height / 2 in
        (* Draw spike column: bright orange-red with white tip. *)
        for i = 0 to h.h_height - 1 do
          let y = cy - half + i in
          let frac = float_of_int i /. float_of_int (max 1 h.h_height) in
          (* Tip is white/yellow, base is deep red. *)
          let r = 255 in
          let g = int_of_float (220.0 -. (frac *. 200.0)) in
          let b = int_of_float (60.0 -. (frac *. 60.0)) in
          put_px bytes ~px_w ~px_h ~x:hx ~y ~r ~g ~b ;
          (* Width: one pixel wide for sharp spike look. *)
          (* Side glow for visibility. *)
          let gr = 200 in
          let gg = int_of_float (80.0 -. (frac *. 60.0)) in
          let gb = 20 in
          put_px bytes ~px_w ~px_h ~x:(hx - 1) ~y ~r:gr ~g:gg ~b:gb ;
          put_px bytes ~px_w ~px_h ~x:(hx + 1) ~y ~r:gr ~g:gg ~b:gb
        done
      end)
    s.hazards

(* ---------- radar panel ---------- *)

(* 30×8 radar panel centred at the top of the playfield. Shows up to 8
   enemy dots relative to the player's position. Enemies ahead are bright;
   enemies behind (off-screen left) are dim. *)
let draw_radar bytes ~px_w ~px_h (s : Model.t) =
  let radar_w = 30 in
  let radar_h = 8 in
  let rx = (px_w - radar_w) / 2 in
  let ry = 2 in
  (* Dark background for the radar panel. *)
  fill_rect
    bytes
    ~px_w
    ~px_h
    ~x:rx
    ~y:ry
    ~w:radar_w
    ~h:radar_h
    ~r:10
    ~g:10
    ~b:20 ;
  (* Border *)
  for x = rx to rx + radar_w - 1 do
    put_px bytes ~px_w ~px_h ~x ~y:ry ~r:40 ~g:80 ~b:60 ;
    put_px bytes ~px_w ~px_h ~x ~y:(ry + radar_h - 1) ~r:40 ~g:80 ~b:60
  done ;
  for y = ry to ry + radar_h - 1 do
    put_px bytes ~px_w ~px_h ~x:rx ~y ~r:40 ~g:80 ~b:60 ;
    put_px bytes ~px_w ~px_h ~x:(rx + radar_w - 1) ~y ~r:40 ~g:80 ~b:60
  done ;
  (* Centre crosshair — represents the player. *)
  let mid_x = rx + (radar_w / 2) in
  let mid_y = ry + (radar_h / 2) in
  put_px bytes ~px_w ~px_h ~x:mid_x ~y:mid_y ~r:100 ~g:220 ~b:180 ;
  (* Collect up to 8 live enemies. *)
  let radar_range_x = float_of_int px_w *. 1.5 in
  let radar_range_y = float_of_int px_h in
  let count = ref 0 in
  Array.iter
    (fun (e : Model.enemy) ->
      if e.alive && !count < 8 && e.kind <> Model.Boss then begin
        let dx = e.x -. s.player.x in
        let dy = e.y -. s.player.y in
        let nx = dx /. radar_range_x in
        (* -1 .. +1 *)
        let ny = dy /. (radar_range_y /. 2.0) in
        let nx = Float.max (-1.0) (Float.min 1.0 nx) in
        let ny = Float.max (-1.0) (Float.min 1.0 ny) in
        let dot_x =
          mid_x + int_of_float (nx *. float_of_int ((radar_w / 2) - 2))
        in
        let dot_y =
          mid_y + int_of_float (ny *. float_of_int ((radar_h / 2) - 1))
        in
        (* Dim if behind player (dx < 0). *)
        let behind = dx < 0.0 in
        let dr = if behind then 60 else 200 in
        let dg = if behind then 60 else 60 in
        let db = if behind then 60 else 60 in
        put_px bytes ~px_w ~px_h ~x:dot_x ~y:dot_y ~r:dr ~g:dg ~b:db ;
        put_px bytes ~px_w ~px_h ~x:(dot_x + 1) ~y:dot_y ~r:dr ~g:dg ~b:db ;
        put_px bytes ~px_w ~px_h ~x:dot_x ~y:(dot_y + 1) ~r:dr ~g:dg ~b:db ;
        put_px bytes ~px_w ~px_h ~x:(dot_x + 1) ~y:(dot_y + 1) ~r:dr ~g:dg ~b:db ;
        incr count
      end)
    s.enemies

(* ---------- big kill announcement ---------- *)

let draw_big_kill bytes ~px_w ~px_h (s : Model.t) =
  if s.big_kill_t > 0.0 then begin
    let text = s.big_kill_text in
    let char_w = 4 in
    let text_px_w = String.length text * char_w in
    let lx = (px_w - text_px_w) / 2 in
    let ly = px_h * 3 / 4 in
    (* Background shadow. *)
    fill_rect
      bytes
      ~px_w
      ~px_h
      ~x:(lx - 2)
      ~y:(ly - 2)
      ~w:(text_px_w + 4)
      ~h:9
      ~r:0
      ~g:0
      ~b:0 ;
    (* Gold text. *)
    let life01 = s.big_kill_t /. 1.5 in
    let bright = int_of_float (180.0 +. (75.0 *. life01)) in
    draw_text_pixels bytes ~px_w ~px_h ~x:lx ~y:ly ~text ~r:255 ~g:bright ~b:60
  end

(* ---------- force tether line ---------- *)

let draw_force_tether bytes ~px_w ~px_h (s : Model.t) =
  match s.player.force with
  | Model.Force_front | Model.Force_back -> ()
  | Model.Force_detached fd ->
      if fd.recalling then begin
        let fx = fd.fx -. s.world_x in
        let fy = fd.fy in
        let sx = s.player.x in
        let sy = s.player.y in
        let dx = sx -. fx in
        let dy = sy -. fy in
        let d = sqrt ((dx *. dx) +. (dy *. dy)) in
        if d > 1.0 then begin
          let nx = dx /. d in
          let ny = dy /. d in
          (* Dashed line: draw every 4th pixel. *)
          let steps = int_of_float (d /. 2.0) in
          for step = 0 to steps - 1 do
            let t = float_of_int step *. 2.0 in
            let px_ = int_of_float (fx +. (nx *. t)) in
            let py_ = int_of_float (fy +. (ny *. t)) in
            (* Alternate bright / dim cyan. *)
            let bright = step land 1 = 0 in
            let r = 0 in
            let g = if bright then 220 else 80 in
            let b = if bright then 255 else 120 in
            put_px bytes ~px_w ~px_h ~x:px_ ~y:py_ ~r ~g ~b
          done
        end
      end

(* ---------- speed-burst ship trail ---------- *)

(* While speed_boost_t > 0, draw a rainbow-hued particle trail behind the
   ship each frame.  We write directly to the pixel buffer rather than
   spawning particles, so there is no per-frame heap allocation. *)
let draw_speed_trail bytes ~px_w ~px_h (s : Model.t) =
  if s.player.alive && s.player.speed_boost_t > 0.0 then begin
    let p = s.player in
    let cx = int_of_float p.x in
    let cy = int_of_float p.y in
    (* Hue cycles with mode_t so the colours shift each frame. *)
    let hue_phase = s.mode_t *. 4.0 in
    (* 5 trail pixels, staggered behind the ship. *)
    for i = 1 to 5 do
      let tx = cx - 4 - i in
      let hue_off = hue_phase +. (float_of_int i *. 0.4) in
      let hf = mod_float hue_off (2.0 *. Float.pi) in
      (* Simple HSV-like cycle: r/g/b shift through rainbow. *)
      let tr = int_of_float (128.0 +. (127.0 *. sin hf)) in
      let tg =
        int_of_float (128.0 +. (127.0 *. sin (hf +. (2.0 *. Float.pi /. 3.0))))
      in
      let tb =
        int_of_float (128.0 +. (127.0 *. sin (hf +. (4.0 *. Float.pi /. 3.0))))
      in
      put_px bytes ~px_w ~px_h ~x:tx ~y:cy ~r:tr ~g:tg ~b:tb ;
      if i <= 3 then begin
        put_px
          bytes
          ~px_w
          ~px_h
          ~x:tx
          ~y:(cy - 1)
          ~r:(tr / 2)
          ~g:(tg / 2)
          ~b:(tb / 2) ;
        put_px
          bytes
          ~px_w
          ~px_h
          ~x:tx
          ~y:(cy + 1)
          ~r:(tr / 2)
          ~g:(tg / 2)
          ~b:(tb / 2)
      end
    done
  end

(* ---------- phase-change warning banner ---------- *)

(* Drawn when boss_phase_warn_t > 0: centered bright red/orange text
   bar across the vertical midpoint, fading as the timer runs down. *)
let draw_phase_warn bytes ~px_w ~px_h (s : Model.t) =
  if s.boss_phase_warn_t > 0.0 then begin
    let frac = s.boss_phase_warn_t /. 0.6 in
    (* Background bar: 5 pixels tall, full width. *)
    let by = (px_h / 2) - 2 in
    let br = int_of_float (180.0 *. frac) in
    let bg_ = int_of_float (40.0 *. frac) in
    fill_rect bytes ~px_w ~px_h ~x:0 ~y:by ~w:px_w ~h:5 ~r:br ~g:bg_ ~b:0 ;
    (* "!! PHASE CHANGE !!" text centred in the bar. *)
    let text = "!! PHASE CHANGE !!" in
    let char_w = 4 in
    let tw = String.length text * char_w in
    let tx = (px_w - tw) / 2 in
    let ty = by in
    let tr = 255 in
    let tg = int_of_float (180.0 +. (75.0 *. frac)) in
    draw_text_pixels bytes ~px_w ~px_h ~x:tx ~y:ty ~text ~r:tr ~g:tg ~b:0
  end

(* ---------- score milestone popup ---------- *)

(* Drawn when milestone_t > 0: big text at top-right, fading out. *)
let draw_milestone bytes ~px_w ~px_h (s : Model.t) =
  if s.milestone_t > 0.0 then begin
    let frac = s.milestone_t /. 1.2 in
    let text = s.milestone_text in
    let char_w = 4 in
    let tw = String.length text * char_w in
    let tx = px_w - tw - 4 in
    let ty = 14 in
    (* Background shadow. *)
    fill_rect
      bytes
      ~px_w
      ~px_h
      ~x:(tx - 2)
      ~y:(ty - 2)
      ~w:(tw + 4)
      ~h:9
      ~r:0
      ~g:0
      ~b:0 ;
    let bright = int_of_float (200.0 +. (55.0 *. frac)) in
    draw_text_pixels bytes ~px_w ~px_h ~x:tx ~y:ty ~text ~r:255 ~g:bright ~b:60
  end

let build_frame (s : Model.t) ~px_w ~px_h =
  let bytes = Bytes.make (px_w * px_h * 3) '\000' in
  (* Screen wipe on level start: white vertical bar sweeps left→right over 0.4s.
     mode_t resets to 0 when we enter Playing, so the wipe plays immediately
     after each level transition. *)
  let draw_level_start_wipe () =
    if s.mode_t < 0.4 then begin
      let wipe_x = int_of_float (s.mode_t /. 0.4 *. float_of_int px_w) in
      let bar_w = 8 in
      fill_rect
        bytes
        ~px_w
        ~px_h
        ~x:(max 0 (wipe_x - bar_w))
        ~y:0
        ~w:bar_w
        ~h:px_h
        ~r:255
        ~g:255
        ~b:255
    end
  in
  draw_stars bytes ~px_w ~px_h ~world_x:s.world_x ~palette:s.palette ;
  draw_terrain
    bytes
    ~px_w
    ~px_h
    ~world_x:s.world_x
    ~palette:s.palette
    ~level_num:s.level ;
  (* Hazard spikes drawn before entities so they're part of the terrain layer. *)
  draw_hazards bytes ~px_w ~px_h s ;
  (* Pickups under bullets so they read as background-y.
     Also draw magnetic pull lines when a pickup is close to the player. *)
  let px = s.player.x in
  let py = s.player.y in
  Array.iter
    (fun (pe : Model.pickup_entity) ->
      if pe.p_alive then begin
        draw_pickup bytes ~px_w ~px_h ~world_t:s.mode_t pe ;
        (* Magnet line: if pickup within 30px, draw 4 dashed yellow pixels
           from pickup toward the player. *)
        let dx = px -. pe.px in
        let dy = py -. pe.py in
        let d2 = (dx *. dx) +. (dy *. dy) in
        if d2 < 30.0 *. 30.0 && d2 > 1.0 then begin
          let d = sqrt d2 in
          let nx = dx /. d in
          let ny = dy /. d in
          (* 4 dashes at intervals of 2px from pickup centre *)
          for step = 1 to 4 do
            let t = float_of_int step *. 2.0 in
            if t < d then begin
              let sx = int_of_float (pe.px +. (nx *. t)) in
              let sy = int_of_float (pe.py +. (ny *. t)) in
              (* Alternate on/off for dash effect *)
              if step land 1 = 1 then
                put_px bytes ~px_w ~px_h ~x:sx ~y:sy ~r:220 ~g:220 ~b:60
            end
          done
        end
      end)
    s.pickups ;
  Array.iter
    (fun (e : Model.enemy) -> if e.alive then draw_enemy bytes ~px_w ~px_h e)
    s.enemies ;
  Array.iter
    (fun (b : Model.bullet) ->
      if b.b_alive then draw_bullet ~ours:true bytes ~px_w ~px_h b)
    s.player_bullets ;
  Array.iter
    (fun (b : Model.bullet) ->
      if b.b_alive then draw_bullet ~ours:false bytes ~px_w ~px_h b)
    s.enemy_bullets ;
  (* Homing bullet trail: spawn a small fading particle at each active
     homing bullet's position each render frame for a glowing red tail. *)
  Array.iter
    (fun (b : Model.bullet) ->
      if b.b_alive && b.b_kind = Model.Bullet_homing then
        Arcade_kit.Particles.spawn
          s.particles
          ~x:b.bx
          ~y:b.by
          ~vx:0.0
          ~vy:0.0
          ~life:0.2
          ~hue:4)
    s.enemy_bullets ;
  draw_particles bytes ~px_w ~px_h s ;
  draw_popups bytes ~px_w ~px_h s ;
  (* Speed-burst trail: drawn before the ship so it's behind it. *)
  draw_speed_trail bytes ~px_w ~px_h s ;
  if s.player.alive then begin
    let cx = int_of_float s.player.x in
    let cy = int_of_float s.player.y in
    draw_ship
      bytes
      ~px_w
      ~px_h
      ~cx
      ~cy
      ~invuln:s.player.invuln
      ~charge:s.player.charge
      ~shield_flash:s.player.weapons.flash_t
      ~pickup_flash:s.player.weapons.pickup_flash_t ;
    let fx, fy = Model.force_world_pos s in
    let detached =
      match s.player.force with Model.Force_detached _ -> true | _ -> false
    in
    (* Tether line when recalling: drawn before the Force sphere. *)
    draw_force_tether bytes ~px_w ~px_h s ;
    draw_force
      bytes
      ~px_w
      ~px_h
      ~cx:(int_of_float fx)
      ~cy:(int_of_float fy)
      ~detached
      ~upgraded:s.player.weapons.has_force_upgrade
  end ;
  (* Apply flash overlay (lighten globally) — cheap approximation. *)
  let alpha = Arcade_kit.Screen_fx.flash_alpha s.fx in
  if alpha > 0.01 then begin
    let add = int_of_float (alpha *. 120.0) in
    let n = Bytes.length bytes in
    let i = ref 0 in
    while !i < n do
      let r = Char.code (Bytes.get bytes !i) in
      Bytes.set bytes !i (Char.chr (min 255 (r + add))) ;
      let g = Char.code (Bytes.get bytes (!i + 1)) in
      Bytes.set bytes (!i + 1) (Char.chr (min 255 (g + add))) ;
      let b = Char.code (Bytes.get bytes (!i + 2)) in
      Bytes.set bytes (!i + 2) (Char.chr (min 255 (b + add))) ;
      i := !i + 3
    done
  end ;
  (* Boss health bar: drawn after flash so it reads clearly. *)
  if s.boss_active then draw_boss_health_bar bytes ~px_w ~px_h s ;
  (* Phase-change warning banner — drawn on top of the boss bar. *)
  draw_phase_warn bytes ~px_w ~px_h s ;
  (* Radar: enemy dot panel at top-centre. *)
  draw_radar bytes ~px_w ~px_h s ;
  (* Big-kill announcement overlay. *)
  draw_big_kill bytes ~px_w ~px_h s ;
  (* Score milestone popup. *)
  draw_milestone bytes ~px_w ~px_h s ;
  (* Lives display: tiny ship silhouettes in the top-right corner. *)
  let lives = max 0 (min 5 s.lives) in
  for i = 0 to lives - 1 do
    (* Each silhouette: 5 wide, 3 tall (40% of the full ship sprite).
       Placed from right edge inward, 7px spacing. *)
    let cx = px_w - 5 - (i * 7) in
    let cy = 4 in
    (* Tiny body: 4×2 rect *)
    fill_rect
      bytes
      ~px_w
      ~px_h
      ~x:(cx - 2)
      ~y:(cy - 1)
      ~w:4
      ~h:2
      ~r:160
      ~g:180
      ~b:220 ;
    (* Tiny nose *)
    put_px bytes ~px_w ~px_h ~x:(cx + 2) ~y:cy ~r:100 ~g:220 ~b:255 ;
    (* Tiny wings *)
    put_px bytes ~px_w ~px_h ~x:(cx - 1) ~y:(cy - 2) ~r:100 ~g:120 ~b:160 ;
    put_px bytes ~px_w ~px_h ~x:(cx - 1) ~y:(cy + 1) ~r:100 ~g:120 ~b:160
  done ;
  (* Low-health alert: pulsing red border (2px wide) when lives == 1. *)
  if s.lives = 1 then begin
    (* 2Hz pulse using mode_t *)
    let pulse = 0.5 +. (0.5 *. sin (s.mode_t *. Float.pi *. 4.0)) in
    let br = int_of_float (180.0 +. (75.0 *. pulse)) in
    (* Top 2 rows *)
    fill_rect bytes ~px_w ~px_h ~x:0 ~y:0 ~w:px_w ~h:2 ~r:br ~g:0 ~b:0 ;
    (* Bottom 2 rows *)
    fill_rect bytes ~px_w ~px_h ~x:0 ~y:(px_h - 2) ~w:px_w ~h:2 ~r:br ~g:0 ~b:0 ;
    (* Left 2 cols *)
    fill_rect bytes ~px_w ~px_h ~x:0 ~y:0 ~w:2 ~h:px_h ~r:br ~g:0 ~b:0 ;
    (* Right 2 cols *)
    fill_rect bytes ~px_w ~px_h ~x:(px_w - 2) ~y:0 ~w:2 ~h:px_h ~r:br ~g:0 ~b:0
  end ;
  (* Screen wipe must be drawn last so it overlays everything. *)
  draw_level_start_wipe () ;
  bytes

(* ---------- HUD ---------- *)

let pad_right s ~width =
  let n = visible_width s in
  if n >= width then s else s ^ String.make (width - n) ' '

let center_in width s =
  let n = visible_width s in
  if n >= width then s
  else
    let pad = (width - n) / 2 in
    String.make pad ' ' ^ s

let force_label = function
  | Model.Force_front -> "Force[F]"
  | Model.Force_back -> "Force[B]"
  | Model.Force_detached _ -> "Force[*]"

(* Render the weapon loadout string for the HUD. *)
let weapon_loadout_hud (w : Model.weapon_state) =
  let parts = Buffer.create 32 in
  Buffer.add_string parts "WPN:" ;
  if w.has_missile then Buffer.add_string parts "[Msl]" ;
  if w.has_force_upgrade then Buffer.add_string parts "[FUp]" ;
  if w.has_shield then begin
    if w.shield_active then Buffer.add_string parts "[Shd]"
    else Buffer.add_string parts "[shd]" (* lowercase = consumed *)
  end ;
  if w.speed_level > 0 then
    Buffer.add_string parts (Printf.sprintf " Spd:%d" w.speed_level) ;
  Buffer.contents parts

(* Build a filled-bar string of [n] filled and [total-n] empty blocks. *)
let tier_bar ~filled ~total =
  let buf = Buffer.create ((total * 3) + 2) in
  Buffer.add_char buf '[' ;
  for i = 0 to total - 1 do
    if i < filled then Buffer.add_string buf "\u{25A0}"
    else Buffer.add_string buf "\u{25A1}"
  done ;
  Buffer.add_char buf ']' ;
  Buffer.contents buf

let render_hud (s : Model.t) ~cols =
  let boss_indicator =
    if s.boss_active then
      let phase = if s.boss_phase = 0 then 1 else s.boss_phase in
      Printf.sprintf " BOSS p%d" phase
    else ""
  in
  let turn_indicator =
    if s.turn_based then Printf.sprintf " [TB:%d]" s.frame_counter else ""
  in
  (* Combo flash: when multiplier ≥ 2, alternate between normal and bright
     yellow/white using a 6 Hz sine, so the timer is highly visible. *)
  let combo_indicator =
    if s.combo > 1 then begin
      let bright = sin (s.mode_t *. 6.0) > 0.0 in
      let tag = Printf.sprintf " x%d" s.combo in
      if bright then "\027[1;33m" ^ tag ^ "\027[0m" else tag
    end
    else ""
  in
  (* Animated score: display_score rolls up toward real score.
     Round to nearest 10 for a counter-rolling effect. *)
  let disp_score =
    let raw = int_of_float s.display_score in
    raw / 10 * 10
  in
  (* Left section: score, best, lives, level, force state. *)
  let left =
    Printf.sprintf
      " LVL%d Score %05d Best %05d Lives %d %s%s%s%s"
      s.level
      disp_score
      s.best
      (max 0 s.lives)
      (force_label s.player.force)
      boss_indicator
      combo_indicator
      turn_indicator
  in
  (* Right section: weapon tier bars + icons. *)
  let w = s.player.weapons in
  let right_parts = Buffer.create 40 in
  (* Speed tier bar: 0–3 filled squares. *)
  if w.speed_level > 0 then begin
    Buffer.add_string right_parts "Spd:" ;
    Buffer.add_string right_parts (tier_bar ~filled:w.speed_level ~total:3) ;
    Buffer.add_char right_parts ' '
  end ;
  if w.has_missile then Buffer.add_string right_parts "[M]" ;
  if w.has_shield then begin
    if w.shield_active then Buffer.add_string right_parts "[S]"
    else Buffer.add_string right_parts "[s]"
  end ;
  if w.has_force_upgrade then Buffer.add_string right_parts "[F+]" ;
  (* Speed-burst active indicator: bright cyan "SPD". *)
  if s.player.speed_boost_t > 0.0 then
    Buffer.add_string right_parts "\027[1;96mSPD\027[0m" ;
  let right = Buffer.contents right_parts ^ " " in
  (* Fill the gap between left and right with spaces. *)
  let left_w = visible_width left in
  let right_w = visible_width right in
  let gap = max 1 (cols - left_w - right_w) in
  let full = left ^ String.make gap ' ' ^ right in
  W.themed_emphasis full

let render_footer ~cols =
  let txt =
    "  Arrows move  Space fire/charge  d detach Force  f flip  Esc back"
  in
  W.themed_muted (pad_right txt ~width:cols)

(* ---------- title screen ---------- *)

let render_title (s : Model.t) ~cols ~rows =
  let lines = ref [] in
  let push x = lines := x :: !lines in
  let blank () = push "" in
  blank () ;
  blank () ;
  push (W.themed_emphasis (center_in cols "MIAOU FORCE")) ;
  push
    (W.themed_muted (center_in cols "an R-Type-style horizontal shoot-em-up")) ;
  blank () ;
  push (center_in cols "═══════════════════════════════════") ;
  blank () ;
  push (center_in cols "Arrow keys  -  Move ship") ;
  push (center_in cols "Space       -  Fire (auto / hold to charge)") ;
  push (center_in cols "d           -  Detach / recall the Force") ;
  push (center_in cols "f           -  Flip Force front / back") ;
  push (center_in cols "Esc         -  Pause / back to launcher") ;
  blank () ;
  push
    (W.themed_emphasis
       (center_in cols "Enter to launch  ·  S for level select")) ;
  blank () ;
  blank () ;
  (* Prominent best-score display with pilot rank. *)
  push
    (W.themed_emphasis
       (center_in cols (Printf.sprintf "BEST SCORE: %06d" s.best))) ;
  let rank_str =
    if s.best > 50000 then "RANK: ACE PILOT ***"
    else if s.best > 20000 then "RANK: VETERAN **"
    else if s.best > 5000 then "RANK: RECRUIT *"
    else "RANK: CADET"
  in
  push (W.themed_muted (center_in cols rank_str)) ;
  (* Per-level best scores shown below rank if any are non-zero. *)
  let bl = s.best_level in
  if bl.(0) > 0 || bl.(1) > 0 || bl.(2) > 0 then
    push
      (W.themed_muted
         (center_in
            cols
            (Printf.sprintf
               "Lv1: %04d  Lv2: %04d  Lv3: %04d"
               bl.(0)
               bl.(1)
               bl.(2)))) ;
  let blink = int_of_float (s.mode_t *. 2.0) mod 2 = 0 in
  if blink then push (W.themed_muted (center_in cols ">>> ready <<<"))
  else push "" ;
  let body = List.rev !lines in
  let body_lines = List.length body in
  let pad_top = max 0 ((rows - body_lines) / 2) in
  let top = List.init pad_top (fun _ -> "") in
  String.concat "\n" (top @ body)

let render_game_over (s : Model.t) ~cols ~rows =
  let lines = ref [] in
  let push x = lines := x :: !lines in
  let blank () = push "" in
  blank () ;
  push (W.themed_emphasis (center_in cols "GAME OVER")) ;
  blank () ;
  (* Pilot status: KIA in bold red. *)
  push (center_in cols "\027[1;31mPILOT STATUS: KIA\027[0m") ;
  push (center_in cols (Printf.sprintf "REACHED LEVEL: %d" s.level)) ;
  blank () ;
  (* Lives display: hearts for remaining lives (uses ASCII fallback <3). *)
  let hearts =
    let n = max 0 (min 3 s.lives) in
    if n = 0 then "\027[31m[ no lives remain ]\027[0m"
    else
      let h = String.concat " " (List.init n (fun _ -> "\u{2665}")) in
      Printf.sprintf "LIVES: \027[1;31m%s\027[0m" h
  in
  push (center_in cols hearts) ;
  blank () ;
  push (center_in cols (Printf.sprintf "Score: %d" s.score)) ;
  push (center_in cols (Printf.sprintf "Best:  %d" s.best)) ;
  blank () ;
  (* Show per-level breakdown if any levels were cleared. *)
  let any_scored = Array.exists (fun v -> v > 0) s.level_scores in
  if any_scored then begin
    push (center_in cols "Level scores:") ;
    Array.iteri
      (fun i sc ->
        if sc > 0 then
          push (center_in cols (Printf.sprintf "  Level %d: %d" (i + 1) sc)))
      s.level_scores ;
    blank ()
  end ;
  push
    (W.themed_muted
       (center_in cols "Enter to retry · S for level select · Esc to leave")) ;
  let body = List.rev !lines in
  let pad_top = max 0 ((rows - List.length body) / 2) in
  let top = List.init pad_top (fun _ -> "") in
  String.concat "\n" (top @ body)

let render_level_clear (s : Model.t) ~cols ~rows =
  let lines = ref [] in
  let push x = lines := x :: !lines in
  let blank () = push "" in
  push "" ;
  push
    (W.themed_emphasis
       (center_in cols (Printf.sprintf "*** LEVEL %d CLEAR ***" s.level))) ;
  push "" ;
  push (W.themed_emphasis (center_in cols "BOSS DEFEATED")) ;
  push "" ;
  push (center_in cols (Printf.sprintf "Score: %d" s.score)) ;
  push "" ;
  (* Weapon loadout summary. *)
  let w = s.player.weapons in
  let loadout_parts = ref [] in
  if w.has_missile then loadout_parts := "Missile" :: !loadout_parts ;
  if w.has_force_upgrade then loadout_parts := "Force+" :: !loadout_parts ;
  if w.has_shield then
    loadout_parts :=
      (if w.shield_active then "Shield" else "Shield(used)") :: !loadout_parts ;
  if w.speed_level > 0 then
    loadout_parts := Printf.sprintf "Speed x%d" w.speed_level :: !loadout_parts ;
  if !loadout_parts <> [] then begin
    push
      (center_in
         cols
         (Printf.sprintf
            "Upgrades: %s"
            (String.concat ", " (List.rev !loadout_parts)))) ;
    blank ()
  end ;
  if s.level < Levels.max_level then begin
    push
      (W.themed_emphasis
         (center_in
            cols
            (Printf.sprintf "Press Enter for Level %d" (s.level + 1)))) ;
    push (W.themed_muted (center_in cols "Esc to leave"))
  end
  else begin
    push (W.themed_emphasis (center_in cols "MISSION COMPLETE")) ;
    blank () ;
    (* Level-by-level score breakdown. *)
    let ls = s.level_scores in
    push
      (center_in
         cols
         (Printf.sprintf
            "LVL 1: %5d  LVL 2: %5d  LVL 3: %5d"
            ls.(0)
            ls.(1)
            ls.(2))) ;
    blank () ;
    push
      (W.themed_muted
         (center_in cols (Printf.sprintf "Final score: %d" s.score))) ;
    (* Pilot ranking based on total score. *)
    let rank =
      if s.score > 50000 then "\027[1;33mACE PILOT\027[0m"
      else if s.score > 20000 then "\027[1;36mVETERAN\027[0m"
      else if s.score > 5000 then "\027[1;32mCADET\027[0m"
      else "ROOKIE"
    in
    push (center_in cols (Printf.sprintf "PILOT RANK: %s" rank)) ;
    blank () ;
    push
      (W.themed_muted
         (center_in cols "Press Enter to return to title  ·  Esc to leave"))
  end ;
  let body = List.rev !lines in
  let pad_top = max 0 ((rows - List.length body) / 2) in
  let top = List.init pad_top (fun _ -> "") in
  String.concat "\n" (top @ body)

let level_name = function
  | 1 -> "Vanguard Run"
  | 2 -> "Asteroid Belt"
  | 3 -> "The Core"
  | _ -> "Unknown"

let render_level_select (s : Model.t) ~cols ~rows =
  let lines = ref [] in
  let push x = lines := x :: !lines in
  let blank () = push "" in
  blank () ;
  push (W.themed_emphasis (center_in cols "SELECT LEVEL")) ;
  blank () ;
  push (center_in cols "Use Up/Down to choose, Enter to start") ;
  blank () ;
  for i = 1 to Levels.max_level do
    let cursor = if s.level_select_cursor = i - 1 then "> " else "  " in
    let score_txt =
      let sc = s.level_scores.(i - 1) in
      if sc > 0 then Printf.sprintf "  (best: %d)" sc else ""
    in
    let line =
      Printf.sprintf "%sLevel %d: %s%s" cursor i (level_name i) score_txt
    in
    if s.level_select_cursor = i - 1 then
      push (W.themed_emphasis (center_in cols line))
    else push (center_in cols line) ;
    blank ()
  done ;
  blank () ;
  push (W.themed_muted (center_in cols "Esc to return to title")) ;
  let body = List.rev !lines in
  let pad_top = max 0 ((rows - List.length body) / 2) in
  let top = List.init pad_top (fun _ -> "") in
  String.concat "\n" (top @ body)

(* ---------- level-clear animation screen ---------- *)

(* Render the 2-second level-clear cinematic: particles from boss explosion
   still on screen, white flash fading out, centred "LEVEL N CLEAR!" text. *)
let render_level_clear_anim (s : Model.t) ~anim_t ~level ~cols ~rows ~px_w ~px_h
    ~fb ~mode =
  (* Reuse the in-flight particle/fx frame. *)
  let bytes = Bytes.make (px_w * px_h * 3) '\000' in
  draw_stars bytes ~px_w ~px_h ~world_x:s.world_x ~palette:s.palette ;
  draw_terrain
    bytes
    ~px_w
    ~px_h
    ~world_x:s.world_x
    ~palette:s.palette
    ~level_num:s.level ;
  draw_particles bytes ~px_w ~px_h s ;
  (* Fade-out white flash: full at t=0, gone by t=1.0 *)
  let flash_strength = Float.max 0.0 (1.0 -. (anim_t *. 1.5)) in
  if flash_strength > 0.01 then begin
    let add = int_of_float (flash_strength *. 200.0) in
    let n = Bytes.length bytes in
    let i = ref 0 in
    while !i < n do
      let r = Char.code (Bytes.get bytes !i) in
      Bytes.set bytes !i (Char.chr (min 255 (r + add))) ;
      let g = Char.code (Bytes.get bytes (!i + 1)) in
      Bytes.set bytes (!i + 1) (Char.chr (min 255 (g + add))) ;
      let b = Char.code (Bytes.get bytes (!i + 2)) in
      Bytes.set bytes (!i + 2) (Char.chr (min 255 (b + add))) ;
      i := !i + 3
    done
  end ;
  (* Overlay "LEVEL N CLEAR!" centred in the frame. *)
  let label = Printf.sprintf "LEVEL %d CLEAR!" level in
  let char_w = 4 in
  let label_px_w = String.length label * char_w in
  let lx = (px_w - label_px_w) / 2 in
  let ly = (px_h / 2) - 14 in
  (* Gold text *)
  draw_text_pixels bytes ~px_w ~px_h ~x:lx ~y:ly ~text:label ~r:255 ~g:220 ~b:60 ;
  (* Score line below *)
  let score_label = Printf.sprintf "SCORE %d" s.score in
  let slx = (px_w - (String.length score_label * char_w)) / 2 in
  draw_text_pixels
    bytes
    ~px_w
    ~px_h
    ~x:slx
    ~y:(ly + 10)
    ~text:score_label
    ~r:200
    ~g:200
    ~b:255 ;
  (* Max combo reached. *)
  let combo_label = Printf.sprintf "MAX COMBO %dX" s.combo_max in
  let clx = (px_w - (String.length combo_label * char_w)) / 2 in
  draw_text_pixels
    bytes
    ~px_w
    ~px_h
    ~x:clx
    ~y:(ly + 20)
    ~text:combo_label
    ~r:255
    ~g:180
    ~b:80 ;
  (* Lives remaining. *)
  let lives_label = Printf.sprintf "LIVES %d" (max 0 s.lives) in
  let llx = (px_w - (String.length lives_label * char_w)) / 2 in
  draw_text_pixels
    bytes
    ~px_w
    ~px_h
    ~x:llx
    ~y:(ly + 30)
    ~text:lives_label
    ~r:100
    ~g:220
    ~b:180 ;
  (* Skip hint *)
  let skip_label = "SPACE TO SKIP" in
  let sklx = (px_w - (String.length skip_label * char_w)) / 2 in
  draw_text_pixels
    bytes
    ~px_w
    ~px_h
    ~x:sklx
    ~y:(ly + 40)
    ~text:skip_label
    ~r:120
    ~g:120
    ~b:120 ;
  FB.blit fb ~src:bytes ~width:px_w ~height:px_h ;
  let _ = (cols, rows) in
  FB.render_with_mode fb ~mode ~cols ~rows

(* ---------- top-level ---------- *)

let too_small_msg = "Resize terminal — needs at least 60×20"

(* Cap framebuffer to keep encoding bounded on large terminals. *)
let cap_frame_cols = 160

let cap_frame_rows = 48

let mode_px_per_cell mode =
  match mode with
  | Caps.Sixel -> (8, 16)
  | Caps.Octant -> (2, 4)
  | Caps.Sextant -> (2, 3)
  | Caps.Half_block -> (1, 2)
  | Caps.Braille -> (2, 4)

let render (s : Model.t) ~fb ~size =
  let cols = size.LTerm_geom.cols in
  let rows = size.LTerm_geom.rows in
  if cols < 60 || rows < 20 then too_small_msg
  else
    let frame_cols = min cap_frame_cols cols in
    let frame_rows = min cap_frame_rows (rows - 2) in
    let mode =
      Arcade_kit.Pixel_mode.resolve ~env_var:"MIAOU_FORCE_PIXEL_MODE" ()
    in
    let px_x, px_y = mode_px_per_cell mode in
    let px_w = frame_cols * px_x in
    let px_h = frame_rows * px_y in
    (* Update arena bounds in the model — view owns the canvas size. *)
    s.arena_w <- px_w ;
    s.arena_h <- px_h ;
    let body =
      match s.mode with
      | Model.Title -> render_title s ~cols:frame_cols ~rows:frame_rows
      | Model.Game_over -> render_game_over s ~cols:frame_cols ~rows:frame_rows
      | Model.Level_clear ->
          render_level_clear s ~cols:frame_cols ~rows:frame_rows
      | Model.Level_clear_anim anim ->
          render_level_clear_anim
            s
            ~anim_t:anim.anim_t
            ~level:anim.level
            ~cols:frame_cols
            ~rows:frame_rows
            ~px_w
            ~px_h
            ~fb
            ~mode
      | Model.Level_select ->
          render_level_select s ~cols:frame_cols ~rows:frame_rows
      | Model.Playing ->
          let bytes = build_frame s ~px_w ~px_h in
          FB.blit fb ~src:bytes ~width:px_w ~height:px_h ;
          FB.render_with_mode fb ~mode ~cols:frame_cols ~rows:frame_rows
    in
    let header = render_hud s ~cols:frame_cols in
    let footer = render_footer ~cols:frame_cols in
    String.concat "\n" [header; body; footer]
