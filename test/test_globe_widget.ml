open Alcotest
module G = Miaou_widgets_display.Globe_widget

let approx ?(eps = 1e-6) a b = Float.abs (a -. b) < eps

let test_xyz_north_pole () =
  let x, y, z = G.latlon_to_xyz 90.0 0.0 in
  check bool "x≈0" true (approx ~eps:1e-9 x 0.0) ;
  check bool "y≈1" true (approx ~eps:1e-9 y 1.0) ;
  check bool "z≈0" true (approx ~eps:1e-9 z 0.0)

let test_xyz_equator_origin () =
  let x, y, z = G.latlon_to_xyz 0.0 0.0 in
  check bool "x≈1" true (approx x 1.0) ;
  check bool "y≈0" true (approx y 0.0) ;
  check bool "z≈0" true (approx z 0.0)

let test_xyz_equator_east () =
  let _, _, z = G.latlon_to_xyz 0.0 90.0 in
  check bool "z≈1 at lon=90" true (approx z 1.0)

let test_haversine_paris_lyon () =
  (* Paris: 48.8566, 2.3522 ; Lyon: 45.7640, 4.8357. Reference ~391 km. *)
  let d =
    G.haversine_km ~lat1:48.8566 ~lon1:2.3522 ~lat2:45.7640 ~lon2:4.8357
  in
  check
    bool
    (Printf.sprintf "Paris-Lyon ~391 km, got %.1f" d)
    true
    (Float.abs (d -. 391.0) < 5.0)

let test_haversine_london_ny () =
  (* London 51.5074,-0.1278 ; NY 40.7128,-74.0060. Reference ~5570 km. *)
  let d =
    G.haversine_km ~lat1:51.5074 ~lon1:(-0.1278) ~lat2:40.7128 ~lon2:(-74.0060)
  in
  check
    bool
    (Printf.sprintf "London-NY ~5570 km, got %.1f" d)
    true
    (Float.abs (d -. 5570.0) < 30.0)

let test_haversine_zero () =
  let d = G.haversine_km ~lat1:10.0 ~lon1:20.0 ~lat2:10.0 ~lon2:20.0 in
  check bool "zero distance" true (d < 1e-3)

let test_advance_monotonic () =
  let g0 = G.create ~coastline:[||] () in
  let g1 = G.advance g0 ~dt:0.5 in
  let g2 = G.advance g1 ~dt:0.5 in
  check bool "yaw advances after 0.5s" true (G.yaw g1 > G.yaw g0) ;
  check bool "yaw advances after 1.0s total" true (G.yaw g2 > G.yaw g1)

let test_advance_wraps () =
  (* After many seconds yaw should wrap into [0, 2π). *)
  let g = G.create ~coastline:[||] () in
  let g = G.advance g ~dt:50.0 in
  check
    bool
    "yaw within [0, 2π)"
    true
    (G.yaw g >= 0.0 && G.yaw g < 2.0 *. Float.pi)

let test_render_nonempty () =
  (* Sample coastline: a triangle around the prime meridian at the equator
     should always show *something* on the front. *)
  let coast = [|(0.0, 0.0); (10.0, 0.0); (-10.0, 0.0); (0.0, 10.0)|] in
  let g = G.create ~coastline:coast () in
  let g = G.set_rotation g ~yaw:0.0 ~pitch:0.0 in
  let s = G.render g ~cols:30 ~rows:15 in
  check bool "render non-empty" true (String.length s > 0) ;
  (* Should contain at least one non-space char (any printable utf-8). *)
  let has_nonspace =
    let any = ref false in
    String.iter
      (fun c -> if not (c = ' ' || c = '\n' || c = '\x1b') then any := true)
      s ;
    !any
  in
  check bool "render has visible glyphs" true has_nonspace

let test_set_rotation () =
  let g = G.create ~coastline:[||] () in
  let g' = G.set_rotation g ~yaw:1.0 ~pitch:0.5 in
  check bool "yaw set" true (Float.abs (G.yaw g' -. 1.0) < 1e-9)

let () =
  run
    "globe_widget"
    [
      ( "latlon_to_xyz",
        [
          test_case "north pole" `Quick test_xyz_north_pole;
          test_case "equator at lon 0" `Quick test_xyz_equator_origin;
          test_case "equator at lon 90" `Quick test_xyz_equator_east;
        ] );
      ( "haversine",
        [
          test_case "Paris-Lyon" `Quick test_haversine_paris_lyon;
          test_case "London-NY" `Quick test_haversine_london_ny;
          test_case "self distance is zero" `Quick test_haversine_zero;
        ] );
      ( "rotation",
        [
          test_case "advance is monotonic" `Quick test_advance_monotonic;
          test_case "advance wraps modulo 2π" `Quick test_advance_wraps;
          test_case "set_rotation" `Quick test_set_rotation;
        ] );
      ("render", [test_case "non-empty output" `Quick test_render_nonempty]);
    ]
