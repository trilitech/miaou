(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

let pi = Float.pi

let two_pi = 2.0 *. pi

let deg_to_rad d = d *. pi /. 180.0

let latlon_to_xyz lat_deg lon_deg =
  let lat = deg_to_rad lat_deg in
  let lon = deg_to_rad lon_deg in
  let cl = cos lat in
  (cl *. cos lon, sin lat, cl *. sin lon)

let haversine_km ~lat1 ~lon1 ~lat2 ~lon2 =
  let r = 6371.0 in
  let dlat = deg_to_rad (lat2 -. lat1) in
  let dlon = deg_to_rad (lon2 -. lon1) in
  let a =
    let s = sin (dlat /. 2.0) in
    let s2 = sin (dlon /. 2.0) in
    (s *. s) +. (cos (deg_to_rad lat1) *. cos (deg_to_rad lat2) *. s2 *. s2)
  in
  let a = max 0.0 (min 1.0 a) in
  2.0 *. r *. atan2 (sqrt a) (sqrt (1.0 -. a))

type t = {
  coastline : (float * float) array;
  is_land : (lat:float -> lon:float -> bool) option;
  yaw : float;
  pitch : float;
  rate : float; (* radians per second *)
}

let create ?is_land ~coastline () =
  {coastline; is_land; yaw = 0.0; pitch = 0.2; rate = two_pi /. 20.0}

let yaw t = t.yaw

let set_rotation t ~yaw ~pitch = {t with yaw; pitch}

let advance t ~dt =
  let yaw = mod_float (t.yaw +. (t.rate *. dt)) two_pi in
  {t with yaw}

(* Apply yaw (around y axis) then pitch (around x axis). *)
let rotate ~yaw ~pitch (x, y, z) =
  let cy = cos yaw and sy = sin yaw in
  let x1 = (x *. cy) +. (z *. sy) in
  let z1 = (-.x *. sy) +. (z *. cy) in
  let cp = cos pitch and sp = sin pitch in
  let y2 = (y *. cp) -. (z1 *. sp) in
  let z2 = (y *. sp) +. (z1 *. cp) in
  (x1, y2, z2)

(* Inverse of [rotate]: undo pitch then yaw to map a camera-space point back
   to model space (where lat/lon make sense). *)
let inv_rotate ~yaw ~pitch (xc, yc, zc) =
  let cp = cos pitch and sp = sin pitch in
  let yp = (yc *. cp) +. (zc *. sp) in
  let zp = (-.yc *. sp) +. (zc *. cp) in
  let cy = cos yaw and sy = sin yaw in
  let xm = (xc *. cy) -. (zp *. sy) in
  let zm = (xc *. sy) +. (zp *. cy) in
  (xm, yp, zm)

(* Pick a 256-color shade for a given diffuse term in [0..1].
   Uses the cube + greyscale ramp:
     bright land  → 226 (yellow)
     mid          → 220, 214 (gold→amber)
     limb         → 240, 244 (greys)
   Returns Some "256;N" SGR payload or None for very dark. *)
let shade_color diffuse =
  if diffuse <= 0.0 then None
  else if diffuse >= 0.85 then Some "38;5;226"
  else if diffuse >= 0.65 then Some "38;5;220"
  else if diffuse >= 0.45 then Some "38;5;214"
  else if diffuse >= 0.25 then Some "38;5;208"
  else Some "38;5;130"

let limb_color = Some "38;5;75"

(* Ocean blue ramp by Lambert diffuse (in screen space — sun fixed at the
   right of the viewport, so the right side stays bright as the globe
   rotates underneath). *)
let ocean_color diffuse =
  if diffuse <= 0.05 then Some "38;5;17"
  else if diffuse <= 0.2 then Some "38;5;18"
  else if diffuse <= 0.4 then Some "38;5;19"
  else if diffuse <= 0.6 then Some "38;5;20"
  else if diffuse <= 0.8 then Some "38;5;26"
  else if diffuse <= 0.95 then Some "38;5;33"
  else Some "38;5;75"

(* Sand/earth ramp for filled continents — same Lambert idea as the ocean. *)
let land_fill_color diffuse =
  if diffuse <= 0.05 then Some "38;5;58"
  else if diffuse <= 0.2 then Some "38;5;94"
  else if diffuse <= 0.4 then Some "38;5;130"
  else if diffuse <= 0.6 then Some "38;5;172"
  else if diffuse <= 0.8 then Some "38;5;214"
  else if diffuse <= 0.95 then Some "38;5;220"
  else Some "38;5;226"

let render t ~cols ~rows =
  let canvas = Octant_canvas.create ~width:cols ~height:rows in
  let dot_w = cols * 2 in
  let dot_h = rows * 4 in
  let cx = float_of_int dot_w /. 2.0 in
  let cy = float_of_int dot_h /. 2.0 in
  (* Aspect: terminal cells are roughly 2× taller than wide, octant gives
     2 dots wide × 4 dots tall per cell so dots are ~equally spaced. Use
     a slightly squashed radius to keep the projection roughly circular. *)
  let radius = Float.min cx cy -. 1.5 in
  (* 0) Ocean fill — flood every cell whose centre lies inside the
     inscribed disc with a Lambert-shaded blue. The shading is in screen
     space so the sun stays on the right, and the coastline highlights
     drawn later sweep across the lit hemisphere as the globe rotates. *)
  let r2 = radius *. radius in
  for cy_c = 0 to rows - 1 do
    for cx_c = 0 to cols - 1 do
      let dx = float_of_int ((cx_c * 2) + 1) -. cx in
      let dy = float_of_int ((cy_c * 4) + 2) -. cy in
      let d2 = (dx *. dx) +. (dy *. dy) in
      if d2 <= r2 then begin
        let nx = dx /. radius in
        let ny = -.dy /. radius in
        let nz = sqrt (Float.max 0.0 (1.0 -. (nx *. nx) -. (ny *. ny))) in
        let diffuse = Float.max 0.0 nx in
        let is_land =
          match t.is_land with
          | None -> false
          | Some f ->
              let xm, ym, zm =
                inv_rotate ~yaw:t.yaw ~pitch:t.pitch (nx, ny, nz)
              in
              let lat =
                asin (Float.max (-1.0) (Float.min 1.0 ym)) *. 180.0 /. pi
              in
              let lon = atan2 zm xm *. 180.0 /. pi in
              f ~lat ~lon
        in
        let color =
          if is_land then land_fill_color diffuse else ocean_color diffuse
        in
        for j = 0 to 3 do
          for i = 0 to 1 do
            Octant_canvas.set_dot
              canvas
              ~x:((cx_c * 2) + i)
              ~y:((cy_c * 4) + j)
              ~color
          done
        done
      end
    done
  done ;
  (* 1) Limb: faint outline circle. *)
  let n_limb = 360 in
  for i = 0 to n_limb - 1 do
    let theta = float_of_int i *. two_pi /. float_of_int n_limb in
    let x = cx +. (radius *. cos theta) in
    let y = cy +. (radius *. sin theta) in
    Octant_canvas.set_dot
      canvas
      ~x:(int_of_float x)
      ~y:(int_of_float y)
      ~color:limb_color
  done ;
  (* 2) Graticule — equator and prime meridian (rotated). *)
  let project x y z =
    if z < 0.0 then None
    else
      let sx = cx +. (x *. radius) in
      let sy = cy -. (y *. radius) in
      Some (int_of_float sx, int_of_float sy)
  in
  let plot_graticule lat_deg lon_deg color =
    let xyz =
      rotate ~yaw:t.yaw ~pitch:t.pitch (latlon_to_xyz lat_deg lon_deg)
    in
    let x, y, z = xyz in
    match project x y z with
    | None -> ()
    | Some (sx, sy) -> Octant_canvas.set_dot canvas ~x:sx ~y:sy ~color
  in
  (* equator *)
  for i = 0 to 359 do
    plot_graticule 0.0 (float_of_int i -. 180.0) (Some "38;5;240")
  done ;
  (* meridians every 30° *)
  for m = 0 to 11 do
    let lon = (float_of_int m *. 30.0) -. 180.0 in
    let i = ref (-90) in
    while !i <= 90 do
      plot_graticule (float_of_int !i) lon (Some "38;5;238") ;
      incr i
    done
  done ;
  (* 3) Coastline overlay — only when no land classifier is supplied. With
     [is_land] the per-cell fill already paints filled continents in the
     correct shade; redrawing 60K coastline points on top would just add
     visual noise (and substantial per-frame work). *)
  (match t.is_land with
  | Some _ -> ()
  | None ->
      Array.iter
        (fun (lat, lon) ->
          let xyz = rotate ~yaw:t.yaw ~pitch:t.pitch (latlon_to_xyz lat lon) in
          let x, y, z = xyz in
          match project x y z with
          | None -> ()
          | Some (sx, sy) ->
              let diffuse = x in
              let color = shade_color diffuse in
              Octant_canvas.set_dot canvas ~x:sx ~y:sy ~color)
        t.coastline) ;
  Octant_canvas.render canvas

let () =
  Miaou_registry.register ~name:"globe" ~mli:[%blob "globe_widget.mli"] ()
