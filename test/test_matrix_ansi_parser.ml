(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

open Alcotest
module Parser = Miaou_driver_matrix.Matrix_ansi_parser
module Buffer = Miaou_driver_matrix.Matrix_buffer
module Cell = Miaou_driver_matrix.Matrix_cell

(* Helper to create a buffer and parser *)
let make_test_env ~rows ~cols =
  let buf = Buffer.create ~rows ~cols in
  let parser = Parser.create () in
  (buf, parser)

(* Helper to get cell char at position *)
let get_char buf row col = (Buffer.get_back buf ~row ~col).Cell.char

(* Helper to get cell style at position *)
let get_style buf row col = (Buffer.get_back buf ~row ~col).Cell.style

(* ============== Plain Text Tests ============== *)

let test_plain_text () =
  let buf, parser = make_test_env ~rows:1 ~cols:20 in
  let col = Parser.parse_line parser buf ~row:0 ~col:0 "Hello" in
  check int "advances 5 cols" 5 col ;
  check string "cell 0" "H" (get_char buf 0 0) ;
  check string "cell 1" "e" (get_char buf 0 1) ;
  check string "cell 2" "l" (get_char buf 0 2) ;
  check string "cell 3" "l" (get_char buf 0 3) ;
  check string "cell 4" "o" (get_char buf 0 4) ;
  check string "cell 5 empty" " " (get_char buf 0 5)

let test_empty_string () =
  let buf, parser = make_test_env ~rows:1 ~cols:10 in
  let col = Parser.parse_line parser buf ~row:0 ~col:0 "" in
  check int "no advance" 0 col ;
  check string "cell 0 empty" " " (get_char buf 0 0)

let test_spaces () =
  let buf, parser = make_test_env ~rows:1 ~cols:10 in
  let col = Parser.parse_line parser buf ~row:0 ~col:0 "a b c" in
  check int "advances 5" 5 col ;
  check string "cell 0" "a" (get_char buf 0 0) ;
  check string "cell 1 space" " " (get_char buf 0 1) ;
  check string "cell 2" "b" (get_char buf 0 2)

(* ============== UTF-8 Tests ============== *)

let test_utf8_simple () =
  let buf, parser = make_test_env ~rows:1 ~cols:20 in
  let col = Parser.parse_line parser buf ~row:0 ~col:0 "★" in
  check int "advances 1" 1 col ;
  check string "star char" "★" (get_char buf 0 0)

let test_utf8_mixed () =
  let buf, parser = make_test_env ~rows:1 ~cols:20 in
  let col = Parser.parse_line parser buf ~row:0 ~col:0 "A★B" in
  check int "advances 3" 3 col ;
  check string "cell 0" "A" (get_char buf 0 0) ;
  check string "cell 1" "★" (get_char buf 0 1) ;
  check string "cell 2" "B" (get_char buf 0 2)

let test_utf8_emoji () =
  let buf, parser = make_test_env ~rows:1 ~cols:20 in
  let col = Parser.parse_line parser buf ~row:0 ~col:0 "🐱" in
  check int "advances 1" 1 col ;
  check string "cat emoji" "🐱" (get_char buf 0 0)

let test_utf8_accents () =
  let buf, parser = make_test_env ~rows:1 ~cols:20 in
  let col = Parser.parse_line parser buf ~row:0 ~col:0 "café" in
  check int "advances 4" 4 col ;
  check string "cell 3" "é" (get_char buf 0 3)

(* ============== Basic Color Tests ============== *)

let test_bold () =
  let buf, parser = make_test_env ~rows:1 ~cols:20 in
  let input = "\027[1mBold\027[0m" in
  let col = Parser.parse_line parser buf ~row:0 ~col:0 input in
  check int "advances 4" 4 col ;
  check string "cell 0" "B" (get_char buf 0 0) ;
  check bool "cell 0 bold" true (get_style buf 0 0).bold ;
  (* After reset, style should be default *)
  let final_style = Parser.current_style parser in
  check bool "final not bold" false final_style.bold

let test_dim () =
  let buf, parser = make_test_env ~rows:1 ~cols:20 in
  let input = "\027[2mDim\027[0m" in
  let _ = Parser.parse_line parser buf ~row:0 ~col:0 input in
  check bool "cell 0 dim" true (get_style buf 0 0).dim

let test_fg_256_color () =
  let buf, parser = make_test_env ~rows:1 ~cols:20 in
  (* 38;5;196 is red in 256-color palette *)
  let input = "\027[38;5;196mRed\027[0m" in
  let col = Parser.parse_line parser buf ~row:0 ~col:0 input in
  check int "advances 3" 3 col ;
  check int "fg color 196" 196 (get_style buf 0 0).fg

let test_bg_256_color () =
  let buf, parser = make_test_env ~rows:1 ~cols:20 in
  (* 48;5;238 is dark gray background *)
  let input = "\027[48;5;238mDark\027[0m" in
  let _ = Parser.parse_line parser buf ~row:0 ~col:0 input in
  check int "bg color 238" 238 (get_style buf 0 0).bg

let test_basic_fg_colors () =
  let buf, parser = make_test_env ~rows:1 ~cols:20 in
  (* 31 = red foreground (basic) *)
  let input = "\027[31mX\027[0m" in
  let _ = Parser.parse_line parser buf ~row:0 ~col:0 input in
  check int "fg color 1 (red)" 1 (get_style buf 0 0).fg

let test_basic_bg_colors () =
  let buf, parser = make_test_env ~rows:1 ~cols:20 in
  (* 44 = blue background (basic) *)
  let input = "\027[44mX\027[0m" in
  let _ = Parser.parse_line parser buf ~row:0 ~col:0 input in
  check int "bg color 4 (blue)" 4 (get_style buf 0 0).bg

(* ============== Combined Style Tests ============== *)

let test_combined_bold_color () =
  let buf, parser = make_test_env ~rows:1 ~cols:20 in
  (* Bold + cyan foreground *)
  let input = "\027[1;38;5;75mText\027[0m" in
  let _ = Parser.parse_line parser buf ~row:0 ~col:0 input in
  let style = get_style buf 0 0 in
  check bool "bold" true style.bold ;
  check int "fg 75" 75 style.fg

let test_nested_styles () =
  let buf, parser = make_test_env ~rows:1 ~cols:20 in
  (* Start bold, add color, then more text *)
  let input = "\027[1mA\027[38;5;196mB\027[0mC" in
  let _ = Parser.parse_line parser buf ~row:0 ~col:0 input in
  (* A should be bold, default color *)
  check bool "A bold" true (get_style buf 0 0).bold ;
  check int "A fg default" (-1) (get_style buf 0 0).fg ;
  (* B should be bold + red *)
  check bool "B bold" true (get_style buf 0 1).bold ;
  check int "B fg 196" 196 (get_style buf 0 1).fg ;
  (* C should be default *)
  check bool "C not bold" false (get_style buf 0 2).bold ;
  check int "C fg default" (-1) (get_style buf 0 2).fg

(* ============== Reset Tests ============== *)

let test_reset () =
  let buf, parser = make_test_env ~rows:1 ~cols:20 in
  let input = "\027[38;5;196mRed\027[0mNormal" in
  let _ = Parser.parse_line parser buf ~row:0 ~col:0 input in
  check int "Red fg" 196 (get_style buf 0 0).fg ;
  check int "Normal fg default" (-1) (get_style buf 0 3).fg

let test_partial_reset () =
  let buf, parser = make_test_env ~rows:1 ~cols:20 in
  (* Bold + color, then reset bold only (22) *)
  let input = "\027[1;38;5;75mA\027[22mB\027[0m" in
  let _ = Parser.parse_line parser buf ~row:0 ~col:0 input in
  check bool "A bold" true (get_style buf 0 0).bold ;
  check int "A fg 75" 75 (get_style buf 0 0).fg ;
  check bool "B not bold" false (get_style buf 0 1).bold ;
  check int "B fg still 75" 75 (get_style buf 0 1).fg

(* ============== Edge Cases ============== *)

let test_only_ansi_codes () =
  let buf, parser = make_test_env ~rows:1 ~cols:10 in
  let input = "\027[1m\027[38;5;75m\027[0m" in
  let col = Parser.parse_line parser buf ~row:0 ~col:0 input in
  check int "no visible chars" 0 col

let test_truncated_escape () =
  let buf, parser = make_test_env ~rows:1 ~cols:20 in
  (* Just ESC without [ - parser skips ESC and the next char *)
  let input = "\027X" in
  let col = Parser.parse_line parser buf ~row:0 ~col:0 input in
  (* ESC without [ is ignored, X is also consumed as part of recovery *)
  check int "truncated escape consumed" 0 col ;
  (* Test with visible text after *)
  Parser.reset parser ;
  let col2 = Parser.parse_line parser buf ~row:0 ~col:0 "\027XABC" in
  check int "recovers and parses ABC" 3 col2

let test_malformed_csi () =
  let buf, parser = make_test_env ~rows:1 ~cols:20 in
  (* CSI without proper terminator *)
  let input = "\027[1;2xABC" in
  let col = Parser.parse_line parser buf ~row:0 ~col:0 input in
  (* Should recover and parse ABC *)
  check int "parses ABC" 3 col ;
  check string "cell 0" "A" (get_char buf 0 0)

(* ============== Multiline Tests ============== *)

let test_multiline () =
  let buf, parser = make_test_env ~rows:3 ~cols:10 in
  let row, col = Parser.parse_into parser buf ~row:0 ~col:0 "A\nB\nC" in
  check int "final row" 2 row ;
  check int "final col" 1 col ;
  check string "row 0" "A" (get_char buf 0 0) ;
  check string "row 1" "B" (get_char buf 1 0) ;
  check string "row 2" "C" (get_char buf 2 0)

let test_multiline_with_styles () =
  let buf, parser = make_test_env ~rows:2 ~cols:20 in
  let input = "\027[1mBold\027[0m\n\027[2mDim\027[0m" in
  let _, _ = Parser.parse_into parser buf ~row:0 ~col:0 input in
  check bool "row 0 bold" true (get_style buf 0 0).bold ;
  check bool "row 1 dim" true (get_style buf 1 0).dim

(* ============== Visible Length Tests ============== *)

let test_visible_length_plain () =
  let len = Parser.visible_length "Hello" in
  check int "plain 5" 5 len

let test_visible_length_with_ansi () =
  let len = Parser.visible_length "\027[1mHello\027[0m" in
  check int "with ansi 5" 5 len

let test_visible_length_complex () =
  let len = Parser.visible_length "\027[38;5;196mRed\027[0m Normal" in
  check int "complex 10" 10 len

let test_visible_length_utf8 () =
  let len = Parser.visible_length "★ Star" in
  check int "utf8 6" 6 len

(* ============== OSC Sequence Tests ============== *)

let test_osc8_hyperlink_skipped () =
  let buf, parser = make_test_env ~rows:1 ~cols:40 in
  (* OSC 8 hyperlink: ESC]8;;url ESC\ display ESC]8;; ESC\ *)
  let input = "\027]8;;https://example.com\027\\click\027]8;;\027\\" in
  let col = Parser.parse_line parser buf ~row:0 ~col:0 input in
  (* Only "click" (5 chars) should be visible *)
  check int "osc8 visible 5" 5 col ;
  check string "cell 0" "c" (get_char buf 0 0) ;
  check string "cell 1" "l" (get_char buf 0 1) ;
  check string "cell 4" "k" (get_char buf 0 4) ;
  check string "cell 5 empty" " " (get_char buf 0 5) ;
  (* URL should be attached to display cells *)
  check string "cell 0 url" "https://example.com" (get_style buf 0 0).url ;
  check string "cell 4 url" "https://example.com" (get_style buf 0 4).url ;
  (* After the hyperlink close, URL should be empty *)
  check string "cell 5 no url" "" (get_style buf 0 5).url

let test_osc8_with_styled_display () =
  let buf, parser = make_test_env ~rows:1 ~cols:40 in
  (* Hyperlink wrapping bold display text *)
  let input = "\027]8;;https://x.com\027\\\027[1mbold\027[0m\027]8;;\027\\" in
  let col = Parser.parse_line parser buf ~row:0 ~col:0 input in
  check int "styled hyperlink visible 4" 4 col ;
  check string "cell 0" "b" (get_char buf 0 0) ;
  check bool "cell 0 bold" true (get_style buf 0 0).bold ;
  (* URL survives SGR reset (OSC 8 is not SGR) *)
  check string "cell 0 url" "https://x.com" (get_style buf 0 0).url ;
  check string "cell 3 url" "https://x.com" (get_style buf 0 3).url

let test_osc8_bel_terminated () =
  let buf, parser = make_test_env ~rows:1 ~cols:40 in
  (* OSC terminated by BEL (0x07) instead of ESC \ *)
  let input = "\027]8;;https://example.com\007click\027]8;;\007" in
  let col = Parser.parse_line parser buf ~row:0 ~col:0 input in
  check int "bel terminated visible 5" 5 col ;
  check string "cell 0" "c" (get_char buf 0 0)

let test_osc_mixed_with_csi () =
  let buf, parser = make_test_env ~rows:1 ~cols:40 in
  (* CSI color + OSC hyperlink *)
  let input = "\027[31mred\027[0m \027]8;;https://x\027\\link\027]8;;\027\\" in
  let col = Parser.parse_line parser buf ~row:0 ~col:0 input in
  (* "red" (3) + " " (1) + "link" (4) = 8 visible chars *)
  check int "mixed csi+osc visible 8" 8 col ;
  check int "red fg" 1 (get_style buf 0 0).fg ;
  check string "cell 4 link" "l" (get_char buf 0 4) ;
  (* "red" has no URL, "link" has URL *)
  check string "red no url" "" (get_style buf 0 0).url ;
  check string "link has url" "https://x" (get_style buf 0 4).url

let test_visible_length_osc8 () =
  let input = "\027]8;;https://example.com\027\\click\027]8;;\027\\" in
  let len = Parser.visible_length input in
  check int "osc8 visible_length 5" 5 len

let test_visible_length_mixed_csi_osc () =
  let input = "\027[31mred\027[0m \027]8;;https://x\027\\link\027]8;;\027\\" in
  let len = Parser.visible_length input in
  check int "mixed visible_length 8" 8 len

(* ============== Real Widget Output Tests ============== *)

let test_widget_bold () =
  let buf, parser = make_test_env ~rows:1 ~cols:20 in
  let input = Miaou_widgets_display.Widgets.bold "Test" in
  let col = Parser.parse_line parser buf ~row:0 ~col:0 input in
  check int "advances 4" 4 col ;
  check bool "is bold" true (get_style buf 0 0).bold

let test_widget_dim () =
  let buf, parser = make_test_env ~rows:1 ~cols:20 in
  let input = Miaou_widgets_display.Widgets.dim "Dim" in
  let col = Parser.parse_line parser buf ~row:0 ~col:0 input in
  check int "advances 3" 3 col ;
  check bool "is dim" true (get_style buf 0 0).dim

let test_widget_fg_color () =
  let buf, parser = make_test_env ~rows:1 ~cols:20 in
  let input = Miaou_widgets_display.Widgets.fg 75 "Cyan" in
  let col = Parser.parse_line parser buf ~row:0 ~col:0 input in
  check int "advances 4" 4 col ;
  check int "fg is 75" 75 (get_style buf 0 0).fg

let test_widget_bg_color () =
  let buf, parser = make_test_env ~rows:1 ~cols:20 in
  let input = Miaou_widgets_display.Widgets.bg 238 "Dark" in
  let col = Parser.parse_line parser buf ~row:0 ~col:0 input in
  check int "advances 4" 4 col ;
  check int "bg is 238" 238 (get_style buf 0 0).bg

let test_widget_red () =
  let buf, parser = make_test_env ~rows:1 ~cols:20 in
  let input = Miaou_widgets_display.Widgets.red "Error" in
  let col = Parser.parse_line parser buf ~row:0 ~col:0 input in
  check int "advances 5" 5 col ;
  (* red uses basic color 31 = index 1 *)
  check int "fg is red" 1 (get_style buf 0 0).fg

let test_widget_green () =
  let buf, parser = make_test_env ~rows:1 ~cols:20 in
  let input = Miaou_widgets_display.Widgets.green "OK" in
  let _ = Parser.parse_line parser buf ~row:0 ~col:0 input in
  check int "fg is green" 2 (get_style buf 0 0).fg

(* ============== Test Suite ============== *)

let plain_text_tests =
  [
    test_case "plain text" `Quick test_plain_text;
    test_case "empty string" `Quick test_empty_string;
    test_case "spaces" `Quick test_spaces;
  ]

let utf8_tests =
  [
    test_case "utf8 simple" `Quick test_utf8_simple;
    test_case "utf8 mixed" `Quick test_utf8_mixed;
    test_case "utf8 emoji" `Quick test_utf8_emoji;
    test_case "utf8 accents" `Quick test_utf8_accents;
  ]

let color_tests =
  [
    test_case "bold" `Quick test_bold;
    test_case "dim" `Quick test_dim;
    test_case "fg 256 color" `Quick test_fg_256_color;
    test_case "bg 256 color" `Quick test_bg_256_color;
    test_case "basic fg colors" `Quick test_basic_fg_colors;
    test_case "basic bg colors" `Quick test_basic_bg_colors;
  ]

let combined_tests =
  [
    test_case "combined bold color" `Quick test_combined_bold_color;
    test_case "nested styles" `Quick test_nested_styles;
  ]

let reset_tests =
  [
    test_case "reset" `Quick test_reset;
    test_case "partial reset" `Quick test_partial_reset;
  ]

let edge_case_tests =
  [
    test_case "only ansi codes" `Quick test_only_ansi_codes;
    test_case "truncated escape" `Quick test_truncated_escape;
    test_case "malformed csi" `Quick test_malformed_csi;
  ]

let multiline_tests =
  [
    test_case "multiline" `Quick test_multiline;
    test_case "multiline with styles" `Quick test_multiline_with_styles;
  ]

let visible_length_tests =
  [
    test_case "visible length plain" `Quick test_visible_length_plain;
    test_case "visible length with ansi" `Quick test_visible_length_with_ansi;
    test_case "visible length complex" `Quick test_visible_length_complex;
    test_case "visible length utf8" `Quick test_visible_length_utf8;
  ]

let osc_tests =
  [
    test_case "osc8 hyperlink skipped" `Quick test_osc8_hyperlink_skipped;
    test_case "osc8 styled display" `Quick test_osc8_with_styled_display;
    test_case "osc8 bel terminated" `Quick test_osc8_bel_terminated;
    test_case "osc mixed with csi" `Quick test_osc_mixed_with_csi;
    test_case "visible length osc8" `Quick test_visible_length_osc8;
    test_case
      "visible length mixed csi+osc"
      `Quick
      test_visible_length_mixed_csi_osc;
  ]

let widget_tests =
  [
    test_case "widget bold" `Quick test_widget_bold;
    test_case "widget dim" `Quick test_widget_dim;
    test_case "widget fg color" `Quick test_widget_fg_color;
    test_case "widget bg color" `Quick test_widget_bg_color;
    test_case "widget red" `Quick test_widget_red;
    test_case "widget green" `Quick test_widget_green;
  ]

let () =
  run
    "matrix_ansi_parser"
    [
      ("plain_text", plain_text_tests);
      ("utf8", utf8_tests);
      ("colors", color_tests);
      ("combined", combined_tests);
      ("reset", reset_tests);
      ("edge_cases", edge_case_tests);
      ("multiline", multiline_tests);
      ("visible_length", visible_length_tests);
      ("osc", osc_tests);
      ("widgets", widget_tests);
    ]
