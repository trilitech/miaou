(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

open Alcotest
module BW = Miaou_widgets_layout.Box_widget
module H = Miaou_widgets_display.Widgets

let lines s = String.split_on_char '\n' s

let visible_len = Miaou_widgets_display.Widgets.visible_chars_count

let test_basic_no_title () =
  let result = BW.render ~style:Ascii ~width:20 "Hello" in
  let ls = lines result in
  check int "line count" 3 (List.length ls)

let test_with_title () =
  let result = BW.render ~title:"Title" ~style:Ascii ~width:30 "body" in
  let first = List.hd (lines result) in
  check bool "title in first line" true (String.length first > 0) ;
  check
    bool
    "contains Title"
    true
    (try
       ignore (Str.search_forward (Str.regexp_string "Title") first 0) ;
       true
     with Not_found -> false)

let test_multiline_content () =
  let result = BW.render ~style:Ascii ~width:20 "line1\nline2\nline3" in
  let ls = lines result in
  check int "3 content + 2 border" 5 (List.length ls)

let test_padding () =
  let padding = {BW.left = 1; right = 1; top = 1; bottom = 1} in
  let result = BW.render ~style:Ascii ~padding ~width:20 "hello" in
  let ls = lines result in
  (* top border + 1 top pad + 1 content + 1 bottom pad + bottom border = 5 *)
  check int "with padding" 5 (List.length ls)

let test_fixed_height () =
  let result = BW.render ~style:Ascii ~width:20 ~height:6 "one" in
  let ls = lines result in
  check int "exact height" 6 (List.length ls)

let test_empty_content () =
  let result = BW.render ~style:Ascii ~width:20 "" in
  let ls = lines result in
  check int "empty = 3 lines" 3 (List.length ls)

let test_width_consistency () =
  let result = BW.render ~style:Ascii ~width:25 "testing" in
  let ls = lines result in
  List.iter (fun line -> check int "visible width" 25 (visible_len line)) ls

let test_truncation () =
  let long = String.make 50 'x' in
  let result = BW.render ~style:Ascii ~width:20 long in
  let ls = lines result in
  List.iter
    (fun line ->
      let vl = visible_len line in
      check bool "at most width" true (vl <= 20))
    ls

let test_ascii_style () =
  let result = BW.render ~style:Ascii ~width:20 "test" in
  let first = List.hd (lines result) in
  check bool "starts with +" true (String.length first > 0 && first.[0] = '+')

let test_double_style () =
  let result = BW.render ~style:Double ~width:20 "test" in
  let ls = lines result in
  check bool "renders" true (List.length ls >= 3)

let test_rounded_style () =
  let result = BW.render ~style:Rounded ~width:20 "test" in
  let ls = lines result in
  check bool "renders" true (List.length ls >= 3)

let test_heavy_style () =
  let result = BW.render ~style:Heavy ~width:20 "test" in
  let ls = lines result in
  check bool "renders" true (List.length ls >= 3)

let test_color () =
  let result = BW.render ~style:Ascii ~color:45 ~width:20 "test" in
  check
    bool
    "contains ANSI"
    true
    (try
       ignore (Str.search_forward (Str.regexp_string "\027[") result 0) ;
       true
     with Not_found -> false)

let test_height_clips () =
  let content = "a\nb\nc\nd\ne\nf" in
  let result = BW.render ~style:Ascii ~width:20 ~height:4 content in
  let ls = lines result in
  check int "clipped to 4" 4 (List.length ls)

let test_height_pads () =
  let result = BW.render ~style:Ascii ~width:20 ~height:8 "one" in
  let ls = lines result in
  check int "padded to 8" 8 (List.length ls)

let () =
  run
    "Box_widget"
    [
      ( "render",
        [
          test_case "basic_no_title" `Quick test_basic_no_title;
          test_case "with_title" `Quick test_with_title;
          test_case "multiline_content" `Quick test_multiline_content;
          test_case "padding" `Quick test_padding;
          test_case "fixed_height" `Quick test_fixed_height;
          test_case "empty_content" `Quick test_empty_content;
          test_case "width_consistency" `Quick test_width_consistency;
          test_case "truncation" `Quick test_truncation;
          test_case "ascii_style" `Quick test_ascii_style;
          test_case "double_style" `Quick test_double_style;
          test_case "rounded_style" `Quick test_rounded_style;
          test_case "heavy_style" `Quick test_heavy_style;
          test_case "color" `Quick test_color;
          test_case "height_clips" `Quick test_height_clips;
          test_case "height_pads" `Quick test_height_pads;
        ] );
    ]
