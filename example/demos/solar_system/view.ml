(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

module FB = Miaou_widgets_display.Framebuffer_widget
module Caps = Miaou_widgets_display.Terminal_caps
module W = Miaou_widgets_display.Widgets

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

(* ---------- pixel helpers ---------- *)

let put_px bytes ~px_w ~px_h ~x ~y ~r ~g ~b =
  if x >= 0 && x < px_w && y >= 0 && y < px_h then begin
    let off = ((y * px_w) + x) * 3 in
    Bytes.set bytes off (Char.chr r) ;
    Bytes.set bytes (off + 1) (Char.chr g) ;
    Bytes.set bytes (off + 2) (Char.chr b)
  end

let mix ~base diffuse =
  let r0, g0, b0 = base in
  let f = Float.max 0.05 diffuse in
  let r = int_of_float (float_of_int r0 *. f) in
  let g = int_of_float (float_of_int g0 *. f) in
  let b = int_of_float (float_of_int b0 *. f) in
  (max 0 (min 255 r), max 0 (min 255 g), max 0 (min 255 b))

(* Bresenham circle outline. *)
let stroke_circle bytes ~px_w ~px_h ~cx ~cy ~radius ~r ~g ~b =
  if radius <= 0 then ()
  else
    let x = ref radius in
    let y = ref 0 in
    let err = ref (1 - radius) in
    while !x >= !y do
      let put dx dy = put_px bytes ~px_w ~px_h ~x:(cx + dx) ~y:(cy + dy) ~r ~g ~b in
      put !x !y ;
      put !y !x ;
      put (- !x) !y ;
      put (- !y) !x ;
      put !x (- !y) ;
      put !y (- !x) ;
      put (- !x) (- !y) ;
      put (- !y) (- !x) ;
      incr y ;
      if !err <= 0 then err := !err + (2 * !y) + 1
      else begin
        decr x ;
        err := !err + (2 * (!y - !x)) + 1
      end
    done

(* Bresenham ellipse outline (axis-aligned, semi-axes a along x, b along y). *)
let stroke_ellipse bytes ~px_w ~px_h ~cx ~cy ~a ~b ~r ~g ~bl =
  if a <= 0 || b <= 0 then ()
  else
    let n = 4 * (a + b) in
    let n = max 32 n in
    for i = 0 to n - 1 do
      let theta = 2.0 *. Float.pi *. float_of_int i /. float_of_int n in
      let x = cx + int_of_float (float_of_int a *. cos theta) in
      let y = cy + int_of_float (float_of_int b *. sin theta) in
      put_px bytes ~px_w ~px_h ~x ~y ~r ~g ~b:bl
    done

(* Posterised sphere shading. Lambert is quantised to four bands so the
   octant 256-colour palette gets discrete-looking steps instead of
   broken gradients. A tiny bright specular spot sits on the sun-facing
   pole, and a single bright "surface dot" rotates with the spin phase
   to give a readable rotation cue without the noise of full-disc
   stripes. *)
let fill_disc bytes ~px_w ~px_h ~cx ~cy ~radius ~base ~sun_dx ~sun_dy
    ~spin_phase =
  if radius <= 0 then put_px bytes ~px_w ~px_h ~x:cx ~y:cy
       ~r:(let r, _, _ = base in r)
       ~g:(let _, g, _ = base in g)
       ~b:(let _, _, b = base in b)
  else
    let r2 = radius * radius in
    let len =
      Float.max 1.0 (sqrt ((sun_dx *. sun_dx) +. (sun_dy *. sun_dy)))
    in
    let lx = sun_dx /. len in
    let ly = sun_dy /. len in
    let rf = float_of_int radius in
    let posterise lambert =
      if lambert > 0.85 then 1.05
      else if lambert > 0.55 then 0.85
      else if lambert > 0.25 then 0.55
      else if lambert > 0.05 then 0.32
      else 0.18
    in
    for dy = -radius to radius do
      for dx = -radius to radius do
        let d2 = (dx * dx) + (dy * dy) in
        if d2 <= r2 then begin
          let nxf = float_of_int dx /. rf in
          let nyf = float_of_int dy /. rf in
          let cos_t = (nxf *. lx) +. (nyf *. ly) in
          let lambert = Float.max 0.0 cos_t in
          let diffuse = posterise lambert in
          let r, g, b = mix ~base diffuse in
          put_px bytes ~px_w ~px_h ~x:(cx + dx) ~y:(cy + dy) ~r ~g ~b
        end
      done
    done ;
    (* Specular hot-spot: a 1-2 px white-ish dot biased toward the
       sun-facing pole — small enough to read as gloss, not as a
       second light source. *)
    if radius >= 4 then begin
      let sx = int_of_float (lx *. 0.55 *. rf) in
      let sy = int_of_float (ly *. 0.55 *. rf) in
      let r, g, b = mix ~base:(255, 250, 230) 1.0 in
      put_px bytes ~px_w ~px_h ~x:(cx + sx) ~y:(cy + sy) ~r ~g ~b ;
      if radius >= 6 then
        put_px bytes ~px_w ~px_h ~x:(cx + sx + 1) ~y:(cy + sy) ~r ~g ~b
    end ;
    (* Rotation cue: a single bright surface dot that orbits the limb
       at the body's spin rate. Drops on the unlit side. *)
    if radius >= 4 then begin
      let rr = rf *. 0.78 in
      let mx = rr *. cos spin_phase in
      let my = rr *. sin spin_phase in
      let cos_l = ((mx /. rr) *. lx) +. ((my /. rr) *. ly) in
      if cos_l > 0.05 then begin
        let r, g, b = mix ~base:(255, 255, 255) 1.0 in
        put_px
          bytes
          ~px_w
          ~px_h
          ~x:(cx + int_of_float mx)
          ~y:(cy + int_of_float my)
          ~r
          ~g
          ~b
      end
    end

(* Camera tilt: 0 → top-down, π/2 → edge-on. ~25° gives a textbook 3-D
   solar-system feel (orbits read as ellipses, sun and outer planets feel
   behind/in front of the foreground). *)
let camera_tilt = 0.42

let project_orbit_to_screen ~cx ~cy mx my =
  let cos_t = cos camera_tilt in
  (cx + int_of_float mx, cy + int_of_float (my *. cos_t))

(* "Depth" used to sort planets back-to-front so foreground planets
   correctly draw over the sun and over each other. Higher = closer to
   camera. With our tilt, depth grows with -y (positive y is "behind" in
   3-D top-down convention but rendered low on screen — so a planet at
   y > 0 is on the far side; flip sign so foreground has bigger depth). *)
let depth_of my = -. my

(* Sun: hot yellow-white core with a warm halo. Halo kept compact (4/3 ×
   core) so it doesn't swallow the inner planets. *)
let draw_sun bytes ~px_w ~px_h ~cx ~cy ~radius =
  let core_r = radius in
  let halo_r = radius * 4 / 3 in
  let r2 = halo_r * halo_r in
  for dy = -halo_r to halo_r do
    for dx = -halo_r to halo_r do
      let d2 = (dx * dx) + (dy * dy) in
      if d2 <= r2 then begin
        let d = sqrt (float_of_int d2) in
        let f =
          if d <= float_of_int core_r then 1.0
          else
            let t =
              (d -. float_of_int core_r)
              /. Float.max 1.0 (float_of_int (halo_r - core_r))
            in
            Float.max 0.0 (1.0 -. t)
        in
        let r, g, b = mix ~base:(255, 220, 90) (Float.min 1.0 (f *. 1.1)) in
        if f > 0.02 then put_px bytes ~px_w ~px_h ~x:(cx + dx) ~y:(cy + dy) ~r ~g ~b
      end
    done
  done

(* Saturn-style ring — the ring lies in the orbit plane so it picks up
   the same camera tilt (squashed by cos camera_tilt on the screen-y
   axis). [half = `Back] traces only the upper half of the ellipse (the
   part that should be hidden behind the planet), [half = `Front] traces
   the lower half (which should occlude the planet). Drawing the back
   half before the disc and the front half after gives the textbook 3-D
   "ring through planet" look. *)
let stroke_ellipse_half bytes ~px_w ~px_h ~cx ~cy ~a ~b ~half ~r ~g ~bl =
  if a <= 0 || b <= 0 then ()
  else
    let n = max 64 (4 * (a + b)) in
    for i = 0 to n - 1 do
      let theta = 2.0 *. Float.pi *. float_of_int i /. float_of_int n in
      let take =
        match half with
        | `Back -> sin theta < 0.0
        | `Front -> sin theta >= 0.0
      in
      if take then begin
        let x = cx + int_of_float (float_of_int a *. cos theta) in
        let y = cy + int_of_float (float_of_int b *. sin theta) in
        put_px bytes ~px_w ~px_h ~x ~y ~r ~g ~b:bl
      end
    done

let draw_ring_half bytes ~px_w ~px_h ~cx ~cy ~radius ~half =
  let outer_a = radius * 9 / 4 in
  let mid_a = radius * 7 / 4 in
  let inner_a = radius * 6 / 4 in
  let cos_t = cos camera_tilt in
  let outer_b = max 1 (int_of_float (float_of_int outer_a *. cos_t)) in
  let mid_b = max 1 (int_of_float (float_of_int mid_a *. cos_t)) in
  let inner_b = max 1 (int_of_float (float_of_int inner_a *. cos_t)) in
  stroke_ellipse_half
    bytes ~px_w ~px_h ~cx ~cy ~a:outer_a ~b:outer_b ~half
    ~r:235 ~g:215 ~bl:165 ;
  stroke_ellipse_half
    bytes ~px_w ~px_h ~cx ~cy ~a:mid_a ~b:mid_b ~half
    ~r:215 ~g:195 ~bl:150 ;
  stroke_ellipse_half
    bytes ~px_w ~px_h ~cx ~cy ~a:inner_a ~b:inner_b ~half
    ~r:200 ~g:185 ~bl:140

(* ---------- starfield (deterministic, sparse) ---------- *)

let starfield bytes ~px_w ~px_h =
  let st = Random.State.make [|0xC057A1; px_w; px_h|] in
  (* Sparse: ~one star per 3500 pixels so the sky reads as a clean black
     backdrop with the occasional pinpoint, not a snowstorm. *)
  let n = px_w * px_h / 3500 in
  for _ = 1 to n do
    let x = Random.State.int st px_w in
    let y = Random.State.int st px_h in
    let bucket = Random.State.int st 100 in
    let v =
      if bucket < 5 then 240 (* rare bright star *)
      else if bucket < 25 then 180
      else 120
    in
    let tint = Random.State.int st 30 in
    put_px bytes ~px_w ~px_h ~x ~y ~r:v ~g:(v - (tint / 3)) ~b:(v - tint)
  done

(* ---------- scaling ---------- *)

let neptune_mkm = 4495.1

(* Distance scale: square-root compression of real distances, with a
   constant offset so that even Mercury's orbit (sqrt(57.9) = ~7.6 ≪
   sqrt(neptune)) sits well clear of the Sun's halo. *)
let dist_to_px ~max_radius_px ~mkm =
  let base_offset = 18 in
  let max_dist = sqrt neptune_mkm in
  let usable = max 1 (max_radius_px - base_offset) in
  let f = sqrt mkm /. max_dist in
  base_offset + int_of_float (f *. float_of_int usable)

let radius_for_body (body : Model.body) ~scale =
  if body.name = "Sun" then max 5 (int_of_float (8.0 *. scale))
  else
    let earth = 6371.0 in
    let r = Float.cbrt (body.radius_km /. earth) *. 4.5 *. scale in
    max 3 (int_of_float r)

(* ---------- frame builder ---------- *)

(* Default to Octant: 256-color sub-cell rendering that gives readable
   colours through the matrix driver's ANSI parser. Auto-detected Sixel
   tends to over-quantize our smooth gradients into a chunky / fragmented
   look, so it's opt-in only. *)
let frame_pixel_mode () =
  match Sys.getenv_opt "MIAOU_SOLAR_PIXEL_MODE" with
  | Some "sixel" -> Caps.Sixel
  | Some "octant" -> Caps.Octant
  | Some "sextant" -> Caps.Sextant
  | Some "half_block" -> Caps.Half_block
  | Some "braille" -> Caps.Braille
  | _ -> Caps.Octant

let mode_px_per_cell mode =
  match mode with
  | Caps.Sixel -> (8, 16)
  | Caps.Octant -> (2, 4)
  | Caps.Sextant -> (2, 3)
  | Caps.Half_block -> (1, 2)
  | Caps.Braille -> (2, 4)

let build_frame (s : Model.state) ~px_w ~px_h =
  let bytes = Bytes.make (px_w * px_h * 3) '\000' in
  starfield bytes ~px_w ~px_h ;
  let cx = px_w / 2 in
  let cy = px_h / 2 in
  (* Tilted ellipses: horizontal extent = r, vertical extent = r*cos_tilt.
     Allow r to grow until either axis hits the frame margin. *)
  let cos_tilt = cos camera_tilt in
  let h_limit = cx - 4 in
  let v_limit = int_of_float (float_of_int (cy - 4) /. cos_tilt) in
  let max_radius_px = max 24 (min h_limit v_limit) in
  let scale =
    Float.max 0.6 (float_of_int (min px_w px_h) /. 240.0)
  in
  if s.show_orbits then begin
    Array.iter
      (fun (p : Model.body) ->
        let r = dist_to_px ~max_radius_px ~mkm:p.orbit_mkm in
        let b_axis = max 1 (int_of_float (float_of_int r *. cos_tilt)) in
        stroke_ellipse
          bytes
          ~px_w
          ~px_h
          ~cx
          ~cy
          ~a:r
          ~b:b_axis
          ~r:48
          ~g:60
          ~bl:80)
      Model.planets
  end ;
  let sun_r = radius_for_body Model.sun ~scale in
  (* Build a depth-sorted list of planet draw items. Planets with smaller
     depth (further side of the orbit) draw before the sun; planets in
     front draw after, naturally occluding the sun's halo. *)
  let items =
    Array.to_list Model.planets
    |> List.map (fun (p : Model.body) ->
           let mx, my = Model.body_xy p ~t_days:s.t_days in
           let dpx = float_of_int (dist_to_px ~max_radius_px ~mkm:p.orbit_mkm) in
           let phase = atan2 my mx in
           let bx = dpx *. cos phase in
           let by = dpx *. sin phase in
           let px, py = project_orbit_to_screen ~cx ~cy bx by in
           let pr = radius_for_body p ~scale in
           let sp = Model.spin_phase p ~t_days:s.t_days in
           (depth_of by, p, px, py, pr, sp))
    |> List.sort (fun (a, _, _, _, _, _) (b, _, _, _, _, _) -> compare a b)
  in
  let draw_planet (_, (p : Model.body), px, py, pr, sp) =
    let sun_dx = float_of_int (cx - px) in
    let sun_dy = float_of_int (cy - py) in
    if p.has_ring then
      draw_ring_half bytes ~px_w ~px_h ~cx:px ~cy:py ~radius:pr ~half:`Back ;
    fill_disc
      bytes
      ~px_w
      ~px_h
      ~cx:px
      ~cy:py
      ~radius:pr
      ~base:p.base_color
      ~sun_dx
      ~sun_dy
      ~spin_phase:sp ;
    if p.has_ring then
      draw_ring_half bytes ~px_w ~px_h ~cx:px ~cy:py ~radius:pr ~half:`Front
  in
  let behind_sun, in_front_of_sun =
    List.partition (fun (d, _, _, _, _, _) -> d <= 0.0) items
  in
  List.iter draw_planet behind_sun ;
  draw_sun bytes ~px_w ~px_h ~cx ~cy ~radius:sun_r ;
  List.iter draw_planet in_front_of_sun ;
  bytes

(* ---------- side panel ---------- *)

let panel_width = 30

let build_panel (s : Model.state) ~rows =
  let lines = Buffer.create 1024 in
  let add l = Buffer.add_string lines (pad_right l ~width:panel_width) ; Buffer.add_char lines '\n' in
  add (W.themed_emphasis "Solar System") ;
  add (W.themed_muted "─────────────────────────────") ;
  let years = s.t_days /. 365.25 in
  add (Printf.sprintf "Sim time: +%.1f y" years) ;
  add
    (Printf.sprintf
       "Speed:    %s%s"
       (Model.speed_label s.speed)
       (if s.paused then "  (paused)" else "")) ;
  add "" ;
  add (W.themed_muted "Planets (orbital phase)") ;
  Array.iter
    (fun (p : Model.body) ->
      let mx, my = Model.body_xy p ~t_days:s.t_days in
      let phase = atan2 my mx in
      let deg = ((phase *. 180.0 /. Float.pi) +. 360.0) |> mod_float 360.0 in
      add
        (Printf.sprintf "  %-8s %3.0f°  %5.0fMkm" p.name deg p.orbit_mkm))
    Model.planets ;
  add "" ;
  add (W.themed_muted "Controls") ;
  add "  1-5  speed x1..x10k" ;
  add "  p    pause/resume" ;
  add (Printf.sprintf "  o    orbits  %s" (if s.show_orbits then "on" else "off")) ;
  add (Printf.sprintf "  l    labels  %s" (if s.show_labels then "on" else "off")) ;
  add "  r    reset time" ;
  add "  Tab  hide panel" ;
  add "  Esc  back" ;
  let raw = Buffer.contents lines in
  (* Truncate / pad to [rows] lines. *)
  let parts = String.split_on_char '\n' raw in
  let parts =
    let l = List.length parts in
    if l >= rows then
      let rec take n = function
        | _ when n = 0 -> []
        | [] -> []
        | x :: xs -> x :: take (n - 1) xs
      in
      take rows parts
    else parts @ List.init (rows - l) (fun _ -> String.make panel_width ' ')
  in
  String.concat "\n" parts

(* ---------- composition ---------- *)

let compose_left_right ~left ~right =
  let l_lines = String.split_on_char '\n' left in
  let r_lines = String.split_on_char '\n' right in
  let n = max (List.length l_lines) (List.length r_lines) in
  let rec pad lst k =
    if k = 0 then lst
    else match lst with [] -> "" :: pad [] (k - 1) | x :: xs -> x :: pad xs (k - 1)
  in
  let l_lines = pad l_lines n in
  let r_lines = pad r_lines n in
  List.map2 (fun l r -> l ^ "  " ^ r) l_lines r_lines |> String.concat "\n"

let too_small_msg = "Resize terminal — needs at least 60×20"

let render (s : Model.state) ~size =
  let cols = size.LTerm_geom.cols in
  let rows = size.LTerm_geom.rows in
  if cols < 60 || rows < 20 then too_small_msg
  else begin
    let panel_visible = s.show_panel in
    let panel_cols = if panel_visible then panel_width + 2 else 0 in
    let frame_cols = max 20 (cols - panel_cols) in
    let frame_rows = rows - 2 in
    let mode = frame_pixel_mode () in
    let px_x, px_y = mode_px_per_cell mode in
    let px_w = frame_cols * px_x in
    let px_h = frame_rows * px_y in
    let bytes = build_frame s ~px_w ~px_h in
    let fb = FB.create () in
    FB.blit fb ~src:bytes ~width:px_w ~height:px_h ;
    let frame =
      FB.render_with_mode fb ~mode ~cols:frame_cols ~rows:frame_rows
    in
    let header =
      let title = W.themed_emphasis "MIAOU SOLAR SYSTEM" in
      let pad = max 0 ((cols - visible_width title) / 2) in
      String.make pad ' ' ^ title
    in
    let body =
      if panel_visible then
        let panel = build_panel s ~rows:frame_rows in
        compose_left_right ~left:frame ~right:panel
      else frame
    in
    let footer =
      W.themed_muted
        "1-5 speed · p pause · o orbits · l labels · r reset · Tab panel · Esc back"
    in
    String.concat "\n" [header; body; footer]
  end
