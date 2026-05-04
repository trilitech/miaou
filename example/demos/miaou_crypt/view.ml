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

let blend_px bytes ~px_w ~px_h ~x ~y ~r ~g ~b ~alpha =
  if x >= 0 && x < px_w && y >= 0 && y < px_h then begin
    let off = ((y * px_w) + x) * 3 in
    let r0 = Char.code (Bytes.get bytes off) in
    let g0 = Char.code (Bytes.get bytes (off + 1)) in
    let b0 = Char.code (Bytes.get bytes (off + 2)) in
    let blend a b =
      int_of_float
        ((float_of_int a *. (1.0 -. alpha)) +. (float_of_int b *. alpha))
    in
    Bytes.set bytes off (Char.chr (max 0 (min 255 (blend r0 r)))) ;
    Bytes.set bytes (off + 1) (Char.chr (max 0 (min 255 (blend g0 g)))) ;
    Bytes.set bytes (off + 2) (Char.chr (max 0 (min 255 (blend b0 b))))
  end

let fill_rect bytes ~px_w ~px_h ~x ~y ~w ~h ~r ~g ~b =
  for dy = 0 to h - 1 do
    for dx = 0 to w - 1 do
      put_px bytes ~px_w ~px_h ~x:(x + dx) ~y:(y + dy) ~r ~g ~b
    done
  done

(* ---------- ceiling + floor gradient ---------- *)

let draw_floor_ceiling bytes ~px_w ~px_h ~torch_timer =
  let half = px_h / 2 in
  let warm = if torch_timer > 0.0 then 1.0 else 0.0 in
  for y = 0 to half - 1 do
    let t = 1.0 -. (float_of_int y /. float_of_int (max 1 half)) in
    let r = int_of_float (10.0 +. (24.0 *. t) +. (warm *. 8.0 *. t)) in
    let g = int_of_float (15.0 +. (32.0 *. t)) in
    let b = int_of_float (28.0 +. (52.0 *. t) -. (warm *. 18.0 *. t)) in
    for x = 0 to px_w - 1 do
      put_px bytes ~px_w ~px_h ~x ~y ~r ~g ~b
    done
  done ;
  for y = half to px_h - 1 do
    let t = float_of_int (y - half) /. float_of_int (max 1 (px_h - half)) in
    let r = int_of_float (24.0 +. (38.0 *. t) +. (warm *. 12.0 *. t)) in
    let g = int_of_float (16.0 +. (22.0 *. t)) in
    let b = int_of_float (10.0 +. (10.0 *. t) -. (warm *. 4.0 *. t)) in
    (* Subtle floor tile pattern: every ~4 px row a slight darker band. *)
    let row_band = if y mod 8 = 0 then -3 else 0 in
    for x = 0 to px_w - 1 do
      put_px
        bytes
        ~px_w
        ~px_h
        ~x
        ~y
        ~r:(max 0 (r + row_band))
        ~g:(max 0 (g + row_band))
        ~b:(max 0 (b + row_band))
    done
  done

(* ---------- wall slices ---------- *)

let slice_height ~px_h ~perp_dist =
  let h = float_of_int px_h /. Float.max 0.001 perp_dist in
  int_of_float h

(* Symmetric slice bounds — guarantees adjacent columns produce
   identical seams for matching distances. *)
let slice_bounds ~px_h ~perp_dist =
  let h = slice_height ~px_h ~perp_dist in
  let half = px_h / 2 in
  let top = max 0 (half - (h / 2)) in
  let bot = min px_h (half + ((h + 1) / 2)) in
  (top, bot, h)

let draw_wall_slice bytes ~px_w ~px_h ~col ~hit ~torch_timer ~floor_no =
  let top, bot, h = slice_bounds ~px_h ~perp_dist:hit.Raycast.perp_dist in
  let h = max 1 h in
  for y = top to bot - 1 do
    let row_t = float_of_int (y - top) /. float_of_int h in
    let r, g, b = Raycast.wall_rgb hit ~row_t ~torch_timer ~floor_no in
    (* Additive torch warmth: shift wall pixels toward orange when lit. *)
    let r, g, b =
      if torch_timer > 0.0 then
        (min 255 (r + 30), min 255 (g + 15), max 0 (b - 20))
      else (r, g, b)
    in
    put_px bytes ~px_w ~px_h ~x:col ~y ~r ~g ~b
  done

let render_column (s : Model.t) bytes ~px_w ~px_h ~col ~n_cols ~depth =
  let dx, dy = Raycast.column_ray s.player ~col ~n_cols in
  let hit = Raycast.cast_ray s.floor ~px:s.player.x ~py:s.player.y ~dx ~dy in
  match hit with
  | None -> depth.(col) <- Raycast.max_view_distance
  | Some h ->
      draw_wall_slice
        bytes
        ~px_w
        ~px_h
        ~col
        ~hit:h
        ~torch_timer:s.player.torch_timer
        ~floor_no:s.player.floor ;
      depth.(col) <- h.perp_dist

(* ---------- world projection ---------- *)

let project_world_point (player : Model.player) x y =
  let rx = x -. player.x in
  let ry = y -. player.y in
  let fdx = float_of_int player.facing.dx in
  let fdy = float_of_int player.facing.dy in
  let pdx, pdy = Raycast.camera_plane player.facing in
  let det = (pdx *. fdy) -. (pdy *. fdx) in
  if Float.abs det < 0.0001 then None
  else
    let inv = 1.0 /. det in
    let t_x = inv *. ((fdy *. rx) -. (fdx *. ry)) in
    let t_y = inv *. ((-.pdy *. rx) +. (pdx *. ry)) in
    if t_y <= 0.05 then None else Some (t_x, t_y)

(* ---------- pickup decals ---------- *)

let draw_floor_marks bytes ~px_w ~px_h ~depth (s : Model.t) =
  let f = s.floor in
  for ty = 0 to f.height - 1 do
    for tx = 0 to f.width - 1 do
      let t = Model.tile_at f ~x:tx ~y:ty in
      let mark =
        match t with
        | Model.Key -> Some (240, 220, 80)
        | Model.Stairs -> Some (110, 220, 230)
        | Model.Exit -> Some (255, 160, 240)
        | Model.Potion -> Some (90, 240, 140)
        | Model.Torch -> Some (255, 180, 80)
        | Model.Sword -> Some (220, 240, 255)
        | Model.Map_scroll -> Some (160, 230, 255)
        | Model.Ring_of_speed -> Some (255, 255, 80)
        | Model.Armor -> Some (160, 220, 255)
        | Model.Speed_scroll -> Some (200, 255, 180)
        | Model.Healing_rune -> Some (120, 255, 160)
        | Model.Bomb_scroll -> Some (255, 140, 40)
        | _ -> None
      in
      match mark with
      | None -> ()
      | Some (mr, mg, mb) -> (
          let cx = float_of_int tx +. 0.5 in
          let cy = float_of_int ty +. 0.5 in
          match project_world_point s.player cx cy with
          | None -> ()
          | Some (cam_x, cam_z) ->
              if cam_z > Raycast.max_view_distance then ()
              else
                let n_cols = px_w in
                let screen_x =
                  int_of_float
                    (float_of_int n_cols /. 2.0 *. (1.0 +. (cam_x /. cam_z)))
                in
                let h = int_of_float (float_of_int px_h /. cam_z) in
                let half = px_h / 2 in
                let cy_screen = half + (h / 2) - max 1 (h / 8) in
                let size = max 1 (h / 12) in
                (* Pulsing brightness for animation interest. *)
                let pulse =
                  0.65 +. (0.35 *. (0.5 +. (0.5 *. Float.sin (s.anim_t *. 4.0))))
                in
                let mr = int_of_float (float_of_int mr *. pulse) in
                let mg = int_of_float (float_of_int mg *. pulse) in
                let mb = int_of_float (float_of_int mb *. pulse) in
                let left = screen_x - size in
                let right = screen_x + size in
                for x = max 0 left to min (px_w - 1) right do
                  if cam_z < depth.(x) then
                    for dy = -size to size do
                      let yy = cy_screen + dy in
                      let dist = abs (x - screen_x) + abs dy in
                      if dist <= size then
                        put_px bytes ~px_w ~px_h ~x ~y:yy ~r:mr ~g:mg ~b:mb
                    done
                done)
    done
  done

(* ---------- monsters ---------- *)

(* Monster silhouette. Returns whether the local UV (lx, ly) is inside
   the per-kind shape. [frame] is 0 or 1 for the 2-frame walk cycle. *)
let monster_pixel ~kind ~lx ~ly ~frame =
  match (kind : Model.monster_kind) with
  | Spider ->
      let cx = lx -. 0.5 in
      let cy = ly -. 0.5 in
      let r2 = (cx *. cx) +. (cy *. cy) in
      let body = r2 < 0.10 in
      (* Eight legs, splayed; alternate splay in walk frames. *)
      let leg_offset = if frame = 0 then 0.05 else -0.05 in
      let leg =
        let dy = ly -. 0.55 in
        Float.abs dy < 0.04
        && (Float.abs (lx -. (0.20 +. leg_offset)) < 0.08
           || Float.abs (lx -. (0.40 +. leg_offset)) < 0.05
           || Float.abs (lx -. (0.60 -. leg_offset)) < 0.05
           || Float.abs (lx -. (0.80 -. leg_offset)) < 0.08)
      in
      body || leg
  | Skeleton ->
      let body = lx > 0.32 && lx < 0.68 && ly > 0.28 && ly < 0.92 in
      let head =
        let cx = lx -. 0.5 in
        let cy = ly -. 0.18 in
        (cx *. cx) +. (cy *. cy) < 0.012
      in
      (* Arms swing in the walk frame. *)
      let arm_swing = if frame = 0 then 0.06 else -0.06 in
      let arm_l =
        Float.abs (ly -. 0.50) < 0.04
        && lx > 0.22 +. arm_swing
        && lx < 0.32 +. arm_swing
      in
      let arm_r =
        Float.abs (ly -. 0.50) < 0.04
        && lx > 0.68 -. arm_swing
        && lx < 0.78 -. arm_swing
      in
      body || head || arm_l || arm_r
  | Bat ->
      let dy_v = Float.abs (ly -. 0.50 +. if frame = 0 then 0.0 else 0.04) in
      let dx_v = Float.abs (lx -. 0.5) in
      (* Wings flap: frame 0 wide, frame 1 narrow. *)
      let wing_w = if frame = 0 then 0.5 else 0.4 in
      dy_v < 0.10 && dx_v < wing_w -. dy_v
  | Wraith ->
      (* Drifting wisp shape — taller than spider, alpha-blended. *)
      let cx = lx -. 0.5 in
      let cy = ly -. 0.5 in
      let r2 = (cx *. cx) +. (cy *. cy *. 0.6) in
      let body = r2 < 0.20 in
      let tail =
        ly > 0.7
        && Float.abs (lx -. 0.5 +. if frame = 0 then 0.05 else -0.05) < 0.12
      in
      body || tail
  | Lich ->
      (* Tall robed figure with a wide skirt. *)
      let robe =
        ly > 0.30 && lx > 0.20 +. (ly *. 0.05) && lx < 0.80 -. (ly *. 0.05)
      in
      let head =
        let cx = lx -. 0.5 in
        let cy = ly -. 0.18 in
        (cx *. cx) +. (cy *. cy) < 0.025
      in
      let arm_swing = if frame = 0 then 0.04 else -0.04 in
      let staff =
        lx > 0.78 +. arm_swing
        && lx < 0.85 +. arm_swing
        && ly > 0.20 && ly < 0.90
      in
      robe || head || staff
  | Dragon ->
      (* Massive: filled wide silhouette plus wings. *)
      let body = lx > 0.20 && lx < 0.80 && ly > 0.28 && ly < 0.92 in
      let head =
        let cx = lx -. 0.5 in
        let cy = ly -. 0.18 in
        (cx *. cx) +. (cy *. cy) < 0.045
      in
      let wing_off = if frame = 0 then 0.0 else -0.05 in
      let wing_l =
        Float.abs (ly -. 0.45 +. wing_off) < 0.08 && lx > 0.05 && lx < 0.30
      in
      let wing_r =
        Float.abs (ly -. 0.45 +. wing_off) < 0.08 && lx > 0.70 && lx < 0.95
      in
      body || head || wing_l || wing_r
  | Archer ->
      (* Slim figure with a bow drawn — arm extended sideways. *)
      let body = lx > 0.38 && lx < 0.62 && ly > 0.30 && ly < 0.88 in
      let head =
        let cx = lx -. 0.5 in
        let cy = ly -. 0.18 in
        (cx *. cx) +. (cy *. cy) < 0.010
      in
      (* Draw arm pointing forward in frame 0, pulled back in frame 1. *)
      let arm_ext = if frame = 0 then 0.0 else 0.06 in
      let arm =
        Float.abs (ly -. 0.45) < 0.04
        && lx > 0.62 +. arm_ext
        && lx < 0.90 +. arm_ext
      in
      (* Arrow nock: tiny dot at the bowstring. *)
      let arrow_tip = Float.abs (ly -. 0.45) < 0.02 && lx > 0.86 && lx < 0.96 in
      body || head || arm || arrow_tip
  | Zombie ->
      (* Chunky shambling silhouette: wide body, hunched shoulders, arms
         slightly forward as if reaching.  Walk cycle tilts sideways. *)
      let body = lx > 0.25 && lx < 0.75 && ly > 0.30 && ly < 0.90 in
      let head =
        let cx = lx -. 0.5 in
        let cy = ly -. 0.15 in
        (cx *. cx) +. (cy *. cy) < 0.020
      in
      (* Outstretched arms: alternate forward reach between frames. *)
      let arm_reach = if frame = 0 then 0.0 else 0.08 in
      let arm_l =
        Float.abs (ly -. 0.48) < 0.04
        && lx > 0.06 -. arm_reach
        && lx < 0.26 -. arm_reach
      in
      let arm_r =
        Float.abs (ly -. 0.48) < 0.04
        && lx > 0.74 +. arm_reach
        && lx < 0.94 +. arm_reach
      in
      body || head || arm_l || arm_r

let monster_palette = function
  | Model.Spider -> (210, 60, 60)
  | Model.Skeleton -> (215, 215, 200)
  | Model.Bat -> (90, 60, 110)
  | Model.Wraith -> (180, 220, 255)
  | Model.Lich -> (180, 80, 220)
  | Model.Dragon -> (240, 80, 50)
  | Model.Archer -> (140, 200, 100)
  | Model.Zombie -> (60, 120, 60)

(* Width-multiplier per kind so dragon/lich fill more of the corridor. *)
let monster_size_mul = function
  | Model.Dragon -> 1.4
  | Model.Lich -> 1.1
  | Model.Bat -> 0.7
  | Model.Archer -> 0.85
  | Model.Zombie -> 1.15
  | _ -> 1.0

let draw_monster bytes ~px_w ~px_h ~depth ~anim_t (player : Model.player)
    (m : Model.monster) =
  let mx = m.rx in
  let my = m.ry in
  match project_world_point player mx my with
  | None -> ()
  | Some (cam_x, cam_z) ->
      let n_cols = px_w in
      let screen_x =
        int_of_float (float_of_int n_cols /. 2.0 *. (1.0 +. (cam_x /. cam_z)))
      in
      let size_mul = monster_size_mul m.kind in
      let h = int_of_float (float_of_int px_h /. cam_z *. size_mul) in
      let w = int_of_float (float_of_int px_h /. cam_z *. size_mul *. 0.6) in
      if h <= 0 || w <= 0 then ()
      else
        let half = px_h / 2 in
        let top = max 0 (half - (h / 2)) in
        let bot = min px_h (half + (h / 2)) in
        let left = screen_x - (w / 2) in
        let right = screen_x + (w / 2) in
        let r0, g0, b0 = monster_palette m.kind in
        let mul =
          let t =
            Float.min Raycast.max_view_distance cam_z
            /. Raycast.max_view_distance
          in
          1.0 -. (0.7 *. t)
        in
        (* Hit-flash brightens the sprite for ~0.18 s after a hit. *)
        let flash_boost = if m.hit_flash > 0.0 then 80 else 0 in
        let r0 =
          min 255 (int_of_float (float_of_int r0 *. mul) + flash_boost)
        in
        let g0 =
          min 255 (int_of_float (float_of_int g0 *. mul) + flash_boost)
        in
        let b0 =
          min 255 (int_of_float (float_of_int b0 *. mul) + flash_boost)
        in
        let frame = int_of_float (anim_t *. 4.0) mod 2 in
        let alpha_kind = match m.kind with Model.Wraith -> 0.55 | _ -> 1.0 in
        for x = max 0 left to min (px_w - 1) right do
          if x >= 0 && x < px_w && cam_z < depth.(x) then begin
            let lx = float_of_int (x - left) /. float_of_int (max 1 w) in
            for y = top to bot - 1 do
              let ly = float_of_int (y - top) /. float_of_int (max 1 h) in
              if monster_pixel ~kind:m.kind ~lx ~ly ~frame then begin
                if alpha_kind < 1.0 then
                  blend_px
                    bytes
                    ~px_w
                    ~px_h
                    ~x
                    ~y
                    ~r:r0
                    ~g:g0
                    ~b:b0
                    ~alpha:alpha_kind
                else put_px bytes ~px_w ~px_h ~x ~y ~r:r0 ~g:g0 ~b:b0
              end
            done
          end
        done ;
        (* Alert "!" sprite: draw a bright yellow exclamation mark above the
           monster's head for 1.5 s after first alert.  Uses the pixel-digit
           font scaled to 2× for visibility. *)
        if m.alert_display_t > 0.0 && cam_z < Raycast.max_view_distance then begin
          let ay = max 0 (top - 8) in
          let ax = screen_x - 1 in
          let fade = m.alert_display_t /. 1.5 in
          let ar = int_of_float (255.0 *. fade) in
          let ag = int_of_float (240.0 *. fade) in
          let ab = 0 in
          (* Draw a compact "!" using two pixel columns: body and dot. *)
          for dy = 0 to 4 do
            let yy = ay + dy in
            if yy >= 0 && yy < px_h then begin
              if dy < 3 then begin
                put_px bytes ~px_w ~px_h ~x:ax ~y:yy ~r:ar ~g:ag ~b:ab ;
                put_px bytes ~px_w ~px_h ~x:(ax + 1) ~y:yy ~r:ar ~g:ag ~b:ab
              end (* gap at dy=3, dot at dy=4 *)
              else if dy = 4 then begin
                put_px bytes ~px_w ~px_h ~x:ax ~y:yy ~r:ar ~g:ag ~b:ab ;
                put_px bytes ~px_w ~px_h ~x:(ax + 1) ~y:yy ~r:ar ~g:ag ~b:ab
              end
            end
          done
        end

(* ---------- boss projectiles ---------- *)

let draw_boss_projectiles bytes ~px_w ~px_h ~depth (s : Model.t) =
  Array.iter
    (fun (m : Model.monster) ->
      if m.alive && m.proj_active then
        match project_world_point s.player m.proj_x m.proj_y with
        | None -> ()
        | Some (cam_x, cam_z) ->
            if cam_z > Raycast.max_view_distance then ()
            else
              let n_cols = px_w in
              let sx =
                int_of_float
                  (float_of_int n_cols /. 2.0 *. (1.0 +. (cam_x /. cam_z)))
              in
              let half = px_h / 2 in
              let h = int_of_float (float_of_int px_h /. cam_z) in
              let sy = half + (h / 8) in
              let r = max 2 (h / 16) in
              for dx = -r to r do
                for dy = -r to r do
                  if (dx * dx) + (dy * dy) <= r * r then begin
                    let x = sx + dx in
                    let y = sy + dy in
                    if x >= 0 && x < px_w && cam_z < depth.(x) then
                      put_px bytes ~px_w ~px_h ~x ~y ~r:255 ~g:140 ~b:60
                  end
                done
              done)
    s.monsters

(* ---------- archer arrows ---------- *)

(* Grid-level projectiles from Archer monsters: render as a bright cyan
   dot at the tile centre. *)
let draw_archer_projectiles bytes ~px_w ~px_h ~depth (s : Model.t) =
  Array.iter
    (fun (proj : Model.projectile) ->
      if proj.alive then
        let wx = float_of_int proj.px +. 0.5 in
        let wy = float_of_int proj.py +. 0.5 in
        match project_world_point s.player wx wy with
        | None -> ()
        | Some (cam_x, cam_z) ->
            if cam_z > Raycast.max_view_distance then ()
            else
              let sx =
                int_of_float
                  (float_of_int px_w /. 2.0 *. (1.0 +. (cam_x /. cam_z)))
              in
              let half = px_h / 2 in
              let h = int_of_float (float_of_int px_h /. cam_z) in
              let sy = half + (h / 8) in
              let r = max 1 (h / 20) in
              for dx = -r to r do
                for dy = -r to r do
                  if (dx * dx) + (dy * dy) <= r * r then begin
                    let x = sx + dx in
                    let y = sy + dy in
                    if x >= 0 && x < px_w && cam_z < depth.(x) then
                      put_px bytes ~px_w ~px_h ~x ~y ~r:200 ~g:255 ~b:220
                  end
                done
              done)
    s.projectiles

(* ---------- particles ---------- *)

let draw_particles bytes ~px_w ~px_h ~depth (s : Model.t) =
  Arcade_kit.Particles.iter s.particles ~f:(fun ~x ~y ~life01 ~hue:_ ->
      let r, g, b = Arcade_kit.Hue.rgb Arcade_kit.Hue.lava ~life01 in
      match project_world_point s.player x y with
      | None -> ()
      | Some (cam_x, cam_z) ->
          if cam_z > Raycast.max_view_distance then ()
          else
            let n_cols = px_w in
            let sx =
              int_of_float
                (float_of_int n_cols /. 2.0 *. (1.0 +. (cam_x /. cam_z)))
            in
            let half = px_h / 2 in
            let h = int_of_float (float_of_int px_h /. cam_z) in
            let sy = half - (h / 6) in
            if sx >= 0 && sx < px_w && cam_z < depth.(sx) then
              put_px bytes ~px_w ~px_h ~x:sx ~y:sy ~r ~g ~b)

(* ---------- 3×5 pixel-digit font (popups) ---------- *)

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
  | '-' -> [(0, 2); (1, 2); (2, 2)]
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

(* Project a popup's world coords to the screen, then stamp the text
   in pixel coords. Popups float upward as their life decays. *)
let draw_popups bytes ~px_w ~px_h ~depth (s : Model.t) =
  Array.iter
    (fun (p : Model.popup) ->
      if p.alive then
        match project_world_point s.player p.wx p.wy with
        | None -> ()
        | Some (cam_x, cam_z) ->
            if cam_z > Raycast.max_view_distance then ()
            else
              let n_cols = px_w in
              let sx =
                int_of_float
                  (float_of_int n_cols /. 2.0 *. (1.0 +. (cam_x /. cam_z)))
              in
              let half = px_h / 2 in
              let h = int_of_float (float_of_int px_h /. cam_z) in
              let life01 = if p.life0 > 0.0 then p.life /. p.life0 else 0.0 in
              (* Float upward over lifetime. *)
              let float_up = int_of_float ((1.0 -. life01) *. 12.0) in
              let sy = half - (h / 4) - float_up in
              (* Fade colour as life drops. *)
              let fade = int_of_float (life01 *. 255.0) in
              let r = min 255 (p.r * fade / 255) in
              let g = min 255 (p.g * fade / 255) in
              let b = min 255 (p.b * fade / 255) in
              if sx >= 0 && sx < px_w && cam_z <= depth.(sx) +. 0.3 then
                draw_text_pixels
                  bytes
                  ~px_w
                  ~px_h
                  ~x:(sx - 5)
                  ~y:sy
                  ~text:p.text
                  ~r
                  ~g
                  ~b)
    s.popups

(* ---------- attack flash: slash X overlay + weapon swing ---------- *)

(* Draw a large bright "X" (two diagonals) centred at (cx, cy) using
   thick lines, faded by [alpha]. Size is [half_sz] pixels per arm. *)
let draw_slash_x bytes ~px_w ~px_h ~cx ~cy ~half_sz ~alpha =
  let a = int_of_float (alpha *. 255.0) in
  if a <= 0 then ()
  else
    for i = -half_sz to half_sz do
      let x1 = cx + i in
      let y1 = cy + i in
      let x2 = cx + i in
      let y2 = cy - i in
      (* 3-pixel thick by also painting the neighbouring row/col. *)
      List.iter
        (fun (xx, yy) ->
          if xx >= 0 && xx < px_w && yy >= 0 && yy < px_h then
            blend_px bytes ~px_w ~px_h ~x:xx ~y:yy ~r:255 ~g:255 ~b:255 ~alpha)
        [
          (x1, y1);
          (x1 + 1, y1);
          (x1, y1 + 1);
          (x2, y2);
          (x2 + 1, y2);
          (x2, y2 - 1);
        ]
    done

(* Draw a weapon-swing arc: 5 bright dashes sweeping from the right
   edge of centre outward, at varying y-offsets. Simulates a horizontal
   slash from right to left across the player's view. *)
let draw_weapon_swing bytes ~px_w ~px_h ~alpha =
  if alpha <= 0.01 then ()
  else
    let cx = px_w / 2 in
    let cy = px_h / 2 in
    (* Five dash segments at different vertical offsets. *)
    let segments =
      [
        (cx + 5, cy - 8, 14);
        (cx + 3, cy - 4, 18);
        (cx + 1, cy, 20);
        (cx + 3, cy + 4, 18);
        (cx + 5, cy + 8, 14);
      ]
    in
    List.iter
      (fun (sx, sy, len) ->
        for dx = 0 to len - 1 do
          let x = sx + dx in
          (* Fade toward the tip. *)
          let tip_alpha =
            alpha *. (1.0 -. (float_of_int dx /. float_of_int len))
          in
          blend_px
            bytes
            ~px_w
            ~px_h
            ~x
            ~y:sy
            ~r:255
            ~g:255
            ~b:255
            ~alpha:tip_alpha ;
          blend_px
            bytes
            ~px_w
            ~px_h
            ~x
            ~y:(sy + 1)
            ~r:255
            ~g:220
            ~b:180
            ~alpha:(tip_alpha *. 0.6)
        done)
      segments

(* ---------- monster taunts ---------- *)

(* Two taunts per kind. Index 0 or 1 chosen from floor number parity so
   it is stable within a floor but varies across floors. *)
let monster_taunts = function
  | Model.Spider ->
      [|"It clicks its chelicerae..."; "A web glistens in the darkness"|]
  | Model.Skeleton ->
      [|"Bones rattle in the dark..."; "An ancient warrior rises"|]
  | Model.Bat -> [|"Wings flutter overhead"; "Chittering echoes ahead"|]
  | Model.Wraith -> [|"A cold presence..."; "You feel your life draining..."|]
  | Model.Archer ->
      [|"An arrow nocks in the dark"; "You hear a bowstring pulled tight"|]
  | Model.Zombie ->
      [|"Shuffling footsteps grow louder..."; "A rotting stench fills the air"|]
  | Model.Lich -> [|"FEEL MY WRATH, MORTAL!"; "DEATH COMES FOR YOU!"|]
  | Model.Dragon -> [|"RAAAAAWR!"; "Smoke curls from beneath the door"|]

(* ---------- minimap (boxed, fog of war) ---------- *)

let draw_minimap bytes ~px_w ~px_h (s : Model.t) =
  if not s.show_minimap then ()
  else
    let f = s.floor in
    let scale = 3 in
    let map_w = f.width * scale in
    let map_h = f.height * scale in
    if map_w + 6 > px_w || map_h + 6 > px_h then ()
    else
      let ox = px_w - map_w - 3 in
      let oy = 3 in
      (* Drop-shadow / outer frame. *)
      fill_rect
        bytes
        ~px_w
        ~px_h
        ~x:(ox - 2)
        ~y:(oy - 2)
        ~w:(map_w + 4)
        ~h:(map_h + 4)
        ~r:8
        ~g:8
        ~b:14 ;
      fill_rect
        bytes
        ~px_w
        ~px_h
        ~x:(ox - 1)
        ~y:(oy - 1)
        ~w:(map_w + 2)
        ~h:(map_h + 2)
        ~r:30
        ~g:30
        ~b:42 ;
      for ty = 0 to f.height - 1 do
        for tx = 0 to f.width - 1 do
          let visited = s.has_full_map || Model.is_visited f ~x:tx ~y:ty in
          if visited then begin
            let t = Model.tile_at f ~x:tx ~y:ty in
            (* Visited tiles shown with a +20 brightness boost over unvisited
             fog-of-war darkness.  Full-map reveal uses the brighter shade
             throughout (has_full_map makes every tile appear visited). *)
            let r, g, b =
              match t with
              | Model.Wall -> (110, 100, 90)
              | Model.Door {locked = true; _} -> (220, 100, 60)
              | Model.Door {locked = false; open_ = false} -> (160, 110, 70)
              | Model.Door {open_ = true; _} -> (50, 40, 30)
              | Model.Stairs -> (110, 220, 230)
              | Model.Exit -> (255, 160, 240)
              | Model.Key -> (240, 220, 80)
              | Model.Potion -> (90, 240, 140)
              | Model.Torch -> (255, 180, 80)
              | Model.Sword -> (220, 240, 255)
              | Model.Map_scroll -> (160, 230, 255)
              | Model.Ring_of_speed -> (255, 255, 80)
              | Model.Armor -> (160, 220, 255)
              | Model.Speed_scroll -> (200, 255, 180)
              | Model.Healing_rune -> (120, 255, 160)
              | Model.Bomb_scroll -> (255, 120, 40)
              (* Recently-visited floor tiles appear slightly lighter so the
                 explored area stands out against the dark minimap background. *)
              | Model.Floor -> (60, 48, 38)
            in
            fill_rect
              bytes
              ~px_w
              ~px_h
              ~x:(ox + (tx * scale))
              ~y:(oy + (ty * scale))
              ~w:scale
              ~h:scale
              ~r
              ~g
              ~b
          end
        done
      done ;
      (* Corpse markers: dark-red × at each tile where a monster died. *)
      List.iter
        (fun (cx, cy) ->
          if s.has_full_map || Model.is_visited f ~x:cx ~y:cy then begin
            let mx = ox + (cx * scale) + (scale / 2) in
            let my = oy + (cy * scale) + (scale / 2) in
            (* Draw a small × using two diagonal pixel pairs. *)
            List.iter
              (fun (dx, dy) ->
                put_px
                  bytes
                  ~px_w
                  ~px_h
                  ~x:(mx + dx)
                  ~y:(my + dy)
                  ~r:140
                  ~g:20
                  ~b:20)
              [(-1, -1); (0, 0); (1, 1); (1, -1); (-1, 1)]
          end)
        s.corpses ;
      (* Player trail: last 5 positions as fading-grey dots (newest = lighter). *)
      List.iteri
        (fun i (tx, ty) ->
          (* i=0 is most recent; grey decreases toward older positions. *)
          let grey = 180 - (i * 30) in
          let grey = max 40 grey in
          let mx = ox + (tx * scale) + (scale / 2) in
          let my = oy + (ty * scale) + (scale / 2) in
          put_px bytes ~px_w ~px_h ~x:mx ~y:my ~r:grey ~g:grey ~b:grey)
        s.player_trail ;
      (* Visible monster pins (only on visited tiles). *)
      Array.iter
        (fun (m : Model.monster) ->
          if m.alive && Model.is_visited f ~x:m.mx ~y:m.my then begin
            let r, g, b =
              match m.kind with
              | Model.Lich | Model.Dragon -> (255, 80, 200)
              | Model.Wraith -> (200, 230, 255)
              | _ ->
                  let r0, g0, b0 = monster_palette m.kind in
                  (r0, g0, b0)
            in
            fill_rect
              bytes
              ~px_w
              ~px_h
              ~x:(ox + (m.mx * scale))
              ~y:(oy + (m.my * scale))
              ~w:scale
              ~h:scale
              ~r
              ~g
              ~b
          end)
        s.monsters ;
      (* Player pose: orange triangle / arrow pointing in facing direction. *)
      let px_c = ox + (int_of_float s.player.x * scale) + (scale / 2) in
      let py_c = oy + (int_of_float s.player.y * scale) + (scale / 2) in
      fill_rect
        bytes
        ~px_w
        ~px_h
        ~x:(px_c - 1)
        ~y:(py_c - 1)
        ~w:scale
        ~h:scale
        ~r:255
        ~g:180
        ~b:60 ;
      put_px
        bytes
        ~px_w
        ~px_h
        ~x:(px_c + (s.player.facing.dx * 2))
        ~y:(py_c + (s.player.facing.dy * 2))
        ~r:255
        ~g:240
        ~b:140

(* ---------- footstep dust-puff ---------- *)

(* Draw a 4-pixel-tall umber gradient strip at the very bottom of the
   raycast area. Simulates a footstep dust-puff. Alpha fades based on
   how much footstep_t remains (max 0.1 s). *)
let draw_footstep_flash bytes ~px_w ~px_h ~footstep_t =
  if footstep_t <= 0.0 then ()
  else begin
    let alpha = footstep_t /. 0.1 in
    for row = 0 to 3 do
      let fade = alpha *. (1.0 -. (float_of_int row /. 4.0)) in
      let r = int_of_float (120.0 *. fade) in
      let g = int_of_float (70.0 *. fade) in
      let b = int_of_float (20.0 *. fade) in
      let y = px_h - 1 - row in
      for x = 0 to px_w - 1 do
        blend_px bytes ~px_w ~px_h ~x ~y ~r ~g ~b ~alpha:fade
      done
    done
  end

(* ---------- health vignette ---------- *)

(* When HP is critically low (≤ 5), draw a pulsing red ring around the
   perimeter of the 3-D view.  The ring is 10 pixels wide on each edge.
   Alpha scales with how low HP is and pulses using a sine wave. *)
let draw_health_vignette bytes ~px_w ~px_h ~hp ~mode_t =
  if hp > 5 || hp <= 0 then ()
  else begin
    let base_alpha = (1.0 -. (float_of_int hp /. 5.0)) *. 0.7 in
    let pulse = 0.5 +. (0.5 *. Float.sin (mode_t *. 4.0)) in
    let alpha = base_alpha *. (0.5 +. (0.5 *. pulse)) in
    let ring = 10 in
    for y = 0 to px_h - 1 do
      for x = 0 to px_w - 1 do
        let dist_edge = min (min x (px_w - 1 - x)) (min y (px_h - 1 - y)) in
        if dist_edge < ring then begin
          let edge_alpha =
            alpha *. (1.0 -. (float_of_int dist_edge /. float_of_int ring))
          in
          blend_px bytes ~px_w ~px_h ~x ~y ~r:200 ~g:20 ~b:20 ~alpha:edge_alpha
        end
      done
    done
  end

(* ---------- frame builder ---------- *)

let build_frame (s : Model.t) ~px_w ~px_h =
  let bytes = Bytes.make (px_w * px_h * 3) '\000' in
  draw_floor_ceiling bytes ~px_w ~px_h ~torch_timer:s.player.torch_timer ;
  let depth = Array.make px_w Raycast.max_view_distance in
  for col = 0 to px_w - 1 do
    render_column s bytes ~px_w ~px_h ~col ~n_cols:px_w ~depth
  done ;
  draw_floor_marks bytes ~px_w ~px_h ~depth s ;
  (* Sort monsters far→near so closer ones overdraw farther ones. *)
  let alive_ms =
    Array.to_list s.monsters
    |> List.filter (fun (m : Model.monster) -> m.alive)
    |> List.map (fun (m : Model.monster) ->
        let dx = m.rx -. s.player.x in
        let dy = m.ry -. s.player.y in
        ((dx *. dx) +. (dy *. dy), m))
    |> List.sort (fun (a, _) (b, _) -> compare b a)
  in
  List.iter
    (fun (_, m) ->
      draw_monster bytes ~px_w ~px_h ~depth ~anim_t:s.anim_t s.player m)
    alive_ms ;
  draw_boss_projectiles bytes ~px_w ~px_h ~depth s ;
  draw_archer_projectiles bytes ~px_w ~px_h ~depth s ;
  draw_particles bytes ~px_w ~px_h ~depth s ;
  draw_popups bytes ~px_w ~px_h ~depth s ;
  (* Attack flash: slash X + weapon swing drawn on top of the world. *)
  if s.attack_flash_t > 0.0 then begin
    let alpha = s.attack_flash_t /. 0.3 in
    let cx = px_w / 2 in
    let cy = px_h / 2 in
    let half_sz = min (px_w / 6) (px_h / 4) in
    draw_slash_x bytes ~px_w ~px_h ~cx ~cy ~half_sz ~alpha ;
    draw_weapon_swing bytes ~px_w ~px_h ~alpha
  end ;
  (* Footstep dust-puff at the bottom of the view. *)
  draw_footstep_flash bytes ~px_w ~px_h ~footstep_t:s.footstep_t ;
  (* Low-health warning vignette: pulsing red ring around the view. *)
  draw_health_vignette bytes ~px_w ~px_h ~hp:s.player.hp ~mode_t:s.mode_t ;
  draw_minimap bytes ~px_w ~px_h s ;
  (* Flash overlay. *)
  let alpha = Arcade_kit.Screen_fx.flash_alpha s.fx in
  if alpha > 0.01 then begin
    let add = int_of_float (alpha *. 90.0) in
    let n = Bytes.length bytes in
    let i = ref 0 in
    while !i < n do
      let r = Char.code (Bytes.get bytes !i) in
      Bytes.set bytes !i (Char.chr (min 255 (r + add))) ;
      let g = Char.code (Bytes.get bytes (!i + 1)) in
      Bytes.set bytes (!i + 1) (Char.chr (min 255 (g + (add / 2)))) ;
      let b = Char.code (Bytes.get bytes (!i + 2)) in
      Bytes.set bytes (!i + 2) (Char.chr (min 255 (b + (add / 3)))) ;
      i := !i + 3
    done
  end ;
  bytes

(* ---------- HUD (top bar with inventory icons) ---------- *)

let render_hud (s : Model.t) ~cols =
  let p = s.player in
  let hp_str =
    let frac = float_of_int (max 0 p.hp) /. float_of_int p.hp_max in
    let lbl = Printf.sprintf "HP:%d/%d" (max 0 p.hp) p.hp_max in
    if frac < 0.25 then W.themed_error lbl
    else if frac < 0.5 then W.themed_warning lbl
    else W.themed_emphasis lbl
  in
  (* Passive regen indicator: show "..." in dim green when rest_t > 2.0 s
     (halfway to the 4 s threshold), indicating regen is building up. *)
  let regen_str = if p.hp < p.hp_max && p.rest_t > 2.0 then " ..." else "" in
  let speed_ring_str =
    if p.speed_ring_timer > 0.0 then
      Printf.sprintf "  SPD%ds" (int_of_float (Float.ceil p.speed_ring_timer))
    else ""
  in
  let charges_str = Printf.sprintf "  ⚡×%d" p.special_charges in
  let armor_str = if p.has_armor then "  [A]" else "" in
  let bomb_str =
    if p.bomb_count > 0 then Printf.sprintf "  [B:%d]" p.bomb_count else ""
  in
  let level_str = Printf.sprintf "  Lv.%d" p.player_level in
  (* Torch indicator: flash when active and about to expire (< 5 s). *)
  let torch_str =
    if p.torch_timer > 5.0 then
      Printf.sprintf "  🔥%ds" (int_of_float (Float.ceil p.torch_timer))
    else if p.torch_timer > 0.0 then begin
      let blink = int_of_float (s.anim_t *. 4.0) mod 2 = 0 in
      if blink then
        Printf.sprintf "  🔥%ds!" (int_of_float (Float.ceil p.torch_timer))
      else "  🔥  !"
    end
    else ""
  in
  let inv =
    Printf.sprintf
      "🗝%d  ⚗%d  🕯%d  ⚔+%d%s%s%s%s%s"
      p.keys
      p.potions
      p.torches
      p.sword_bonus
      torch_str
      speed_ring_str
      charges_str
      armor_str
      bomb_str
  in
  let bar =
    Printf.sprintf
      "  %s%s%s | %s | F%d/%d | Best:F%d | Score:%d  %s"
      hp_str
      regen_str
      level_str
      inv
      p.floor
      Floors.count
      s.best_floor
      s.score
      s.last_action
  in
  let dbg =
    if s.debug_mode then
      Printf.sprintf
        "  [TURN-BASED frame %d  pending=%d  n/N/b]"
        s.frame_no
        s.pending_steps
    else ""
  in
  W.themed_emphasis (pad_right (bar ^ dbg) ~width:cols)

let render_footer ~cols (s : Model.t) =
  let txt =
    if s.debug_mode then
      "  ↑/w fwd  ↓/s back  ←/→ turn  a/d strafe  Space act  e spin⚡  f bomb  \
       q drink  t torch  m map  i inv  n/N/b step  Esc back"
    else
      "  ↑/w fwd  ↓/s back  ←/→ turn  a/d strafe  Space act  e spin⚡  f bomb  \
       q drink  t torch  m map  i inventory  Esc back"
  in
  W.themed_muted (pad_right txt ~width:cols)

(* ---------- title screen ---------- *)

let render_title (s : Model.t) ~cols ~rows =
  let lines = ref [] in
  let push x = lines := x :: !lines in
  let blank () = push "" in
  blank () ;
  blank () ;
  push (W.themed_emphasis (center_in cols "MIAOU CRYPT — descend")) ;
  push
    (W.themed_muted
       (center_in cols "a pseudo-3-D first-person dungeon crawler")) ;
  blank () ;
  (* Enhanced ASCII 3-D corridor art: depth-shaded stone passage view.
     Block characters provide a convincing first-person perspective. *)
  List.iter
    (fun line -> push (W.themed_muted (center_in cols line)))
    [
      "████▓▓▒▒░░             ░░▒▒▓▓████";
      "████▓▓▒░  ╔══════════╗  ░▒▓▓████";
      "████▓▒░   ║          ║   ░▒▓████";
      "████▓░   ╔╝          ╚╗   ░▓████";
      "████░   ╔╝            ╚╗   ░████";
      "███░    ║  🔥      🔥  ║    ░███";
      "███     ║              ║     ███";
      "████░   ╚╗            ╔╝   ░████";
      "████▓░   ╚╗          ╔╝   ░▓████";
    ] ;
  push (center_in cols "═══════════════════════════════════") ;
  blank () ;
  push (center_in cols "↑/w  -  Step forward") ;
  push (center_in cols "↓/s  -  Step back") ;
  push (center_in cols "←/→  -  Turn 90°") ;
  push (center_in cols "a/d  -  Strafe") ;
  push (center_in cols "Space-  Attack / open door") ;
  push (center_in cols "e    -  Spin attack (⚡ charge)") ;
  push (center_in cols "f    -  Use bomb scroll (area blast)") ;
  push (center_in cols "q    -  Drink potion (+5 HP)") ;
  push (center_in cols "t    -  Light torch (extra view)") ;
  push (center_in cols "m    -  Toggle minimap") ;
  push (center_in cols "i    -  Inventory") ;
  push (center_in cols "Esc  -  Back") ;
  blank () ;
  push (W.themed_emphasis (center_in cols "Press Enter to enter the crypt")) ;
  blank () ;
  push
    (W.themed_muted
       (center_in
          cols
          (Printf.sprintf
             "Best depth: F%d  |  Best score: %d"
             s.best_floor
             s.best_score))) ;
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
  (* Per-floor star ratings: ★ for earned, ☆ for not yet achieved. *)
  let stars_str =
    let buf = Buffer.create 64 in
    Array.iteri
      (fun i earned ->
        if i > 0 then Buffer.add_string buf "  " ;
        Buffer.add_string buf (Printf.sprintf "F%d:" (i + 1)) ;
        for star = 1 to 3 do
          Buffer.add_string buf (if star <= earned then "★" else "☆")
        done)
      s.floor_stars ;
    Buffer.contents buf
  in
  (* Gravestone ASCII art panel. *)
  blank () ;
  push (W.themed_error (center_in cols "       _______")) ;
  push (W.themed_error (center_in cols "      /       \\")) ;
  push (W.themed_error (center_in cols "     |  R.I.P  |")) ;
  push (W.themed_error (center_in cols "     |         |")) ;
  push (W.themed_error (center_in cols "     |_________|")) ;
  push (W.themed_error (center_in cols "    /___________\\")) ;
  blank () ;
  push (W.themed_error (center_in cols "YOU DIED")) ;
  blank () ;
  (* Cause of death. *)
  if s.last_death_cause <> "" then begin
    push
      (W.themed_warning
         (center_in cols (String.uppercase_ascii s.last_death_cause))) ;
    blank ()
  end ;
  push
    (W.themed_emphasis
       (center_in cols (Printf.sprintf "FLOORS REACHED: %d" s.deepest_reached))) ;
  push
    (W.themed_emphasis
       (center_in cols (Printf.sprintf "TOTAL KILLS: %d" s.total_kills))) ;
  push (W.themed_emphasis (center_in cols (Printf.sprintf "SCORE: %d" s.score))) ;
  blank () ;
  push (center_in cols "─────── run summary ───────") ;
  blank () ;
  push
    (center_in cols (Printf.sprintf "Sword bonus:  +%d" s.player.sword_bonus)) ;
  blank () ;
  (* Floor ratings row. *)
  push (W.themed_muted (center_in cols "FLOOR RATINGS:")) ;
  push (center_in cols stars_str) ;
  blank () ;
  push
    (W.themed_muted
       (center_in
          cols
          (Printf.sprintf
             "Best depth: F%d  |  Best score: %d"
             s.best_floor
             s.best_score))) ;
  blank () ;
  push (W.themed_muted (center_in cols "Enter to retry · Esc to leave")) ;
  let body = List.rev !lines in
  let pad_top = max 0 ((rows - List.length body) / 2) in
  let top = List.init pad_top (fun _ -> "") in
  String.concat "\n" (top @ body)

let render_floor_clear (s : Model.t) ~cols ~rows =
  let lines = ref [] in
  let push x = lines := x :: !lines in
  let blank () = push "" in
  blank () ;
  let title =
    if s.player.floor >= Floors.count then "ARTIFACT RECOVERED"
    else Printf.sprintf "FLOOR %d CLEARED" s.player.floor
  in
  push (W.themed_emphasis (center_in cols title)) ;
  blank () ;
  push (center_in cols (Printf.sprintf "Score:  %d" s.score)) ;
  push
    (center_in
       cols
       (Printf.sprintf "HP:     %d/%d" s.player.hp s.player.hp_max)) ;
  push (center_in cols (Printf.sprintf "Killed: %d" s.player.monsters_killed)) ;
  blank () ;
  let next_msg =
    if s.player.floor >= Floors.count then "Enter to return to title"
    else Printf.sprintf "Enter to descend to floor %d" (s.player.floor + 1)
  in
  push (W.themed_muted (center_in cols next_msg)) ;
  push (W.themed_muted (center_in cols "Esc to leave")) ;
  let body = List.rev !lines in
  let pad_top = max 0 ((rows - List.length body) / 2) in
  let top = List.init pad_top (fun _ -> "") in
  String.concat "\n" (top @ body)

let render_boss_cinematic (s : Model.t) ~cols ~rows =
  (* Show the same in-world view but with a big text overlay banner. *)
  let lines = ref [] in
  let push x = lines := x :: !lines in
  let blank () = push "" in
  let pulse = int_of_float (s.mode_t *. 8.0) mod 2 = 0 in
  blank () ;
  blank () ;
  blank () ;
  if pulse then push (W.themed_emphasis (center_in cols "★ ARTIFACT FOUND ★"))
  else push (center_in cols "  ARTIFACT FOUND  ") ;
  blank () ;
  push (W.themed_warning (center_in cols s.cinematic_msg)) ;
  blank () ;
  push (center_in cols (Printf.sprintf "Score: %d" s.score)) ;
  push (center_in cols (Printf.sprintf "Killed: %d" s.player.monsters_killed)) ;
  blank () ;
  let next_msg =
    if s.player.floor >= Floors.count then "Enter to return to title"
    else Printf.sprintf "Enter to descend to floor %d" (s.player.floor + 1)
  in
  push (W.themed_muted (center_in cols next_msg)) ;
  let body = List.rev !lines in
  let pad_top = max 0 ((rows - List.length body) / 2) in
  let top = List.init pad_top (fun _ -> "") in
  String.concat "\n" (top @ body)

let render_descending_anim (s : Model.t) ~cols ~rows =
  (* Brief full-screen overlay: white-flash "DESCENDING..." text.
     The world is frozen; this plays for 0.8 s then transitions. *)
  let lines = ref [] in
  let push x = lines := x :: !lines in
  let blank () = push "" in
  (* Blink at 8 Hz for urgency. *)
  let blink = int_of_float (s.mode_t *. 8.0) mod 2 = 0 in
  blank () ;
  blank () ;
  blank () ;
  if blink then push (W.themed_emphasis (center_in cols "DESCENDING..."))
  else push (center_in cols "              ") ;
  blank () ;
  push
    (W.themed_muted
       (center_in
          cols
          (Printf.sprintf
             "floor %d → floor %d"
             s.player.floor
             (s.player.floor + 1)))) ;
  let body = List.rev !lines in
  let pad_top = max 0 ((rows - List.length body) / 2) in
  let top = List.init pad_top (fun _ -> "") in
  String.concat "\n" (top @ body)

(* ---------- monster taunt line ---------- *)

(* Return the flavour taunt text for the monster directly in front of
   the player, or an empty string if there is none. The taunt index
   (0 or 1) is derived from the current floor number so it varies per
   floor but is stable within a floor. *)
let front_monster_taunt (s : Model.t) =
  let fx = int_of_float s.player.x + s.player.facing.dx in
  let fy = int_of_float s.player.y + s.player.facing.dy in
  match Model.monster_at s ~x:fx ~y:fy with
  | None -> ""
  | Some m ->
      let taunts = monster_taunts m.kind in
      let idx = s.player.floor mod Array.length taunts in
      taunts.(idx)

(* ---------- inventory overlay ---------- *)

(* Render a centred text-box popup listing the player's current items.
   Returns a multi-line string the same height as [rows], with the box
   drawn in the vertical centre. *)
let render_inventory (s : Model.t) ~cols ~rows =
  let p = s.player in
  let lines = ref [] in
  let push x = lines := x :: !lines in
  let blank () = push (String.make cols ' ') in
  (* Box-drawing helpers using ASCII dashes to avoid multi-byte char issues. *)
  let box_w = min 40 cols in
  let pad = String.make ((cols - box_w) / 2) ' ' in
  let hbar = String.make (box_w - 2) '-' in
  let line txt =
    let trimmed =
      if String.length txt > box_w - 4 then String.sub txt 0 (box_w - 4)
      else txt
    in
    let inner = pad_right trimmed ~width:(box_w - 4) in
    push (pad ^ "| " ^ inner ^ " |")
  in
  let hline cap = push (pad ^ cap ^ hbar ^ cap) in
  blank () ;
  hline "+" ;
  line (W.themed_emphasis "INVENTORY") ;
  push (pad ^ "+" ^ hbar ^ "+") ;
  line
    (Printf.sprintf
       "Level:      %d (XP: %d/%d)"
       p.player_level
       p.xp
       p.xp_to_next) ;
  line (Printf.sprintf "Keys:       %d" p.keys) ;
  line (Printf.sprintf "Potions:    %d" p.potions) ;
  line (Printf.sprintf "Torches:    %d" p.torches) ;
  line (Printf.sprintf "Bomb scrolls: %d" p.bomb_count) ;
  line (Printf.sprintf "Sword:      +%d" p.sword_bonus) ;
  if p.speed_ring_timer > 0.0 then
    line
      (Printf.sprintf
         "Speed ring: %ds"
         (int_of_float (Float.ceil p.speed_ring_timer)))
  else line "Speed ring: none" ;
  line (if p.has_armor then "Armor:      equipped" else "Armor:      none") ;
  line (if s.has_full_map then "Map:        revealed" else "Map:        fog") ;
  push (pad ^ "+" ^ hbar ^ "+") ;
  line (W.themed_muted "Press i to close") ;
  hline "+" ;
  let body_lines = List.rev !lines in
  let n = List.length body_lines in
  let pad_top = max 0 ((rows - n) / 2) in
  let top = List.init pad_top (fun _ -> String.make cols ' ') in
  let bot_count = max 0 (rows - pad_top - n) in
  let bot = List.init bot_count (fun _ -> String.make cols ' ') in
  String.concat "\n" (top @ body_lines @ bot)

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

let render (s : Model.t) ~size =
  let cols = size.LTerm_geom.cols in
  let rows = size.LTerm_geom.rows in
  if cols < 60 || rows < 20 then too_small_msg
  else
    let frame_cols = min cap_frame_cols cols in
    let frame_rows = min cap_frame_rows (rows - 2) in
    let mode =
      Arcade_kit.Pixel_mode.resolve ~env_var:"MIAOU_CRYPT_PIXEL_MODE" ()
    in
    let px_x, px_y = mode_px_per_cell mode in
    let px_w = frame_cols * px_x in
    let px_h = frame_rows * px_y in
    let body =
      match s.mode with
      | Model.Title -> render_title s ~cols:frame_cols ~rows:frame_rows
      | Model.Game_over -> render_game_over s ~cols:frame_cols ~rows:frame_rows
      | Model.Floor_clear ->
          render_floor_clear s ~cols:frame_cols ~rows:frame_rows
      | Model.Boss_kill_cinematic ->
          (* Render the world frame underneath, then overlay text. *)
          let bytes = build_frame s ~px_w ~px_h in
          let fb = FB.create () in
          FB.blit fb ~src:bytes ~width:px_w ~height:px_h ;
          let world =
            FB.render_with_mode fb ~mode ~cols:frame_cols ~rows:frame_rows
          in
          let overlay =
            render_boss_cinematic s ~cols:frame_cols ~rows:frame_rows
          in
          (* Pick whichever the user can read — the overlay sits on top. *)
          if int_of_float (s.mode_t *. 4.0) mod 2 = 0 then overlay else world
      | Model.Descending_anim _ ->
          render_descending_anim s ~cols:frame_cols ~rows:frame_rows
      | Model.Exploring ->
          if s.show_inventory then
            render_inventory s ~cols:frame_cols ~rows:frame_rows
          else begin
            let bytes = build_frame s ~px_w ~px_h in
            let fb = FB.create () in
            FB.blit fb ~src:bytes ~width:px_w ~height:px_h ;
            FB.render_with_mode fb ~mode ~cols:frame_cols ~rows:frame_rows
          end
    in
    let header = render_hud s ~cols:frame_cols in
    let footer = render_footer ~cols:frame_cols s in
    (* Monster taunt: one dim line between the 3-D view and the footer
       when a monster is directly in front of the player. *)
    let taunt_line =
      match s.mode with
      | Model.Exploring ->
          let txt = front_monster_taunt s in
          if txt = "" then ""
          else
            W.themed_muted
              (pad_right (center_in frame_cols txt) ~width:frame_cols)
      | _ -> ""
    in
    (* Boss warning banner: bright orange "⚠ INCOMING!" pulsing line when
       the Dragon is about to fire a breath cone. *)
    let warning_line =
      match s.mode with
      | Model.Exploring when s.boss_warning ->
          let blink = int_of_float (s.mode_t *. 8.0) mod 2 = 0 in
          if blink then
            W.themed_error
              (pad_right
                 (center_in frame_cols "⚠  INCOMING! ⚠")
                 ~width:frame_cols)
          else pad_right "" ~width:frame_cols
      | _ -> ""
    in
    (* Level-up banner: bright gold "LEVEL UP!" displayed for 1.5 s. *)
    let levelup_line =
      match s.mode with
      | Model.Exploring when s.levelup_flash_t > 0.0 ->
          let blink = int_of_float (s.levelup_flash_t *. 6.0) mod 2 = 0 in
          if blink then
            W.themed_emphasis
              (pad_right
                 (center_in
                    frame_cols
                    (Printf.sprintf
                       "★  LEVEL UP!  Lv.%d  ★"
                       s.player.player_level))
                 ~width:frame_cols)
          else pad_right "" ~width:frame_cols
      | _ -> ""
    in
    (* Minimap legend: a compact key shown when the minimap is visible. *)
    let legend_line =
      match s.mode with
      | Model.Exploring when s.show_minimap ->
          W.themed_muted
            (pad_right
               (center_in frame_cols "▲P  ●E  ★K  ×D")
               ~width:frame_cols)
      | _ -> ""
    in
    (* Assemble parts: header, optional banners above body, body,
       optional status lines below, footer. *)
    let top_banners =
      List.filter (fun s -> s <> "") [warning_line; levelup_line]
    in
    let bot_extras = List.filter (fun s -> s <> "") [taunt_line; legend_line] in
    String.concat
      "\n"
      (([header] @ top_banners @ [body]) @ bot_extras @ [footer])
