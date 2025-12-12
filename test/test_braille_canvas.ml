(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

open Alcotest
module Braille = Miaou_widgets_display.Braille_canvas

let test_create () =
  let canvas = Braille.create ~width:5 ~height:3 in
  let w, h = Braille.get_dimensions canvas in
  check int "width" 5 w ;
  check int "height" 3 h

let test_dot_dimensions () =
  let canvas = Braille.create ~width:5 ~height:3 in
  let w, h = Braille.get_dot_dimensions canvas in
  check int "dot width" 10 w ;
  check int "dot height" 12 h

let test_set_get_dot () =
  let canvas = Braille.create ~width:2 ~height:2 in
  Braille.set_dot canvas ~x:1 ~y:1 ;
  check bool "dot set" true (Braille.get_dot canvas ~x:1 ~y:1) ;
  check bool "other dot not set" false (Braille.get_dot canvas ~x:0 ~y:0)

let test_clear_dot () =
  let canvas = Braille.create ~width:2 ~height:2 in
  Braille.set_dot canvas ~x:1 ~y:1 ;
  Braille.clear_dot canvas ~x:1 ~y:1 ;
  check bool "dot cleared" false (Braille.get_dot canvas ~x:1 ~y:1)

let test_clear_canvas () =
  let canvas = Braille.create ~width:2 ~height:2 in
  Braille.set_dot canvas ~x:0 ~y:0 ;
  Braille.set_dot canvas ~x:1 ~y:1 ;
  Braille.clear canvas ;
  check bool "first dot cleared" false (Braille.get_dot canvas ~x:0 ~y:0) ;
  check bool "second dot cleared" false (Braille.get_dot canvas ~x:1 ~y:1)

let test_empty_render () =
  let canvas = Braille.create ~width:3 ~height:2 in
  let output = Braille.render canvas in
  (* Empty braille cells are U+2800, which is "⠀" *)
  (* 3 cells wide × 2 rows with newline = 3 braille chars + newline + 3 braille chars *)
  check bool "has output" true (String.length output > 0)

let test_single_dot_render () =
  let canvas = Braille.create ~width:1 ~height:1 in
  Braille.set_dot canvas ~x:0 ~y:0 ;
  let output = Braille.render canvas in
  (* Dot 1 is 0x2800 + 0x01 = 0x2801 = "⠁" *)
  check bool "not empty" true (String.length output > 0) ;
  check bool "contains braille" true (String.contains output '\226')

let test_horizontal_line () =
  let canvas = Braille.create ~width:3 ~height:1 in
  Braille.draw_line canvas ~x0:0 ~y0:0 ~x1:5 ~y1:0 ;
  check bool "start set" true (Braille.get_dot canvas ~x:0 ~y:0) ;
  check bool "middle set" true (Braille.get_dot canvas ~x:3 ~y:0) ;
  check bool "end set" true (Braille.get_dot canvas ~x:5 ~y:0)

let test_vertical_line () =
  let canvas = Braille.create ~width:1 ~height:2 in
  Braille.draw_line canvas ~x0:0 ~y0:0 ~x1:0 ~y1:6 ;
  check bool "start set" true (Braille.get_dot canvas ~x:0 ~y:0) ;
  check bool "middle set" true (Braille.get_dot canvas ~x:0 ~y:3) ;
  check bool "end set" true (Braille.get_dot canvas ~x:0 ~y:6)

let test_diagonal_line () =
  let canvas = Braille.create ~width:3 ~height:2 in
  Braille.draw_line canvas ~x0:0 ~y0:0 ~x1:5 ~y1:7 ;
  check bool "start set" true (Braille.get_dot canvas ~x:0 ~y:0) ;
  check bool "end set" true (Braille.get_dot canvas ~x:5 ~y:7)

let test_out_of_bounds () =
  let canvas = Braille.create ~width:2 ~height:2 in
  Braille.set_dot canvas ~x:100 ~y:100 ;
  check
    bool
    "out of bounds ignored"
    false
    (Braille.get_dot canvas ~x:100 ~y:100) ;
  Braille.set_dot canvas ~x:(-1) ~y:(-1) ;
  check
    bool
    "negative bounds ignored"
    false
    (Braille.get_dot canvas ~x:(-1) ~y:(-1))

let test_add_cell_bits () =
  let canvas = Braille.create ~width:1 ~height:1 in
  Braille.add_cell_bits canvas ~cell_x:0 ~cell_y:0 0x01 ;
  check bool "dot via cell bits" true (Braille.get_dot canvas ~x:0 ~y:0)

let test_render_with_callback () =
  let canvas = Braille.create ~width:2 ~height:1 in
  let calls = ref 0 in
  let _ =
    Braille.render_with canvas ~f:(fun ~x:_ ~y:_ ch ->
        incr calls ;
        ch)
  in
  check int "callback count" 2 !calls

let suite =
  [
    test_case "create" `Quick test_create;
    test_case "dot dimensions" `Quick test_dot_dimensions;
    test_case "set and get dot" `Quick test_set_get_dot;
    test_case "clear dot" `Quick test_clear_dot;
    test_case "clear canvas" `Quick test_clear_canvas;
    test_case "empty render" `Quick test_empty_render;
    test_case "single dot render" `Quick test_single_dot_render;
    test_case "horizontal line" `Quick test_horizontal_line;
    test_case "vertical line" `Quick test_vertical_line;
    test_case "diagonal line" `Quick test_diagonal_line;
    test_case "out of bounds" `Quick test_out_of_bounds;
    test_case "add cell bits" `Quick test_add_cell_bits;
    test_case "render with callback" `Quick test_render_with_callback;
  ]

let () = run "braille_canvas" [("braille_canvas", suite)]
