open Alcotest
module OC = Miaou_widgets_display.Octant_canvas

let test_create_dimensions () =
  let c = OC.create ~width:3 ~height:2 in
  check (pair int int) "cell dimensions" (3, 2) (OC.get_dimensions c) ;
  check
    (pair int int)
    "dot dimensions are 2x/4x cell dimensions"
    (6, 8)
    (OC.get_dot_dimensions c)

let test_set_get_clear_dot_roundtrip () =
  let c = OC.create ~width:2 ~height:2 in
  check bool "dot starts unset" false (OC.get_dot c ~x:0 ~y:0) ;
  OC.set_dot c ~x:0 ~y:0 ~color:None ;
  check bool "dot is set after set_dot" true (OC.get_dot c ~x:0 ~y:0) ;
  OC.clear_dot c ~x:0 ~y:0 ;
  check bool "dot is unset after clear_dot" false (OC.get_dot c ~x:0 ~y:0)

let test_set_dot_out_of_bounds_is_silently_ignored () =
  let c = OC.create ~width:1 ~height:1 in
  (* Must not raise. *)
  OC.set_dot c ~x:100 ~y:100 ~color:None ;
  OC.set_dot c ~x:(-1) ~y:(-1) ~color:None ;
  check
    bool
    "get_dot out of bounds is false, not a crash"
    false
    (OC.get_dot c ~x:100 ~y:100)

let test_clear_resets_all_dots () =
  let c = OC.create ~width:2 ~height:2 in
  OC.set_dot c ~x:0 ~y:0 ~color:None ;
  OC.set_dot c ~x:3 ~y:7 ~color:None ;
  OC.clear c ;
  check bool "dot (0,0) cleared" false (OC.get_dot c ~x:0 ~y:0) ;
  check bool "dot (3,7) cleared" false (OC.get_dot c ~x:3 ~y:7)

let test_draw_line_sets_endpoints () =
  let c = OC.create ~width:4 ~height:4 in
  OC.draw_line c ~x0:0 ~y0:0 ~x1:6 ~y1:0 ~color:None ;
  check bool "line start is set" true (OC.get_dot c ~x:0 ~y:0) ;
  check bool "line end is set" true (OC.get_dot c ~x:6 ~y:0) ;
  check
    bool
    "a mid-point on a horizontal line is set"
    true
    (OC.get_dot c ~x:3 ~y:0)

let test_draw_line_single_point () =
  let c = OC.create ~width:2 ~height:2 in
  OC.draw_line c ~x0:1 ~y0:1 ~x1:1 ~y1:1 ~color:None ;
  check
    bool
    "degenerate line (same start/end) sets that one dot"
    true
    (OC.get_dot c ~x:1 ~y:1)

let test_add_cell_bits_ors_into_existing_pattern () =
  let c = OC.create ~width:1 ~height:1 in
  OC.set_dot c ~x:0 ~y:0 ~color:None ;
  (* bit 3 (0x08) corresponds to dot (1,1) within the cell. *)
  OC.add_cell_bits c ~cell_x:0 ~cell_y:0 ~bits:0x08 ~color:None ;
  check
    bool
    "originally-set dot (0,0) survives the OR"
    true
    (OC.get_dot c ~x:0 ~y:0) ;
  check bool "newly OR'd dot (1,1) is now set" true (OC.get_dot c ~x:1 ~y:1)

let test_glyph_of_pattern_boundaries () =
  check string "pattern 0x00 is a space" " " (OC.glyph_of_pattern 0x00) ;
  check
    string
    "pattern 0xFF is the full block"
    "\xe2\x96\x88"
    (OC.glyph_of_pattern 0xFF) ;
  let mid = OC.glyph_of_pattern 0x01 in
  check
    bool
    "an intermediate pattern is non-empty and not the space glyph"
    true
    (String.length mid > 0 && mid <> " ")

let test_render_reflects_content_and_color () =
  let blank = OC.create ~width:2 ~height:1 in
  let blank_out = OC.render blank in
  check
    bool
    "an all-blank canvas renders as spaces only"
    true
    (String.for_all (fun c -> c = ' ') blank_out) ;
  let colored = OC.create ~width:1 ~height:1 in
  OC.set_dot colored ~x:0 ~y:0 ~color:(Some "32") ;
  let colored_out = OC.render colored in
  check
    bool
    "a colored dot's render includes the SGR color code"
    true
    (Test_helpers.contains_substring colored_out "32") ;
  check
    bool
    "a colored dot's render includes a reset code"
    true
    (Test_helpers.contains_substring colored_out "\027[0m")

let test_render_line_count_matches_height () =
  let c = OC.create ~width:2 ~height:3 in
  let out = OC.render c in
  let lines = String.split_on_char '\n' out in
  check int "render emits one line per canvas row" 3 (List.length lines)

let () =
  run
    "octant_canvas"
    [
      ( "octant_canvas",
        [
          test_case "create: dimensions" `Quick test_create_dimensions;
          test_case
            "set/get/clear dot roundtrip"
            `Quick
            test_set_get_clear_dot_roundtrip;
          test_case
            "set_dot out of bounds is silently ignored"
            `Quick
            test_set_dot_out_of_bounds_is_silently_ignored;
          test_case "clear resets all dots" `Quick test_clear_resets_all_dots;
          test_case
            "draw_line sets endpoints and mid-points"
            `Quick
            test_draw_line_sets_endpoints;
          test_case
            "draw_line handles a degenerate (single-point) line"
            `Quick
            test_draw_line_single_point;
          test_case
            "add_cell_bits ORs into the existing pattern"
            `Quick
            test_add_cell_bits_ors_into_existing_pattern;
          test_case
            "glyph_of_pattern boundary values"
            `Quick
            test_glyph_of_pattern_boundaries;
          test_case
            "render reflects content and color"
            `Quick
            test_render_reflects_content_and_color;
          test_case
            "render line count matches height"
            `Quick
            test_render_line_count_matches_height;
        ] );
    ]
