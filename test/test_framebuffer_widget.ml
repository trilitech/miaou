open Alcotest
module FB = Miaou_widgets_display.Framebuffer_widget
module Caps = Miaou_widgets_display.Terminal_caps

(* Deterministic fallback paths only: [render_with_mode] bypasses terminal
   auto-detection (which depends on the environment / TTY caps and is not
   deterministic in a test runner), so every case below picks an explicit
   [Terminal_caps.render_mode]. Sixel and Kitty pixel emission, and real
   SDL rendering, are excluded per the test-debt plan's scope. *)

let test_clear_and_render_half_block_is_deterministic_blank () =
  let fb = FB.create () in
  FB.clear fb ~r:0 ~g:0 ~b:0 ;
  let out1 = FB.render_with_mode fb ~mode:Caps.Half_block ~cols:4 ~rows:2 in
  let out2 = FB.render_with_mode fb ~mode:Caps.Half_block ~cols:4 ~rows:2 in
  check string "rendering an unchanged buffer twice is stable" out1 out2 ;
  check bool "render is non-empty" true (String.length out1 > 0)

let test_fill_rect_changes_the_render () =
  let fb = FB.create () in
  FB.clear fb ~r:0 ~g:0 ~b:0 ;
  let blank = FB.render_with_mode fb ~mode:Caps.Half_block ~cols:4 ~rows:2 in
  FB.fill_rect fb ~x:0 ~y:0 ~w:8 ~h:8 ~r:255 ~g:0 ~b:0 ;
  let filled = FB.render_with_mode fb ~mode:Caps.Half_block ~cols:4 ~rows:2 in
  check bool "filling a rect changes the rendered output" true (blank <> filled)

let test_set_pixel_out_of_bounds_does_not_raise () =
  let fb = FB.create () in
  FB.clear fb ~r:0 ~g:0 ~b:0 ;
  (* Out-of-bounds writes are documented as clamped; must not raise. *)
  FB.set_pixel fb ~x:100_000 ~y:100_000 ~r:255 ~g:255 ~b:255 ;
  ignore (FB.render_with_mode fb ~mode:Caps.Half_block ~cols:2 ~rows:2)

let test_blit_replaces_buffer_dimensions () =
  let fb = FB.create () in
  let width = 4 and height = 4 in
  let src = Bytes.make (width * height * 3) '\000' in
  FB.blit fb ~src ~width ~height ;
  let out = FB.render_with_mode fb ~mode:Caps.Half_block ~cols:2 ~rows:2 in
  check
    bool
    "rendering after blit succeeds and is non-empty"
    true
    (String.length out > 0)

let test_render_with_mode_octant_and_sextant_are_deterministic () =
  let fb = FB.create () in
  FB.clear fb ~r:0 ~g:0 ~b:0 ;
  FB.fill_rect fb ~x:0 ~y:0 ~w:8 ~h:8 ~r:10 ~g:20 ~b:30 ;
  let octant1 = FB.render_with_mode fb ~mode:Caps.Octant ~cols:4 ~rows:2 in
  let octant2 = FB.render_with_mode fb ~mode:Caps.Octant ~cols:4 ~rows:2 in
  check
    string
    "Octant mode render is stable across repeated calls"
    octant1
    octant2 ;
  let sextant = FB.render_with_mode fb ~mode:Caps.Sextant ~cols:4 ~rows:2 in
  check
    bool
    "Sextant mode also produces non-empty output"
    true
    (String.length sextant > 0)

let test_render_caches_until_dirtied () =
  let fb = FB.create () in
  FB.clear fb ~r:0 ~g:0 ~b:0 ;
  let out1 = FB.render_with_mode fb ~mode:Caps.Half_block ~cols:3 ~rows:3 in
  (* Re-rendering with the same size and no intervening mutation must hit
     the documented cache and return identical output. *)
  let out2 = FB.render_with_mode fb ~mode:Caps.Half_block ~cols:3 ~rows:3 in
  check string "cached render is byte-identical" out1 out2 ;
  FB.set_pixel fb ~x:0 ~y:0 ~r:200 ~g:0 ~b:0 ;
  let out3 = FB.render_with_mode fb ~mode:Caps.Half_block ~cols:3 ~rows:3 in
  check bool "a pixel write invalidates the cache" true (out3 <> out1)

let () =
  run
    "framebuffer_widget"
    [
      ( "framebuffer_widget",
        [
          test_case
            "clear + render (Half_block) is deterministic"
            `Quick
            test_clear_and_render_half_block_is_deterministic_blank;
          test_case
            "fill_rect changes the render"
            `Quick
            test_fill_rect_changes_the_render;
          test_case
            "set_pixel out of bounds does not raise"
            `Quick
            test_set_pixel_out_of_bounds_does_not_raise;
          test_case
            "blit replaces buffer dimensions"
            `Quick
            test_blit_replaces_buffer_dimensions;
          test_case
            "Octant/Sextant fallback modes are deterministic"
            `Quick
            test_render_with_mode_octant_and_sextant_are_deterministic;
          test_case
            "render caches until the buffer is dirtied"
            `Quick
            test_render_caches_until_dirtied;
        ] );
    ]
