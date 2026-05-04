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

let pad_right s ~width =
  let n = visible_width s in
  if n >= width then s else s ^ String.make (width - n) ' '

let center_in width s =
  let n = visible_width s in
  if n >= width then s
  else
    let pad = (width - n) / 2 in
    String.make pad ' ' ^ s

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

let ring_circle bytes ~px_w ~px_h ~cx ~cy ~radius ~r ~g ~b =
  let n = max 12 (radius * 6) in
  for k = 0 to n - 1 do
    let a = Float.of_int k /. Float.of_int n *. 2.0 *. Float.pi in
    let x = cx + int_of_float (Float.of_int radius *. cos a) in
    let y = cy + int_of_float (Float.of_int radius *. sin a) in
    put_px bytes ~px_w ~px_h ~x ~y ~r ~g ~b
  done

(* ---------- world-to-screen mapping ---------- *)

(* Map a tile coordinate (tx, ty) to a centred pixel rectangle in the
   framebuffer. Tile size is chosen so the whole hole fits. *)

let tile_pixel_box ~px_w ~px_h ~tile_w ~tile_h ~tx ~ty ~ox ~oy =
  let x = ox + (tx * tile_w) in
  let y = oy + (ty * tile_h) in
  (x, y, tile_w, tile_h, px_w, px_h)

(* ---------- pastel palettes ---------- *)

(* Soft pastel — deliberately unlike Force/Crypt neon. *)

let fairway_rgb ~shade =
  (* shade in 0..1, 0 = darker, 1 = lighter. *)
  let r = int_of_float (90.0 +. (40.0 *. shade)) in
  let g = int_of_float (160.0 +. (50.0 *. shade)) in
  let b = int_of_float (90.0 +. (30.0 *. shade)) in
  (r, g, b)

let green_rgb ~shade =
  let r = int_of_float (130.0 +. (30.0 *. shade)) in
  let g = int_of_float (200.0 +. (40.0 *. shade)) in
  let b = int_of_float (120.0 +. (30.0 *. shade)) in
  (r, g, b)

let rough_rgb = (60, 110, 70)

let sand_rgb ~shade =
  let r = int_of_float (220.0 +. (25.0 *. shade)) in
  let g = int_of_float (200.0 +. (25.0 *. shade)) in
  let b = int_of_float (140.0 +. (20.0 *. shade)) in
  (r, g, b)

let water_rgb ~shimmer =
  let r = int_of_float (40.0 +. (15.0 *. shimmer)) in
  let g = int_of_float (90.0 +. (30.0 *. shimmer)) in
  let b = int_of_float (170.0 +. (50.0 *. shimmer)) in
  (r, g, b)

let wall_rgb = (40, 50, 35)

(* Cheap soft Lambert-ish hill. Use a low-frequency sine in (x, y) to
   suggest gentle terrain undulation. *)
let hill_shade ~wx ~wy =
  let v = (sin (wx *. 0.06) *. cos (wy *. 0.07)) +. (0.5 *. sin (wx *. 0.15)) in
  Float.max 0.0 (Float.min 1.0 (0.5 +. (0.4 *. v)))

(* ---------- terrain pass ---------- *)

(* Static terrain: all tiles except Water (water shimmer is time-varying
   so it is repainted every frame on top of the cached background). *)
let draw_terrain_static bytes ~px_w ~px_h ~hole ~tile_w ~tile_h ~ox ~oy =
  let h = hole.Model.height in
  let w = hole.Model.width in
  for ty = 0 to h - 1 do
    for tx = 0 to w - 1 do
      let t = hole.Model.layout.(ty).(tx) in
      let bx, by, bw, bh, _, _ =
        tile_pixel_box ~px_w ~px_h ~tile_w ~tile_h ~tx ~ty ~ox ~oy
      in
      match t with
      | Model.Wall_oob ->
          let r, g, b = wall_rgb in
          fill_rect bytes ~px_w ~px_h ~x:bx ~y:by ~w:bw ~h:bh ~r ~g ~b
      | Model.Fairway | Model.Tee ->
          for dy = 0 to bh - 1 do
            for dx = 0 to bw - 1 do
              let wx = float_of_int (bx + dx) in
              let wy = float_of_int (by + dy) in
              let shade = hill_shade ~wx ~wy in
              let r, g, b = fairway_rgb ~shade in
              put_px bytes ~px_w ~px_h ~x:(bx + dx) ~y:(by + dy) ~r ~g ~b
            done
          done
      | Model.Rough ->
          (* Slightly noisy darker green. *)
          let r0, g0, b0 = rough_rgb in
          for dy = 0 to bh - 1 do
            for dx = 0 to bw - 1 do
              let n = (((bx + dx) * 7) + ((by + dy) * 13)) mod 11 in
              let jitter = n - 5 in
              let r = max 0 (min 255 (r0 + jitter)) in
              let g = max 0 (min 255 (g0 + (jitter * 2))) in
              let b = max 0 (min 255 (b0 + jitter)) in
              put_px bytes ~px_w ~px_h ~x:(bx + dx) ~y:(by + dy) ~r ~g ~b
            done
          done
      | Model.Sand ->
          for dy = 0 to bh - 1 do
            for dx = 0 to bw - 1 do
              let wx = float_of_int (bx + dx) in
              let wy = float_of_int (by + dy) in
              let shade =
                Float.max
                  0.0
                  (Float.min
                     1.0
                     (0.5 +. (0.5 *. sin ((wx *. 0.7) +. (wy *. 0.4)))))
              in
              let r, g, b = sand_rgb ~shade in
              put_px bytes ~px_w ~px_h ~x:(bx + dx) ~y:(by + dy) ~r ~g ~b
            done
          done
      | Model.Water ->
          (* Placeholder: paint a flat base colour so the cache is fully
             populated.  The animated shimmer overwrites this each frame. *)
          let r, g, b = water_rgb ~shimmer:0.5 in
          fill_rect bytes ~px_w ~px_h ~x:bx ~y:by ~w:bw ~h:bh ~r ~g ~b
      | Model.Green | Model.Cup ->
          for dy = 0 to bh - 1 do
            for dx = 0 to bw - 1 do
              let wx = float_of_int (bx + dx) in
              let wy = float_of_int (by + dy) in
              let shade = hill_shade ~wx ~wy in
              let r, g, b = green_rgb ~shade in
              (* Grain direction stripes: alternate +8/-8 on G channel
                 every 4 pixel rows to simulate putting surface grain. *)
              let grain_offset = if (by + dy) / 4 mod 2 = 0 then 8 else -8 in
              let g' = max 0 (min 255 (g + grain_offset)) in
              put_px bytes ~px_w ~px_h ~x:(bx + dx) ~y:(by + dy) ~r ~g:g' ~b
            done
          done
    done
  done

(* Animate water tiles over the cached background (called every frame). *)
let draw_water_shimmer bytes ~px_w ~px_h ~hole ~tile_w ~tile_h ~ox ~oy ~time =
  let h = hole.Model.height in
  let w = hole.Model.width in
  for ty = 0 to h - 1 do
    for tx = 0 to w - 1 do
      if hole.Model.layout.(ty).(tx) = Model.Water then begin
        let bx, by, bw, bh, _, _ =
          tile_pixel_box ~px_w ~px_h ~tile_w ~tile_h ~tx ~ty ~ox ~oy
        in
        for dy = 0 to bh - 1 do
          for dx = 0 to bw - 1 do
            let wx = float_of_int (bx + dx) in
            let wy = float_of_int (by + dy) in
            let shimmer =
              0.5 +. (0.5 *. sin ((wx *. 0.5) +. (wy *. 0.4) +. (time *. 2.0)))
            in
            let r, g, b = water_rgb ~shimmer in
            put_px bytes ~px_w ~px_h ~x:(bx + dx) ~y:(by + dy) ~r ~g ~b
          done
        done
      end
    done
  done

(* ---------- cup ---------- *)

let draw_cup bytes ~px_w ~px_h ~hole ~tile_w ~tile_h ~ox ~oy ~time ~aiming =
  let cx_t, cy_t = hole.Model.cup in
  let cx = ox + (cx_t * tile_w) + (tile_w / 2) in
  let cy = oy + (cy_t * tile_h) + (tile_h / 2) in
  (* Dark cup hole. *)
  fill_disc
    bytes
    ~px_w
    ~px_h
    ~cx
    ~cy
    ~radius:(max 1 (tile_w / 3))
    ~r:30
    ~g:30
    ~b:30 ;
  (* Pulsing ring. *)
  let pulse = 0.5 +. (0.5 *. sin (time *. 3.0)) in
  let radius = max 2 (tile_w + int_of_float (pulse *. float_of_int tile_w)) in
  ring_circle
    bytes
    ~px_w
    ~px_h
    ~cx
    ~cy
    ~radius
    ~r:(220 + int_of_float (pulse *. 35.0))
    ~g:(220 + int_of_float (pulse *. 35.0))
    ~b:120 ;
  (* Capture zone ring: pulsing green outer ring shown while aiming to
     indicate the capture radius the ball must enter to hole out. *)
  if aiming then begin
    let outer_radius = radius + 2 + int_of_float (pulse *. 2.0) in
    ring_circle
      bytes
      ~px_w
      ~px_h
      ~cx
      ~cy
      ~radius:outer_radius
      ~r:60
      ~g:(180 + int_of_float (pulse *. 70.0))
      ~b:80
  end ;
  (* Flag stick — vertical short line above the cup. *)
  let h_flag = tile_h * 2 in
  for dy = 1 to h_flag do
    put_px bytes ~px_w ~px_h ~x:cx ~y:(cy - dy) ~r:200 ~g:80 ~b:80
  done ;
  fill_rect
    bytes
    ~px_w
    ~px_h
    ~x:(cx + 1)
    ~y:(cy - h_flag)
    ~w:(tile_w + 1)
    ~h:(max 2 (tile_h / 2))
    ~r:230
    ~g:80
    ~b:80

(* ---------- ball ---------- *)

let draw_ball bytes ~px_w ~px_h ~ox ~oy ~tile_w ~tile_h (b : Model.ball) =
  let bx = ox + int_of_float (b.x *. float_of_int tile_w) in
  let by = oy + int_of_float (b.y *. float_of_int tile_h) in
  let z_off = int_of_float (b.z *. float_of_int tile_h *. 0.6) in
  let cy = by - z_off in
  let radius = max 1 (tile_w / 3) in
  (* Shadow on the ground. *)
  if b.in_flight then begin
    fill_disc
      bytes
      ~px_w
      ~px_h
      ~cx:bx
      ~cy:by
      ~radius:(max 1 (radius - 1))
      ~r:20
      ~g:25
      ~b:20 ;
    (* Glow halo: dim yellow disc slightly larger than the ball. *)
    fill_disc
      bytes
      ~px_w
      ~px_h
      ~cx:bx
      ~cy
      ~radius:(radius + 2)
      ~r:180
      ~g:160
      ~b:60
  end ;
  (* Soft sphere — bright core + dim rim. *)
  fill_disc bytes ~px_w ~px_h ~cx:bx ~cy ~radius ~r:235 ~g:240 ~b:245 ;
  put_px bytes ~px_w ~px_h ~x:(bx - 1) ~y:(cy - 1) ~r:255 ~g:255 ~b:255

(* ---------- aim arrow ---------- *)

(* Stamp a small filled disc — used to give the arrow a thick, visible shaft. *)
let stamp_disc bytes ~px_w ~px_h ~cx ~cy ~radius ~r ~g ~b =
  let r2 = radius * radius in
  for dy = -radius to radius do
    for dx = -radius to radius do
      if (dx * dx) + (dy * dy) <= r2 then
        put_px bytes ~px_w ~px_h ~x:(cx + dx) ~y:(cy + dy) ~r ~g ~b
    done
  done

(* Pick the arrow colour given the current state.
   - Aiming: colour depends on the club (Driver=bright yellow, Iron=orange,
     Wedge=green, Putter=pale blue), or hot (eagle_eye) warms them all
   - Powering: green→yellow→red gradient based on meter01 regardless of club
   - extra_glow: optional [eagle_eye] perk uses a hotter palette. *)
let arrow_color ~meter01 ~hot ~club =
  match meter01 with
  | Some m ->
      (* Powering: power-meter gradient overrides club tint. *)
      if m < 0.4 then
        let t = m /. 0.4 in
        let r = int_of_float (90.0 +. (180.0 *. t)) in
        let g = int_of_float (220.0 -. (40.0 *. t)) in
        let b = int_of_float (90.0 -. (40.0 *. t)) in
        (r, g, b)
      else if m < 0.8 then
        let t = (m -. 0.4) /. 0.4 in
        let r = int_of_float (210.0 +. (45.0 *. t)) in
        let g = int_of_float (190.0 -. (10.0 *. t)) in
        let b = int_of_float (60.0 -. (40.0 *. t)) in
        (r, g, b)
      else
        let t = Float.min 1.0 ((m -. 0.8) /. 0.2) in
        let r = 255 in
        let g = int_of_float (180.0 -. (90.0 *. t)) in
        let b = int_of_float (40.0 -. (20.0 *. t)) in
        (r, g, b)
  | None -> (
      if
        (* Aiming: each club has its own visual style. *)
        hot
      then (255, 80, 50) (* eagle_eye flame orange *)
      else
        match club with
        | Some Model.Driver ->
            (* Solid bright yellow — long, full brightness. *)
            (255, 230, 40)
        | Some Model.Iron ->
            (* Orange-tinted. *)
            (255, 160, 60)
        | Some Model.Wedge ->
            (* Green-tinted, shorter. *)
            (100, 220, 90)
        | Some Model.Putter ->
            (* Pale blue, small. *)
            (140, 180, 255)
        | None ->
            (* Fallback amber. *)
            (255, 220, 60))

(* Draw a thick multi-cell arrow originating at (bx, by), oriented at [angle],
   with pixel length [length_px]. The arrow has:
   - a 3-px-wide shaft (drawn as overlapping stamped discs along the line)
   - a thin black outline so the bright shaft pops against the fairway
   - a triangular arrowhead at the tip (~6 px wide, ~9 px deep)
   - a small disc at the origin so the player sees the pivot
   The colour is chosen from [arrow_color]. *)
let draw_aim_arrow bytes ~px_w ~px_h ~bx ~by ~angle ~length_px ~meter01 ~hot
    ~club =
  let r, g, b = arrow_color ~meter01 ~hot ~club in
  let cosa = cos angle in
  let sina = sin angle in
  let n = max 6 length_px in
  (* tip in px *)
  let tip_x = bx + int_of_float (cosa *. float_of_int n) in
  let tip_y = by + int_of_float (sina *. float_of_int n) in
  (* Shaft outline (dark) — slightly thicker. *)
  for k = 0 to n - 1 do
    let t = float_of_int k in
    let x = bx + int_of_float (cosa *. t) in
    let y = by + int_of_float (sina *. t) in
    stamp_disc bytes ~px_w ~px_h ~cx:x ~cy:y ~radius:3 ~r:20 ~g:20 ~b:20
  done ;
  (* Shaft fill (bright). *)
  for k = 0 to n - 1 do
    let t = float_of_int k in
    let x = bx + int_of_float (cosa *. t) in
    let y = by + int_of_float (sina *. t) in
    stamp_disc bytes ~px_w ~px_h ~cx:x ~cy:y ~radius:2 ~r ~g ~b
  done ;
  (* Arrowhead — filled triangle. We sweep from the tip backward along
     the inward normal directions and stamp a wedge. *)
  let head_depth = 9 in
  let head_half_w = 6 in
  let nx = -.sina in
  (* normal *)
  let ny = cosa in
  for d = 0 to head_depth - 1 do
    let frac = float_of_int d /. float_of_int head_depth in
    let span = int_of_float (float_of_int head_half_w *. (1.0 -. frac)) in
    let cx0 = tip_x - int_of_float (cosa *. float_of_int d) in
    let cy0 = tip_y - int_of_float (sina *. float_of_int d) in
    for k = -span to span do
      let x = cx0 + int_of_float (nx *. float_of_int k) in
      let y = cy0 + int_of_float (ny *. float_of_int k) in
      (* outline *)
      stamp_disc bytes ~px_w ~px_h ~cx:x ~cy:y ~radius:1 ~r:20 ~g:20 ~b:20
    done ;
    let span = max 0 (span - 1) in
    for k = -span to span do
      let x = cx0 + int_of_float (nx *. float_of_int k) in
      let y = cy0 + int_of_float (ny *. float_of_int k) in
      put_px bytes ~px_w ~px_h ~x ~y ~r ~g ~b
    done
  done ;
  (* Tiny dark dot at origin to mark the pivot. *)
  stamp_disc bytes ~px_w ~px_h ~cx:bx ~cy:by ~radius:2 ~r:30 ~g:30 ~b:30 ;
  stamp_disc
    bytes
    ~px_w
    ~px_h
    ~cx:bx
    ~cy:by
    ~radius:1
    ~r:(min 255 (r + 30))
    ~g:(min 255 (g + 30))
    ~b:(min 255 (b + 30))

(* ---------- power meter overlay (bottom strip) ---------- *)

let draw_power_meter bytes ~px_w ~px_h ~meter01 =
  let bar_h = 3 in
  let y0 = px_h - bar_h - 2 in
  let inner_w = px_w - 20 in
  fill_rect bytes ~px_w ~px_h ~x:10 ~y:y0 ~w:inner_w ~h:bar_h ~r:40 ~g:40 ~b:40 ;
  let filled = int_of_float (meter01 *. float_of_int inner_w) in
  let r, g, b =
    if meter01 < 0.4 then (140, 200, 90)
    else if meter01 < 0.8 then (240, 200, 80)
    else (240, 90, 90)
  in
  fill_rect bytes ~px_w ~px_h ~x:10 ~y:y0 ~w:filled ~h:bar_h ~r ~g ~b

(* ---------- wind indicator ---------- *)

(* A small flag-and-arrow widget at the top-left of the playfield that
   shows the *current shot's* wind vector. The arrow pulses gently. *)
let draw_wind_widget bytes ~px_w ~px_h ~ox ~oy ~wind_x ~wind_y ~time ~gust =
  let cx = ox + 6 in
  let cy = oy + 8 in
  (* Backdrop — red-tinted when a gust is active. *)
  let bg_r = if gust then 35 else 18 in
  let bg_b = if gust then 18 else 18 in
  fill_rect
    bytes
    ~px_w
    ~px_h
    ~x:(cx - 6)
    ~y:(cy - 6)
    ~w:13
    ~h:13
    ~r:bg_r
    ~g:25
    ~b:bg_b ;
  (* Pulsing ring — orange when gusting, green otherwise. *)
  let pulse = 0.6 +. (0.4 *. sin (time *. if gust then 8.0 else 4.0)) in
  let ring_r = int_of_float (200.0 *. pulse) in
  let ring_g = if gust then int_of_float (80.0 *. pulse) else ring_r in
  let ring_b = if gust then 0 else 80 in
  ring_circle bytes ~px_w ~px_h ~cx ~cy ~radius:6 ~r:ring_r ~g:ring_g ~b:ring_b ;
  (* Wind arrow direction inside the ring. *)
  let mag = sqrt ((wind_x *. wind_x) +. (wind_y *. wind_y)) +. 0.0001 in
  let nx = wind_x /. mag in
  let ny = wind_y /. mag in
  let len = max 2 (int_of_float (3.0 +. (mag *. 4.0))) in
  for k = 0 to len - 1 do
    let t = float_of_int k in
    let x = cx + int_of_float (nx *. t) in
    let y = cy + int_of_float (ny *. t) in
    let ar = if gust then 255 else 255 in
    let ag = if gust then 140 else 255 in
    let ab = if gust then 0 else 140 in
    put_px bytes ~px_w ~px_h ~x ~y ~r:ar ~g:ag ~b:ab
  done ;
  (* Tip dot brighter. *)
  let tip_x = cx + int_of_float (nx *. float_of_int (len - 1)) in
  let tip_y = cy + int_of_float (ny *. float_of_int (len - 1)) in
  stamp_disc
    bytes
    ~px_w
    ~px_h
    ~cx:tip_x
    ~cy:tip_y
    ~radius:1
    ~r:255
    ~g:255
    ~b:255 ;
  (* Perpendicular tick marks on the arrow shaft to indicate wind strength. *)
  if mag > 0.5 then begin
    let perp_x = -.ny and perp_y = nx in
    for t = 1 to 3 do
      let frac = float_of_int t /. 4.0 in
      let tx = cx + int_of_float (nx *. float_of_int (len / 2) *. frac) in
      let ty = cy + int_of_float (ny *. float_of_int (len / 2) *. frac) in
      put_px
        bytes
        ~px_w
        ~px_h
        ~x:(tx + int_of_float (perp_x *. 2.0))
        ~y:(ty + int_of_float (perp_y *. 2.0))
        ~r:255
        ~g:255
        ~b:100 ;
      put_px
        bytes
        ~px_w
        ~px_h
        ~x:(tx - int_of_float (perp_x *. 2.0))
        ~y:(ty - int_of_float (perp_y *. 2.0))
        ~r:255
        ~g:255
        ~b:100
    done
  end ;
  (* When a gust is active, draw bright red "GUST" dots above the widget. *)
  if gust then begin
    (* Simple 4-pixel row of hot-orange dots just above the widget. *)
    let gust_y = cy - 8 in
    for dx = -5 to 5 do
      let blink = int_of_float (time *. 8.0) mod 2 = 0 in
      if blink then
        put_px bytes ~px_w ~px_h ~x:(cx + dx) ~y:gust_y ~r:255 ~g:100 ~b:0
    done
  end

(* ---------- stamina-bar overlay drawn in the framebuffer
   (mirrors the HUD bar but more visible during play).
   When stamina ≤ 3 the bar blinks using [mode_t] and a "LOW STAMINA!"
   pixel-dot label appears to the right of the bar. *)
let draw_stamina_bar bytes ~px_w ~px_h ~stamina ~max_stamina ~mode_t =
  if max_stamina <= 0 then ()
  else
    let low = stamina <= 3 in
    (* Blink: sin(mode_t * 8) > 0 → visible; flickers roughly 4 times/s. *)
    let visible = (not low) || sin (mode_t *. 8.0) > 0.0 in
    if not visible then ()
    else begin
      let bar_w = 80 in
      let bar_h = 4 in
      let x0 = (px_w - bar_w) / 2 in
      let y0 = 4 in
      fill_rect
        bytes
        ~px_w
        ~px_h
        ~x:(x0 - 2)
        ~y:(y0 - 2)
        ~w:(bar_w + 4)
        ~h:(bar_h + 4)
        ~r:25
        ~g:25
        ~b:25 ;
      fill_rect
        bytes
        ~px_w
        ~px_h
        ~x:x0
        ~y:y0
        ~w:bar_w
        ~h:bar_h
        ~r:60
        ~g:60
        ~b:60 ;
      let filled = stamina * bar_w / max 1 max_stamina in
      (* Color segments: green (>50%), yellow (25-50%), red (<25%). *)
      let r, g, b =
        if stamina * 4 < max_stamina then (240, 60, 60) (* <25%: bright red *)
        else if stamina * 2 < max_stamina then (230, 200, 80)
          (* 25-50%: yellow *)
        else (140, 220, 90)
        (* >50%: green *)
      in
      fill_rect bytes ~px_w ~px_h ~x:x0 ~y:y0 ~w:filled ~h:bar_h ~r ~g ~b ;
      (* "LOW STAMINA!" label as small pixel dots to the right of the bar
         when stamina ≤ 3.  We draw a minimal brightness-coded pattern of
         single pixels spelling out the warning — a row of hot-red dots with
         a gap, then 3 exclamation dots below. *)
      if low then begin
        let lx = x0 + bar_w + 4 in
        let ly = y0 in
        (* 9 red dots in a row to represent the warning label. *)
        for dx = 0 to 8 do
          put_px bytes ~px_w ~px_h ~x:(lx + dx) ~y:ly ~r:255 ~g:60 ~b:60
        done ;
        (* Second row slightly dimmer for depth. *)
        for dx = 0 to 5 do
          put_px bytes ~px_w ~px_h ~x:(lx + dx) ~y:(ly + 2) ~r:200 ~g:40 ~b:40
        done
      end
    end

(* ---------- particles ---------- *)

let draw_particles bytes ~px_w ~px_h ~ox ~oy ~tile_w ~tile_h (s : Model.t) =
  Arcade_kit.Particles.iter s.particles ~f:(fun ~x ~y ~life01 ~hue ->
      let bx = ox + int_of_float (x *. float_of_int tile_w) in
      let by = oy + int_of_float (y *. float_of_int tile_h) in
      let r, g, b =
        match hue with
        | 1 ->
            (* bright ball-trail — white fading to pale cyan *)
            let v = int_of_float (life01 *. 255.0) in
            (v, min 255 (v + 10), min 255 (v + 20))
        | 3 ->
            (* water splash blue *)
            Arcade_kit.Hue.rgb Arcade_kit.Hue.ice ~life01
        | 6 ->
            (* sand puff *)
            Arcade_kit.Hue.rgb Arcade_kit.Hue.sand ~life01
        | 8 ->
            (* cup celebration *)
            Arcade_kit.Hue.rgb Arcade_kit.Hue.amber ~life01
        | _ ->
            (* default ball-trail green-white *)
            Arcade_kit.Hue.rgb Arcade_kit.Hue.grass ~life01
      in
      put_px bytes ~px_w ~px_h ~x:bx ~y:by ~r ~g ~b)

(* ---------- celebration stars ---------- *)

(* Draw a ring of 12 golden star dots expanding from radius 2 to 8
   over 0.5 s around the cup.  [celebration_t] counts down from 0.5. *)
let draw_celebration_stars bytes ~px_w ~px_h ~cx ~cy ~celebration_t =
  if celebration_t > 0.0 then begin
    (* frac in [0,1] where 0 = just cleared, 1 = 0.5s elapsed. *)
    let frac = 1.0 -. (celebration_t /. 0.5) in
    let radius = int_of_float (2.0 +. (6.0 *. frac)) in
    let brightness = int_of_float (255.0 *. celebration_t /. 0.5) in
    let n = 12 in
    for k = 0 to n - 1 do
      let a = Float.of_int k /. Float.of_int n *. 2.0 *. Float.pi in
      let x = cx + int_of_float (Float.of_int radius *. cos a) in
      let y = cy + int_of_float (Float.of_int radius *. sin a) in
      (* Bright gold star dot. *)
      put_px
        bytes
        ~px_w
        ~px_h
        ~x
        ~y
        ~r:brightness
        ~g:(min 255 (int_of_float (float_of_int brightness *. 0.85)))
        ~b:0 ;
      (* Small extra pixel for visibility. *)
      put_px bytes ~px_w ~px_h ~x:(x + 1) ~y ~r:brightness ~g:200 ~b:20 ;
      put_px bytes ~px_w ~px_h ~x ~y:(y + 1) ~r:brightness ~g:200 ~b:20
    done
  end

(* ---------- water penalty overlay ---------- *)

(* Draw "WATER +1" label as a bright red pixel-row-of-dots pattern above
   the splash position.  Simple approach: we just stamp small red discs
   at the penalty position; the HUD already shows the event text, so
   this is a secondary in-world visual cue. *)
let draw_water_penalty bytes ~px_w ~px_h ~ox ~oy ~tile_w ~tile_h ~game =
  if game.Model.water_penalty_t > 0.0 then begin
    let wx, wy = game.Model.water_penalty_pos in
    let px = ox + int_of_float (wx *. float_of_int tile_w) in
    let py = oy + int_of_float (wy *. float_of_int tile_h) in
    (* Alpha fade based on remaining timer. *)
    let alpha = Float.min 1.0 (game.Model.water_penalty_t /. 0.4) in
    let intensity = int_of_float (255.0 *. alpha) in
    (* Draw three bright red discs in a row above the splash. *)
    let y_off = py - tile_h - 2 in
    for dx = -4 to 4 do
      put_px bytes ~px_w ~px_h ~x:(px + dx) ~y:y_off ~r:intensity ~g:0 ~b:0
    done ;
    (* Second row one below. *)
    for dx = -3 to 3 do
      put_px
        bytes
        ~px_w
        ~px_h
        ~x:(px + dx)
        ~y:(y_off + 1)
        ~r:intensity
        ~g:30
        ~b:0
    done ;
    (* A dim halo. *)
    fill_disc
      bytes
      ~px_w
      ~px_h
      ~cx:px
      ~cy:y_off
      ~radius:2
      ~r:(min 255 (intensity / 2))
      ~g:0
      ~b:0
  end

(* ---------- wind gust whoosh marks ---------- *)

(* Draw 4 short diagonal "//" style marks to suggest a wind gust sweeping
   across the course.  Positions are deterministic from [gust_visual_t] so
   there is no per-frame allocation.  Color is dim grey (light/fading). *)
let draw_gust_whoosh bytes ~px_w ~px_h ~gust_visual_t =
  if gust_visual_t <= 0.0 then ()
  else begin
    let alpha = Float.min 1.0 (gust_visual_t /. 1.5) in
    let intensity = int_of_float (160.0 *. alpha) in
    (* Phase drives horizontal drift: marks slide rightward as the timer counts
       down.  We pre-compute 4 anchor points spread evenly across the frame. *)
    let phase = 1.0 -. alpha in
    (* 0.0 = just started, 1.0 = faded out *)
    let drift = int_of_float (phase *. float_of_int px_w *. 0.3) in
    let anchors =
      [|
        ((px_w * 1 / 5) + drift, px_h * 2 / 5);
        ((px_w * 2 / 5) + drift, px_h * 1 / 4);
        ((px_w * 3 / 5) + drift, px_h * 3 / 5);
        ((px_w * 4 / 5) + drift, px_h * 2 / 7);
      |]
    in
    (* Each mark is a short diagonal line segment (4 pixels long, slope 1:1). *)
    Array.iter
      (fun (ax, ay) ->
        for k = 0 to 3 do
          let x = ax + k in
          let y = ay - k in
          put_px bytes ~px_w ~px_h ~x ~y ~r:intensity ~g:intensity ~b:intensity ;
          (* Second adjacent pixel to make mark slightly thicker. *)
          put_px
            bytes
            ~px_w
            ~px_h
            ~x:(x + 1)
            ~y
            ~r:intensity
            ~g:intensity
            ~b:intensity
        done)
      anchors
  end

(* ---------- frame builder ---------- *)

let game_of_state (s : Model.t) =
  match s.mode with
  | Model.Aiming a -> Some a.a_game
  | Model.Powering p -> Some p.game
  | Model.In_flight f -> Some f.f_game
  | Model.Hole_clear c -> Some c.c_game
  | Model.Hole_preview hp -> Some hp.hp_game
  | _ -> None

let aim_of_state (s : Model.t) =
  match s.mode with
  | Model.Aiming a -> Some a.a_aim
  | Model.Powering p -> Some p.aim_angle
  | _ -> None

let meter_of_state (s : Model.t) =
  match s.mode with Model.Powering p -> Some p.meter01 | _ -> None

let build_frame (s : Model.t) ~px_w ~px_h ~time =
  let bytes = Bytes.make (px_w * px_h * 3) '\000' in
  match game_of_state s with
  | None ->
      (* Solid pastel sky for non-gameplay screens. *)
      for y = 0 to px_h - 1 do
        let t = float_of_int y /. float_of_int (max 1 px_h) in
        let r = int_of_float (60.0 +. (60.0 *. t)) in
        let g = int_of_float (90.0 +. (60.0 *. t)) in
        let b = int_of_float (120.0 +. (40.0 *. t)) in
        for x = 0 to px_w - 1 do
          put_px bytes ~px_w ~px_h ~x ~y ~r ~g ~b
        done
      done ;
      bytes
  | Some g ->
      let hole = g.Model.hole in
      (* Compute tile size that fits the layout into the framebuffer. *)
      let tile_w = max 2 (px_w / hole.Model.width) in
      let tile_h = max 2 ((px_h - 8) / hole.Model.height) in
      let used_w = tile_w * hole.Model.width in
      let used_h = tile_h * hole.Model.height in
      let ox = max 0 ((px_w - used_w) / 2) in
      let oy = max 0 (((px_h - used_h) / 2) - 1) in
      (* Use a cached static-terrain buffer to avoid recomputing the
         expensive per-pixel sin/cos hill_shade calls every frame.
         The cache is keyed on (px_w * px_h) so a terminal resize
         invalidates and rebuilds it automatically. *)
      let key = px_w * px_h in
      let bg =
        match g.Model.bg_cache with
        | Some (k, buf) when k = key -> buf
        | _ ->
            let buf = Bytes.make (px_w * px_h * 3) '\000' in
            draw_terrain_static buf ~px_w ~px_h ~hole ~tile_w ~tile_h ~ox ~oy ;
            g.Model.bg_cache <- Some (key, buf) ;
            buf
      in
      (* Blit the cached background into the working buffer. *)
      Bytes.blit bg 0 bytes 0 (Bytes.length bg) ;
      (* Repaint animated water tiles on top of the blitted background. *)
      draw_water_shimmer bytes ~px_w ~px_h ~hole ~tile_w ~tile_h ~ox ~oy ~time ;
      draw_cup
        bytes
        ~px_w
        ~px_h
        ~hole
        ~tile_w
        ~tile_h
        ~ox
        ~oy
        ~time
        ~aiming:(aim_of_state s <> None) ;
      draw_particles bytes ~px_w ~px_h ~ox ~oy ~tile_w ~tile_h s ;
      draw_ball bytes ~px_w ~px_h ~ox ~oy ~tile_w ~tile_h g.Model.ball ;
      (* Landing divot ring: fades out over 0.5s after the ball touches down. *)
      if g.Model.ball_land_t > 0.0 then begin
        let alpha = g.Model.ball_land_t /. 0.5 in
        let bx = ox + int_of_float (g.Model.ball.x *. float_of_int tile_w) in
        let by = oy + int_of_float (g.Model.ball.y *. float_of_int tile_h) in
        let radius =
          max 2 (tile_w + int_of_float ((1.0 -. alpha) *. float_of_int tile_w))
        in
        let intensity = int_of_float (alpha *. 200.0) in
        (* Colour by terrain: earthy brown on fairway/rough, yellow on sand,
           white on green. *)
        let landing_tile = Model.tile_at_ball g.Model.hole g.Model.ball in
        let dr, dg, db =
          match landing_tile with
          | Model.Sand -> (min 255 intensity, min 255 (intensity * 200 / 255), 0)
          | Model.Green | Model.Cup ->
              (intensity, min 255 intensity, min 255 intensity)
          | _ -> (min 255 intensity, min 255 (intensity * 150 / 255), 0)
        in
        ring_circle bytes ~px_w ~px_h ~cx:bx ~cy:by ~radius ~r:dr ~g:dg ~b:db
      end ;
      (* Celebration stars around the cup after hole-clear. *)
      (let cx_t, cy_t = hole.Model.cup in
       let cx = ox + (cx_t * tile_w) + (tile_w / 2) in
       let cy = oy + (cy_t * tile_h) + (tile_h / 2) in
       draw_celebration_stars
         bytes
         ~px_w
         ~px_h
         ~cx
         ~cy
         ~celebration_t:g.Model.celebration_t) ;
      (* Water penalty indicator above splash site. *)
      draw_water_penalty bytes ~px_w ~px_h ~ox ~oy ~tile_w ~tile_h ~game:g ;
      (* Wind indicator using display wind (includes active gust delta). *)
      let wind_x, wind_y = Model.display_wind g in
      let gust = Model.gust_active g in
      draw_wind_widget bytes ~px_w ~px_h ~ox ~oy ~wind_x ~wind_y ~time ~gust ;
      (* Wind gust whoosh marks: diagonal streaks visible when gust_visual_t > 0. *)
      draw_gust_whoosh bytes ~px_w ~px_h ~gust_visual_t:s.gust_visual_t ;
      (* Stamina bar overlay during a run. *)
      (match s.run with
      | Some r ->
          draw_stamina_bar
            bytes
            ~px_w
            ~px_h
            ~stamina:r.stamina
            ~max_stamina:r.max_stamina
            ~mode_t:s.mode_t
      | None -> ()) ;
      (* Aim arrow / power. The arrow length scales with the club's max
         speed so the player sees driver = long, putter = short. During
         Powering the length grows further with the meter and the colour
         shifts green→yellow→red. *)
      (match aim_of_state s with
      | Some angle ->
          let bx = ox + int_of_float (g.Model.ball.x *. float_of_int tile_w) in
          let by = oy + int_of_float (g.Model.ball.y *. float_of_int tile_h) in
          let club_factor =
            Model.club_max_speed g.Model.club /. 22.0 (* driver = 1.0 *)
          in
          let eagle_eye = Model.has_perk s Model.Eagle_eye in
          let bonus = if eagle_eye then 1.25 else 1.0 in
          let base_px = float_of_int (tile_w * 4) *. club_factor *. bonus in
          let length_px, meter_for_color =
            match s.mode with
            | Model.Powering p ->
                let extra = float_of_int tile_w *. 4.0 *. p.meter01 in
                (int_of_float (base_px +. extra), Some p.meter01)
            | _ -> (int_of_float base_px, None)
          in
          (* Trajectory ghost dots along the predicted flight path.
             For the Putter, we use more dots with tighter spacing to give
             precise putting feedback.  For other clubs, 5 evenly-spaced dots
             across the full expected shot distance. *)
          let max_spd = Model.effective_max_speed s g.Model.club in
          let meter_frac =
            match s.mode with
            | Model.Powering p -> Float.max 0.1 p.meter01
            | _ -> 1.0
          in
          (* Expected pixels to travel — same scaling as the arrow length but
             much longer (full shot), so we use actual speed × tile scale. *)
          let total_px = max_spd *. meter_frac *. float_of_int tile_w *. 0.9 in
          let cosa = cos angle in
          let sina = sin angle in
          let is_putter = g.Model.club = Model.Putter in
          let k_max = if is_putter then 10 else 5 in
          (* Putts travel shorter; use half the total_px for spacing. *)
          let ghost_range = if is_putter then total_px *. 0.5 else total_px in
          for k = 1 to k_max do
            let frac = float_of_int k /. float_of_int k_max in
            let dx = int_of_float (cosa *. ghost_range *. frac) in
            let dy = int_of_float (sina *. ghost_range *. frac) in
            let gx = bx + dx in
            let gy = by + dy in
            (* Dim ghost colour: muted version of the arrow base colour. *)
            let gr, gg, gb =
              arrow_color
                ~meter01:meter_for_color
                ~hot:eagle_eye
                ~club:(Some g.Model.club)
            in
            let dim = 0.35 *. (1.0 -. (frac *. 0.3)) in
            let gr' = int_of_float (float_of_int gr *. dim) in
            let gg' = int_of_float (float_of_int gg *. dim) in
            let gb' = int_of_float (float_of_int gb *. dim) in
            fill_disc
              bytes
              ~px_w
              ~px_h
              ~cx:gx
              ~cy:gy
              ~radius:1
              ~r:(min 255 gr')
              ~g:(min 255 gg')
              ~b:(min 255 gb')
          done ;
          draw_aim_arrow
            bytes
            ~px_w
            ~px_h
            ~bx
            ~by
            ~angle
            ~length_px
            ~meter01:meter_for_color
            ~hot:eagle_eye
            ~club:(Some g.Model.club)
      | None -> ()) ;
      (match meter_of_state s with
      | Some m -> draw_power_meter bytes ~px_w ~px_h ~meter01:m
      | None -> ()) ;
      (* flash overlay *)
      let alpha = Arcade_kit.Screen_fx.flash_alpha s.fx in
      if alpha > 0.01 then begin
        let add = int_of_float (alpha *. 80.0) in
        let n = Bytes.length bytes in
        let i = ref 0 in
        while !i < n do
          let r = Char.code (Bytes.get bytes !i) in
          Bytes.set bytes !i (Char.chr (min 255 (r + (add / 2)))) ;
          let g = Char.code (Bytes.get bytes (!i + 1)) in
          Bytes.set bytes (!i + 1) (Char.chr (min 255 (g + (add / 2)))) ;
          let b = Char.code (Bytes.get bytes (!i + 2)) in
          Bytes.set bytes (!i + 2) (Char.chr (min 255 (b + add))) ;
          i := !i + 3
        done
      end ;
      bytes

(* ---------- HUD / overlays ---------- *)

(* Distance estimate in mock yards — converts club max-speed × meter to a
   rough yardage so the HUD readout reads like real golf. *)
let yardage_of_club ?(meter01 = 1.0) club =
  int_of_float (Model.club_max_speed club *. meter01 *. 12.0)

(* Compass-style readout: angle in radians → degrees in [0, 360). *)
let degrees_of_angle a =
  let pi = Float.pi in
  let two_pi = 2.0 *. pi in
  let n = mod_float a two_pi in
  let n = if n < 0.0 then n +. two_pi else n in
  int_of_float (n *. 180.0 /. pi) mod 360

let render_run_hud (s : Model.t) =
  match s.run with
  | None -> ""
  | Some r ->
      let total = Array.length r.hole_seq in
      let pos = min (r.run_pos + 1) total in
      let next_is_boss = r.run_pos + 1 < total && (r.run_pos + 1) mod 3 = 2 in
      let stamina_bar_w = 18 in
      let filled =
        if r.max_stamina <= 0 then 0
        else r.stamina * stamina_bar_w / max 1 r.max_stamina
      in
      let bar =
        String.make filled '#'
        ^ String.make (max 0 (stamina_bar_w - filled)) '.'
      in
      let perks_glyphs =
        match r.active_perks with
        | [] -> ""
        | ps ->
            "  ["
            ^ String.concat " " (List.map Model.perk_glyph (List.rev ps))
            ^ "]"
      in
      Printf.sprintf
        "  Hole %d/%d%s  Stam [%s] %d/%d  $%d%s"
        pos
        total
        (if next_is_boss then " * BOSS NEXT" else "")
        bar
        r.stamina
        r.max_stamina
        s.coins
        perks_glyphs

let render_hud (s : Model.t) ~cols =
  match game_of_state s with
  | None ->
      W.themed_emphasis
        (pad_right "  MIAOU LINKS — Roguelite Greens  " ~width:cols)
  | Some g ->
      let aim_txt =
        match Model.aim_for_hud s with
        | None -> ""
        | Some a ->
            let deg = degrees_of_angle a in
            let dist_yd = Model.dist_to_cup_yards g in
            let power_txt =
              match s.mode with
              | Model.Powering p ->
                  let yd = yardage_of_club ~meter01:p.meter01 g.club in
                  Printf.sprintf "~%dyd" yd
              | _ ->
                  let max_yd = yardage_of_club g.club in
                  Printf.sprintf "MAX:%dyd" max_yd
            in
            Printf.sprintf
              "Aim:%03d°(%s,%s) DIST:%dyd  "
              deg
              (Model.club_label g.club)
              power_txt
              dist_yd
      in
      let run_part = render_run_hud s in
      (* Live par delta for the current hole. *)
      let par_delta = g.strokes - g.hole.par in
      let par_txt =
        if g.strokes = 0 then ""
        else if par_delta < 0 then Printf.sprintf " %+d" par_delta
        else if par_delta = 0 then " E"
        else Printf.sprintf " %+d" par_delta
      in
      (* Gust indicator in HUD. *)
      let gust_txt = if Model.gust_active g then " [GUST]" else "" in
      let txt =
        Printf.sprintf
          "  Stk %d%s  %sH%d Par%d  Best%+d  %s%s%s"
          g.strokes
          par_txt
          aim_txt
          (g.hole_idx + 1)
          g.hole.par
          s.best_under_par
          (if g.last_event_t > 0.0 then g.last_event else "")
          gust_txt
          run_part
      in
      W.themed_emphasis (pad_right txt ~width:cols)

let render_footer (s : Model.t) ~cols =
  let txt =
    match s.mode with
    | Model.Title -> "  Enter new run  ·  O classic tour  ·  Esc to launcher"
    | Model.New_run_intro -> "  Enter to begin  ·  Esc to title"
    | Model.In_shop _ -> "  Up/Down move  ·  Enter buy  ·  S/Esc start run"
    | Model.Course_select _ -> "  Up/Down pick hole  ·  Enter play  ·  Esc back"
    | Model.Hole_preview _ ->
        "  Space/Enter to skip preview  ·  auto-advances in 2s"
    | Model.Aiming _ ->
        "  Left/Right aim  ·  [/] fine aim  ·  c club  ·  Space power  ·  Esc \
         back"
    | Model.Powering _ ->
        "  Space swing  ·  Left/Right adjust aim  ·  [/] fine  ·  Esc cancel"
    | Model.In_flight _ -> "  ...ball in flight..."
    | Model.Hole_clear _ -> "  Enter for next hole  ·  Esc back"
    | Model.Perk_pick _ -> "  Up/Down pick perk  ·  Enter take  ·  Esc skip"
    | Model.Boss_intro _ -> "  ...prepare for the boss hole..."
    | Model.Run_complete _ -> "  Enter to title  ·  Coins persisted"
    | Model.Run_failed _ -> "  Enter to title  ·  Better luck next run"
    | Model.Card_summary _ -> "  Enter to title  ·  Esc to launcher"
  in
  W.themed_muted (pad_right txt ~width:cols)

(* ---------- non-gameplay screens ---------- *)

let render_run_status (s : Model.t) ~cols =
  match s.run with
  | None -> []
  | Some r ->
      let total = Array.length r.hole_seq in
      let completed = r.run_pos in
      let perk_glyphs =
        match r.active_perks with
        | [] -> ""
        | ps ->
            " ["
            ^ String.concat " " (List.map Model.perk_glyph (List.rev ps))
            ^ "]"
      in
      let status =
        Printf.sprintf
          "Run: %d/%d holes   Stam: %d/%d   $%d%s"
          completed
          total
          r.stamina
          r.max_stamina
          s.coins
          perk_glyphs
      in
      [W.themed_emphasis (center_in cols status); ""]

let render_title (s : Model.t) ~cols ~rows =
  let lines = ref [] in
  let push x = lines := x :: !lines in
  let blank () = push "" in
  (* Run status block shown at the top when a run is in progress. *)
  List.iter push (render_run_status s ~cols) ;
  blank () ;
  blank () ;
  push (W.themed_emphasis (center_in cols "MIAOU LINKS — Roguelite Greens")) ;
  push
    (W.themed_muted
       (center_in cols "a top-down golf roguelite — 9 random holes per run")) ;
  blank () ;
  push (center_in cols "═══════════════════════════════════") ;
  blank () ;
  push (center_in cols "Left/Right     -  Rotate aim") ;
  push (center_in cols "[ / ]          -  Fine-rotate aim") ;
  push (center_in cols "Space          -  Power meter / swing") ;
  push (center_in cols "c              -  Cycle club") ;
  push (center_in cols "Esc            -  Back") ;
  blank () ;
  push (W.themed_emphasis (center_in cols "Enter — New Run")) ;
  push (W.themed_muted (center_in cols "O — Classic 14-hole tour (tOur)")) ;
  blank () ;
  push (W.themed_muted (center_in cols (Printf.sprintf "Coins: $%d" s.coins))) ;
  let classic_txt =
    if s.best_under_par = 0 then "Classic best: no round completed"
    else if s.best_under_par > 0 then
      Printf.sprintf "Classic best: -%d under par" s.best_under_par
    else Printf.sprintf "Classic best: %d over par" (-s.best_under_par)
  in
  push (W.themed_muted (center_in cols classic_txt)) ;
  let run_txt =
    if s.best_run_score <= 0 then "Run best: no run completed"
    else
      Printf.sprintf
        "Run best: %d/9 holes  (%+d under par)"
        Model.holes_per_run
        s.best_run_score
  in
  push (W.themed_muted (center_in cols run_txt)) ;
  let blink = int_of_float (s.mode_t *. 2.0) mod 2 = 0 in
  if blink then push (W.themed_muted (center_in cols ">>> ready <<<"))
  else push "" ;
  let body = List.rev !lines in
  let pad_top = max 0 ((rows - List.length body) / 2) in
  let top = List.init pad_top (fun _ -> "") in
  String.concat "\n" (top @ body)

let render_shop (s : Model.t) (sd : Model.shop_data) ~cols ~rows =
  let lines = ref [] in
  let push x = lines := x :: !lines in
  push
    (W.themed_emphasis
       (center_in cols "PRE-RUN SHOP — spend coins for an edge")) ;
  push "" ;
  push
    (W.themed_emphasis (center_in cols (Printf.sprintf "Coins: $%d" s.coins))) ;
  push "" ;
  let n_options = Array.length sd.s_options in
  (* Items: indices 0 .. n_options-1; SKIP is index n_options. *)
  let n_total = n_options + 1 in
  Array.iteri
    (fun i (pi, cost) ->
      let selected = i = sd.s_cursor in
      let prefix = if selected then "▸ " else "  " in
      let label =
        if pi < 0 then "(SOLD)"
        else begin
          let can_afford = s.coins >= cost in
          let base =
            Printf.sprintf
              "%s — $%d   %s"
              (Model.perk_label Model.all_perks.(pi))
              cost
              (Model.perk_desc Model.all_perks.(pi))
          in
          if can_afford then base else base ^ "  [can't afford]"
        end
      in
      let line = center_in cols (prefix ^ label) in
      let styled =
        if selected then W.themed_emphasis line else W.themed_muted line
      in
      push styled)
    sd.s_options ;
  (* SKIP entry at the bottom of the list. *)
  let skip_selected = sd.s_cursor = n_total - 1 in
  let skip_prefix = if skip_selected then "▸ " else "  " in
  let skip_line = center_in cols (skip_prefix ^ "SKIP — start the run now") in
  let skip_styled =
    if skip_selected then W.themed_emphasis skip_line
    else W.themed_muted skip_line
  in
  push skip_styled ;
  push "" ;
  push
    (W.themed_muted
       (center_in cols "Enter to buy/skip  ·  S or Esc to start the run")) ;
  let body = List.rev !lines in
  let pad_top = max 0 ((rows - List.length body) / 2) in
  let top = List.init pad_top (fun _ -> "") in
  String.concat "\n" (top @ body)

let render_perk_pick (s : Model.t) (pp : Model.perk_pick_data) ~cols ~rows =
  let _ = s in
  let lines = ref [] in
  let push x = lines := x :: !lines in
  push (W.themed_emphasis (center_in cols "PICK A PERK")) ;
  push
    (W.themed_muted
       (center_in cols "between holes — gain a permanent edge for this run")) ;
  push "" ;
  Array.iteri
    (fun i pi ->
      let prefix = if i = pp.pp_cursor then "▸ " else "  " in
      if pi >= 0 then begin
        let p = Model.all_perks.(pi) in
        push
          (center_in
             cols
             (Printf.sprintf
                "%s%s — %s"
                prefix
                (Model.perk_label p)
                (Model.perk_desc p)))
      end)
    pp.pp_options ;
  push "" ;
  push
    (W.themed_muted
       (center_in cols "Enter to take  ·  Up/Down to choose  ·  Esc to skip")) ;
  let body = List.rev !lines in
  let pad_top = max 0 ((rows - List.length body) / 2) in
  let top = List.init pad_top (fun _ -> "") in
  String.concat "\n" (top @ body)

let render_boss_intro (s : Model.t) (bi : Model.boss_intro_data) ~cols ~rows =
  let _ = s in
  let lines = ref [] in
  let push x = lines := x :: !lines in
  let blink = int_of_float (bi.bi_t *. 6.0) mod 2 = 0 in
  push "" ;
  push "" ;
  push
    (W.themed_emphasis
       (center_in cols (if blink then "★  BOSS HOLE  ★" else "   BOSS HOLE   "))) ;
  push "" ;
  push (W.themed_emphasis (center_in cols bi.bi_name)) ;
  push "" ;
  push
    (W.themed_muted
       (center_in
          cols
          "Heavier wind. Hand-authored hazards. No second chances.")) ;
  let body = List.rev !lines in
  let pad_top = max 0 ((rows - List.length body) / 2) in
  let top = List.init pad_top (fun _ -> "") in
  String.concat "\n" (top @ body)

let render_run_complete (s : Model.t) (rc : Model.run_complete_data) ~cols ~rows
    =
  let lines = ref [] in
  let push x = lines := x :: !lines in
  push (W.themed_emphasis (center_in cols "RUN COMPLETE")) ;
  push "" ;
  (* NEW BEST banner: shown in gold when this run beats the stored best. *)
  let is_new_best =
    rc.rc_under_par > 0 && rc.rc_under_par >= s.best_run_score
  in
  if is_new_best then
    push ("\027[33m" ^ center_in cols "*** NEW PERSONAL BEST! ***" ^ "\027[0m")
  else begin
    let best_txt =
      if s.best_run_score <= 0 then "No previous run best"
      else Printf.sprintf "Best: %+d under par" s.best_run_score
    in
    push (W.themed_muted (center_in cols best_txt))
  end ;
  push "" ;
  push (center_in cols (Printf.sprintf "Total strokes: %d" rc.rc_final_score)) ;
  push (center_in cols (Printf.sprintf "Score: %+d under par" rc.rc_under_par)) ;
  push "" ;
  push
    (W.themed_emphasis
       (center_in cols (Printf.sprintf "+$%d coins earned" rc.rc_coins_earned))) ;
  push "" ;
  push (W.themed_muted (center_in cols "Enter to return to title")) ;
  let body = List.rev !lines in
  let pad_top = max 0 ((rows - List.length body) / 2) in
  let top = List.init pad_top (fun _ -> "") in
  String.concat "\n" (top @ body)

let render_run_failed (s : Model.t) (_rc : Model.run_complete_data) ~cols ~rows
    =
  let _ = s in
  let lines = ref [] in
  let push x = lines := x :: !lines in
  push (W.themed_emphasis (center_in cols "RUN FAILED")) ;
  push "" ;
  push (center_in cols "Out of stamina — your strokes ran out.") ;
  push "" ;
  push (W.themed_muted (center_in cols "Enter to return to title")) ;
  let body = List.rev !lines in
  let pad_top = max 0 ((rows - List.length body) / 2) in
  let top = List.init pad_top (fun _ -> "") in
  String.concat "\n" (top @ body)

let render_course_select (s : Model.t) ~cols ~rows ~cursor =
  let _ = s in
  let lines = ref [] in
  let push x = lines := x :: !lines in
  push (W.themed_emphasis (center_in cols "PICK A HOLE")) ;
  push "" ;
  for i = 0 to Courses.count - 1 do
    let _, par, _ = Courses.holes.(i) in
    let prefix = if i = cursor then "▸ " else "  " in
    let line = Printf.sprintf "%sHole %d   par %d" prefix (i + 1) par in
    push (center_in cols line)
  done ;
  push "" ;
  push
    (W.themed_muted
       (center_in
          cols
          (Printf.sprintf "course par total: %d" Courses.par_total))) ;
  let body = List.rev !lines in
  let pad_top = max 0 ((rows - List.length body) / 2) in
  let top = List.init pad_top (fun _ -> "") in
  String.concat "\n" (top @ body)

let render_hole_clear (s : Model.t) (g : Model.game) ~cols ~rows =
  let delta = g.strokes - g.hole.par in
  let rating_label =
    if delta <= -3 then Printf.sprintf "-3 ALBATROSS  (%+d)" delta
    else if delta = -2 then "-2 EAGLE"
    else if delta = -1 then "-1 BIRDIE"
    else if delta = 0 then "PAR"
    else Printf.sprintf "%+d OVER PAR" delta
  in
  let rating_color =
    if delta <= -3 then "\027[96m"
    else if delta = -2 then "\027[33m"
    else if delta = -1 then "\027[32m"
    else if delta = 0 then ""
    else "\027[31m"
  in
  let rating_reset = if rating_color = "" then "" else "\027[0m" in
  (* For the first 2 seconds, show just the big rating text. *)
  if s.mode_t < 2.0 then begin
    let lines = ref [] in
    let push x = lines := x :: !lines in
    push "" ;
    push "" ;
    push
      (W.themed_emphasis
         (center_in cols (Printf.sprintf "HOLE %d COMPLETE!" (g.hole_idx + 1)))) ;
    push "" ;
    (* Three large lines of the rating label for visual impact. *)
    let big_line = rating_color ^ center_in cols rating_label ^ rating_reset in
    push big_line ;
    push big_line ;
    push big_line ;
    push "" ;
    push
      (W.themed_muted
         (center_in
            cols
            (Printf.sprintf
               "Hole %d   Strokes: %d   Par: %d"
               (g.hole_idx + 1)
               g.strokes
               g.hole.par))) ;
    (* Chip-in banner in the initial big-rating display. *)
    if g.chip_in then push ("\027[93m" ^ center_in cols "CHIP-IN!" ^ "\027[0m") ;
    (* Eagle/albatross stamina restore banner during hole-clear. *)
    if s.eagle_stamina_restore_t > 0.0 then
      push ("\027[96m" ^ center_in cols "EAGLE! +1 Stamina" ^ "\027[0m") ;
    push "" ;
    push
      (W.themed_muted
         (center_in cols "Space to continue  ·  wait for scorecard")) ;
    let body = List.rev !lines in
    let pad_top = max 0 ((rows - List.length body) / 2) in
    let top = List.init pad_top (fun _ -> "") in
    String.concat "\n" (top @ body)
  end
  else begin
    let lines = ref [] in
    let push x = lines := x :: !lines in
    let was_hole_in_one = g.strokes = 1 in
    push "" ;
    push (W.themed_emphasis (center_in cols "HOLE COMPLETE!")) ;
    (* Hole-in-one special banner in bright gold. *)
    if was_hole_in_one then
      push ("\027[33m" ^ center_in cols "HOLE-IN-ONE!  +3 Stam  +$8" ^ "\027[0m")
    else push "" ;
    push
      (center_in
         cols
         (Printf.sprintf
            "Hole %d   Strokes: %d   Par: %d"
            (g.hole_idx + 1)
            g.strokes
            g.hole.par)) ;
    push "" ;
    (* Chip-in banner: ball flew into cup from height. *)
    if g.chip_in then push ("\027[93m" ^ center_in cols "CHIP-IN!" ^ "\027[0m") ;
    let score_line =
      rating_color ^ center_in cols rating_label ^ rating_reset
    in
    push score_line ;
    (* Eagle/albatross stamina restore banner. *)
    if s.eagle_stamina_restore_t > 0.0 then
      push ("\027[96m" ^ center_in cols "EAGLE! +1 Stamina" ^ "\027[0m") ;
    push "" ;
    (* Running scorecard for the current run or round. *)
    (match s.run with
    | Some r when r.run_pos > 0 ->
        push (W.themed_muted (center_in cols "— Scorecard this run —")) ;
        let played = min r.run_pos (Array.length r.hole_seq) in
        let run_total_delta = ref 0 in
        for i = 0 to played - 1 do
          let hidx = r.hole_seq.(i) in
          let _, hpar, _ = Courses.holes.(hidx) in
          let hstrokes = s.scorecard.(hidx) in
          let hdelta = hstrokes - hpar in
          run_total_delta := !run_total_delta + hdelta ;
          let marker =
            if hdelta < 0 then "-" else if hdelta = 0 then "=" else "+"
          in
          push
            (center_in
               cols
               (Printf.sprintf
                  "  Hole %d  par %d  strokes %d  %s"
                  (i + 1)
                  hpar
                  hstrokes
                  marker))
        done ;
        (* Run total under/over par. *)
        let run_under = - !run_total_delta in
        let total_lbl =
          if run_under > 0 then Printf.sprintf "%+d under par" run_under
          else if run_under = 0 then "even par"
          else Printf.sprintf "%d over par" (-run_under)
        in
        push
          (W.themed_emphasis
             (center_in cols (Printf.sprintf "Run total: %s" total_lbl)))
    | _ ->
        (* Classic round: show what's in scorecard so far. *)
        let any_played = Array.exists (fun n -> n > 0) s.scorecard in
        if any_played then begin
          push (W.themed_muted (center_in cols "— Scorecard so far —")) ;
          for i = 0 to g.hole_idx do
            let _, hpar, _ = Courses.holes.(i) in
            let hstrokes = s.scorecard.(i) in
            if hstrokes > 0 then begin
              let hdelta = hstrokes - hpar in
              let marker =
                if hdelta < 0 then "-" else if hdelta = 0 then "=" else "+"
              in
              push
                (center_in
                   cols
                   (Printf.sprintf
                      "  Hole %d  par %d  strokes %d  %s"
                      (i + 1)
                      hpar
                      hstrokes
                      marker))
            end
          done
        end) ;
    push "" ;
    push (W.themed_muted (center_in cols "Enter to continue · Esc to leave")) ;
    let body = List.rev !lines in
    let pad_top = max 0 ((rows - List.length body) / 2) in
    let top = List.init pad_top (fun _ -> "") in
    String.concat "\n" (top @ body)
  end

let render_summary (s : Model.t) (sd : Model.summary_data) ~cols ~rows =
  let _ = s in
  let lines = ref [] in
  let push x = lines := x :: !lines in
  push (W.themed_emphasis (center_in cols "ROUND COMPLETE")) ;
  push "" ;
  let total = Array.fold_left ( + ) 0 sd.scorecard in
  let under = Courses.par_total - total in
  push
    (center_in
       cols
       (Printf.sprintf "Total strokes: %d   (par %d)" total Courses.par_total)) ;
  let label =
    if under > 0 then Printf.sprintf "%+d under par" under
    else if under = 0 then "even par"
    else Printf.sprintf "%d over par" (-under)
  in
  push (center_in cols (Printf.sprintf "Result: %s" label)) ;
  push "" ;
  (* Header row. *)
  push (W.themed_muted (center_in cols "Hole  Par  Strokes   Delta  Cumul")) ;
  let cumul = ref 0 in
  for i = 0 to Array.length sd.scorecard - 1 do
    let _, par, _ = Courses.holes.(i) in
    let strokes = sd.scorecard.(i) in
    cumul := !cumul + strokes ;
    let delta = strokes - par in
    let delta_str =
      if delta < 0 then Printf.sprintf "%+d" delta
      else if delta = 0 then "E"
      else Printf.sprintf "+%d" delta
    in
    (* Colour: under par = cyan, over par = red, even = default. *)
    let color =
      if delta < 0 then "\027[96m" else if delta > 0 then "\027[31m" else ""
    in
    let reset = if color = "" then "" else "\027[0m" in
    let line =
      Printf.sprintf
        " %2d    %d      %2d      %s%s%s     %d"
        (i + 1)
        par
        strokes
        color
        (pad_right delta_str ~width:3)
        reset
        !cumul
    in
    push (center_in cols line)
  done ;
  push "" ;
  push
    (W.themed_muted
       (center_in
          cols
          (Printf.sprintf "best round so far: %+d" sd.best_under_par))) ;
  push (W.themed_muted (center_in cols "Enter to title · Esc to leave")) ;
  let body = List.rev !lines in
  let pad_top = max 0 ((rows - List.length body) / 2) in
  let top = List.init pad_top (fun _ -> "") in
  String.concat "\n" (top @ body)

(* ---------- hole preview ---------- *)

(* Draw a pulsing "TEE" marker at the tee position. *)
let draw_tee_marker bytes ~px_w ~px_h ~hole ~tile_w ~tile_h ~ox ~oy ~pulse =
  let tx, ty = hole.Model.tee in
  let cx = ox + (tx * tile_w) + (tile_w / 2) in
  let cy = oy + (ty * tile_h) + (tile_h / 2) in
  (* Bright white/green disc at tee. *)
  let gr = int_of_float (180.0 +. (pulse *. 60.0)) in
  fill_disc
    bytes
    ~px_w
    ~px_h
    ~cx
    ~cy
    ~radius:(max 2 (tile_w / 2))
    ~r:240
    ~g:gr
    ~b:100 ;
  (* Pulsing outer ring in lime green. *)
  let ring_r = max 3 (tile_w + int_of_float (pulse *. float_of_int tile_w)) in
  ring_circle bytes ~px_w ~px_h ~cx ~cy ~radius:ring_r ~r:100 ~g:255 ~b:100

(* Build a framebuffer frame for the hole preview: static terrain + cup
   pulse + tee marker, no ball. *)
let build_preview_frame (g : Model.game) ~px_w ~px_h ~time =
  let bytes = Bytes.make (px_w * px_h * 3) '\000' in
  let hole = g.Model.hole in
  let tile_w = max 2 (px_w / hole.Model.width) in
  let tile_h = max 2 ((px_h - 8) / hole.Model.height) in
  let used_w = tile_w * hole.Model.width in
  let used_h = tile_h * hole.Model.height in
  let ox = max 0 ((px_w - used_w) / 2) in
  let oy = max 0 (((px_h - used_h) / 2) - 1) in
  (* Static terrain — build a fresh buffer (no game cache available here). *)
  draw_terrain_static bytes ~px_w ~px_h ~hole ~tile_w ~tile_h ~ox ~oy ;
  (* Animated water. *)
  draw_water_shimmer bytes ~px_w ~px_h ~hole ~tile_w ~tile_h ~ox ~oy ~time ;
  (* Cup with stronger pulsing ring during preview. *)
  let pulse = 0.5 +. (0.5 *. sin (time *. 5.0)) in
  let cx_t, cy_t = hole.Model.cup in
  let cx = ox + (cx_t * tile_w) + (tile_w / 2) in
  let cy = oy + (cy_t * tile_h) + (tile_h / 2) in
  fill_disc
    bytes
    ~px_w
    ~px_h
    ~cx
    ~cy
    ~radius:(max 1 (tile_w / 3))
    ~r:30
    ~g:30
    ~b:30 ;
  let ring_r =
    max 2 (tile_w + 2 + int_of_float (pulse *. float_of_int (tile_w + 4)))
  in
  ring_circle
    bytes
    ~px_w
    ~px_h
    ~cx
    ~cy
    ~radius:ring_r
    ~r:(200 + int_of_float (pulse *. 55.0))
    ~g:(200 + int_of_float (pulse *. 55.0))
    ~b:80 ;
  (* Second inner ring for extra visual pop. *)
  ring_circle
    bytes
    ~px_w
    ~px_h
    ~cx
    ~cy
    ~radius:(max 2 (ring_r / 2))
    ~r:255
    ~g:(int_of_float (200.0 +. (pulse *. 55.0)))
    ~b:100 ;
  (* Flag on cup. *)
  let h_flag = tile_h * 2 in
  for dy = 1 to h_flag do
    put_px bytes ~px_w ~px_h ~x:cx ~y:(cy - dy) ~r:200 ~g:80 ~b:80
  done ;
  fill_rect
    bytes
    ~px_w
    ~px_h
    ~x:(cx + 1)
    ~y:(cy - h_flag)
    ~w:(tile_w + 1)
    ~h:(max 2 (tile_h / 2))
    ~r:230
    ~g:80
    ~b:80 ;
  (* TEE marker. *)
  draw_tee_marker bytes ~px_w ~px_h ~hole ~tile_w ~tile_h ~ox ~oy ~pulse ;
  bytes

let render_hole_preview (s : Model.t) (hp : Model.hole_preview_data) ~fb ~px_w
    ~px_h ~cols ~rows =
  let g = hp.hp_game in
  let bytes = build_preview_frame g ~px_w ~px_h ~time:s.mode_t in
  FB.blit fb ~src:bytes ~width:px_w ~height:px_h ;
  let frame_str =
    FB.render_with_mode
      fb
      ~mode:(Arcade_kit.Pixel_mode.resolve ~env_var:"MIAOU_LINKS_PIXEL_MODE" ())
      ~cols
      ~rows
  in
  (* Overlay text lines: hole/par info centred at top, club distances at bottom. *)
  let _, par, _ = Courses.holes.(g.hole_idx) in
  let header_line =
    W.themed_emphasis
      (center_in
         cols
         (Printf.sprintf "HOLE %d  —  PAR %d" (g.hole_idx + 1) par))
  in
  let wind_x, wind_y = g.hole.wind in
  let wind_mag = sqrt ((wind_x *. wind_x) +. (wind_y *. wind_y)) in
  let wind_dir =
    if wind_mag < 0.05 then "calm"
    else
      let deg = degrees_of_angle (atan2 wind_y wind_x) in
      let cardinal =
        if deg < 23 || deg >= 338 then "E"
        else if deg < 68 then "SE"
        else if deg < 113 then "S"
        else if deg < 158 then "SW"
        else if deg < 203 then "W"
        else if deg < 248 then "NW"
        else if deg < 293 then "N"
        else "NE"
      in
      Printf.sprintf "%.1f %s" wind_mag cardinal
  in
  (* CONDITIONS label: CALM / BREEZY / GUSTY with colour. *)
  let cond_label, cond_color =
    if wind_mag < 1.0 then ("CALM", "\027[32m")
    else if wind_mag <= 2.5 then ("BREEZY", "\027[33m")
    else ("GUSTY", "\027[31m")
  in
  let conditions_line =
    center_in
      cols
      (Printf.sprintf
         "CONDITIONS: %s%s\027[0m   Wind: %s"
         cond_color
         cond_label
         wind_dir)
  in
  let club_line =
    W.themed_muted
      (center_in
         cols
         (Printf.sprintf
            "Driver:~%dy  Iron:~%dy  Wedge:~%dy  Putter:~%dy"
            (yardage_of_club Model.Driver)
            (yardage_of_club Model.Iron)
            (yardage_of_club Model.Wedge)
            (yardage_of_club Model.Putter)))
  in
  (* Perk effects line — only shown during a roguelite run with active perks. *)
  let perk_line_opt =
    match s.run with
    | None -> None
    | Some r when r.Model.active_perks = [] -> None
    | Some r ->
        let descs =
          List.filter_map
            (fun p ->
              match (p : Model.perk) with
              | Model.Eagle_eye -> Some "Eagle Eye: arrow +25%, capture +0.85r"
              | Model.Power_swing -> Some "Power Swing: Driver +20%"
              | Model.Sand_legs -> Some "Sand Legs: sand 0.9 friction"
              | Model.Wind_breaker -> Some "Wind Breaker: wind halved"
              | Model.Putter_genius -> Some "Putter Genius: less spread"
              | Model.Stroke_saver -> Some "Stroke Saver: +1 stam/4 holes"
              | Model.Birdie_bonus -> Some "Birdie Bonus: +$2/birdie"
              | Model.Coin_magnet -> Some "Coin Magnet: +50% coins"
              | Model.Iron_will ->
                  if r.Model.iron_will_used then None
                  else Some "Iron Will: ignore 1st water"
              | Model.Storm_caller -> Some "Storm Caller: wind x1.8"
              | Model.Lucky_bounce -> Some "Lucky Bounce: 25% water redirect"
              | Model.Backspin -> Some "Backspin: reverses on green landing"
              | Model.Double_down -> Some "Double Down: birdie=coins x2"
              | Model.Rough_ready -> Some "Rough Ready: rough like fairway"
              | Model.Albatross_alert -> Some "Albatross!: 2+ under par +$4"
              | Model.Plus_one_stamina ->
                  None (* immediate effect, no ongoing *))
            r.Model.active_perks
        in
        if descs = [] then None
        else
          Some (W.themed_muted (center_in cols (String.concat "  ·  " descs)))
  in
  (* Replace the first line and last one or two lines of the frame with our
     overlays.  When there are active perk descriptions we replace the last
     two lines so both the club distances and the perk list are visible. *)
  let frame_lines = String.split_on_char '\n' frame_str in
  let n = List.length frame_lines in
  let with_header =
    match frame_lines with
    | _ :: rest -> header_line :: rest
    | [] -> [header_line]
  in
  let with_footer =
    if n <= 2 then with_header
    else
      let a = Array.of_list with_header in
      let len = Array.length a in
      (match perk_line_opt with
      | None ->
          (* No perk line: show conditions on last, club on second-to-last. *)
          if len >= 2 then begin
            a.(len - 2) <- club_line ;
            a.(len - 1) <- conditions_line
          end
          else a.(len - 1) <- conditions_line
      | Some perk_line ->
          (* With perk line: conditions on 3rd-from-last, club 2nd, perk last. *)
          if len >= 3 then begin
            a.(len - 3) <- conditions_line ;
            a.(len - 2) <- club_line ;
            a.(len - 1) <- perk_line
          end
          else if len >= 2 then begin
            a.(len - 2) <- club_line ;
            a.(len - 1) <- perk_line
          end
          else a.(len - 1) <- club_line) ;
      Array.to_list a
  in
  String.concat "\n" with_footer

(* ---------- top-level ---------- *)

let too_small_msg = "Resize terminal — needs at least 60×20"

let cap_frame_cols = 120

let cap_frame_rows = 32

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
      Arcade_kit.Pixel_mode.resolve ~env_var:"MIAOU_LINKS_PIXEL_MODE" ()
    in
    let px_x, px_y = mode_px_per_cell mode in
    let px_w = frame_cols * px_x in
    let px_h = frame_rows * px_y in
    let body =
      match s.mode with
      | Model.Title -> render_title s ~cols:frame_cols ~rows:frame_rows
      | Model.New_run_intro -> render_title s ~cols:frame_cols ~rows:frame_rows
      | Model.In_shop sd -> render_shop s sd ~cols:frame_cols ~rows:frame_rows
      | Model.Course_select cs ->
          render_course_select
            s
            ~cols:frame_cols
            ~rows:frame_rows
            ~cursor:cs.cursor
      | Model.Card_summary sd ->
          render_summary s sd ~cols:frame_cols ~rows:frame_rows
      | Model.Hole_preview hp ->
          render_hole_preview
            s
            hp
            ~fb
            ~px_w
            ~px_h
            ~cols:frame_cols
            ~rows:frame_rows
      | Model.Hole_clear c ->
          render_hole_clear s c.c_game ~cols:frame_cols ~rows:frame_rows
      | Model.Perk_pick pp ->
          render_perk_pick s pp ~cols:frame_cols ~rows:frame_rows
      | Model.Boss_intro bi ->
          render_boss_intro s bi ~cols:frame_cols ~rows:frame_rows
      | Model.Run_complete rc ->
          render_run_complete s rc ~cols:frame_cols ~rows:frame_rows
      | Model.Run_failed rc ->
          render_run_failed s rc ~cols:frame_cols ~rows:frame_rows
      | Model.Aiming _ | Model.Powering _ | Model.In_flight _ ->
          let bytes = build_frame s ~px_w ~px_h ~time:s.mode_t in
          FB.blit fb ~src:bytes ~width:px_w ~height:px_h ;
          FB.render_with_mode fb ~mode ~cols:frame_cols ~rows:frame_rows
    in
    let header = render_hud s ~cols:frame_cols in
    let footer = render_footer s ~cols:frame_cols in
    String.concat "\n" [header; body; footer]
