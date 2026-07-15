open Alcotest
module Spinner = Miaou_widgets_layout.Spinner_widget
module W = Miaou_widgets_display.Widgets

let test_render_dots_includes_label () =
  let s = Spinner.open_centered ~label:"Loading..." () in
  let out = Spinner.render ~backend:`Terminal s in
  check
    bool
    "render includes the label"
    true
    (Test_helpers.contains_substring out "Loading...")

let test_tick_cycles_dots_frames_deterministically () =
  (* Dots style has 10 frames; ticking exactly that many times must return
     to the first frame's rendered output. *)
  let s0 = Spinner.open_centered () in
  let out0 = Spinner.render ~backend:`Terminal s0 in
  let rec tick_n n s = if n <= 0 then s else tick_n (n - 1) (Spinner.tick s) in
  let s10 = tick_n 10 s0 in
  let out10 = Spinner.render ~backend:`Terminal s10 in
  check
    string
    "10 ticks of the 10-frame Dots cycle returns to frame 0"
    out0
    out10 ;
  let s1 = tick_n 1 s0 in
  let out1 = Spinner.render ~backend:`Terminal s1 in
  check bool "a single tick changes the rendered frame" true (out1 <> out0)

let test_set_label_updates_render () =
  let s = Spinner.open_centered ~label:"first" () in
  let s = Spinner.set_label s (Some "second") in
  let out = Spinner.render ~backend:`Terminal s in
  check
    bool
    "render reflects the updated label"
    true
    (Test_helpers.contains_substring out "second") ;
  check
    bool
    "render no longer contains the old label"
    false
    (Test_helpers.contains_substring out "first")

let test_set_label_none_removes_label () =
  let s = Spinner.open_centered ~label:"gone soon" () in
  let s = Spinner.set_label s None in
  let out = Spinner.render ~backend:`Terminal s in
  check
    bool
    "render no longer contains the removed label"
    false
    (Test_helpers.contains_substring out "gone soon")

let test_blocks_style_renders_glyphs () =
  let s = Spinner.open_centered ~style:Spinner.Blocks ~label:"Build" () in
  let out = Spinner.render ~backend:`Terminal s in
  check
    bool
    "Blocks style render includes the label"
    true
    (Test_helpers.contains_substring out "Build")

let test_set_style_switches_between_styles () =
  let s = Spinner.open_centered ~style:Spinner.Dots () in
  let dots_out = Spinner.render ~backend:`Terminal s in
  let s' = Spinner.set_style s Spinner.Blocks in
  let blocks_out = Spinner.render ~backend:`Terminal s' in
  check
    bool
    "switching style changes the rendered output"
    true
    (dots_out <> blocks_out)

let test_render_truncates_to_configured_width () =
  let s = Spinner.open_centered ~width:10 ~label:(String.make 50 'x') () in
  let out = Spinner.render ~backend:`Terminal s in
  check
    bool
    "render is bounded to the configured width"
    true
    (W.visible_chars_count out <= 10)

let test_render_with_backend_matches_render_default () =
  let s = Spinner.open_centered ~label:"same" () in
  let via_render = Spinner.render ~backend:`Terminal s in
  let via_explicit = Spinner.render_with_backend `Terminal s in
  check
    string
    "render ~backend and render_with_backend agree"
    via_render
    via_explicit

let () =
  run
    "spinner_widget"
    [
      ( "spinner_widget",
        [
          test_case
            "render (Dots) includes the label"
            `Quick
            test_render_dots_includes_label;
          test_case
            "tick cycles Dots frames deterministically"
            `Quick
            test_tick_cycles_dots_frames_deterministically;
          test_case
            "set_label updates the render"
            `Quick
            test_set_label_updates_render;
          test_case
            "set_label None removes the label"
            `Quick
            test_set_label_none_removes_label;
          test_case
            "Blocks style renders with the label"
            `Quick
            test_blocks_style_renders_glyphs;
          test_case
            "set_style switches between styles"
            `Quick
            test_set_style_switches_between_styles;
          test_case
            "render truncates to the configured width"
            `Quick
            test_render_truncates_to_configured_width;
          test_case
            "render_with_backend matches render ~backend"
            `Quick
            test_render_with_backend_matches_render_default;
        ] );
    ]
