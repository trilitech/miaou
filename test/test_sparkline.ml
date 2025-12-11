(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

open Alcotest
module Sparkline = Miaou_widgets_display.Sparkline_widget

let strip_ansi s =
  let len = String.length s in
  let buf = Buffer.create len in
  let rec loop i =
    if i >= len then Buffer.contents buf
    else
      match s.[i] with
      | '\027' ->
          let j = ref (i + 1) in
          if !j < len && s.[!j] = '[' then (
            incr j ;
            while !j < len && s.[!j] <> 'm' do
              incr j
            done ;
            if !j < len then loop (!j + 1) else Buffer.contents buf)
          else loop (i + 1)
      | c ->
          Buffer.add_char buf c ;
          loop (i + 1)
  in
  loop 0

let test_empty_sparkline () =
  let sp = Sparkline.create ~width:10 ~max_points:10 () in
  let output =
    Sparkline.render sp ~focus:false ~show_value:false ~thresholds:[] ()
  in
  check string "empty sparkline" (String.make 10 ' ') output

let test_single_value () =
  let sp = Sparkline.create ~width:10 ~max_points:10 () in
  Sparkline.push sp 50.0 ;
  let output =
    Sparkline.render sp ~focus:false ~show_value:false ~thresholds:[] ()
  in
  (* Single value should be centered with middle block *)
  let has_block =
    try
      ignore (Str.search_forward (Str.regexp "▄") output 0) ;
      true
    with Not_found -> false
  in
  check bool "contains block" true has_block

let test_ascending_values () =
  let sp = Sparkline.create ~width:8 ~max_points:8 () in
  for i = 0 to 7 do
    Sparkline.push sp (float_of_int i)
  done ;
  let output =
    strip_ansi
      (Sparkline.render sp ~focus:true ~show_value:false ~thresholds:[] ())
  in
  (* Should have ascending blocks:  ▂▃▄▅▆▇█ *)
  check string "ascending" " ▂▃▄▅▆▇█" output

let test_descending_values () =
  let sp = Sparkline.create ~width:8 ~max_points:8 () in
  for i = 7 downto 0 do
    Sparkline.push sp (float_of_int i)
  done ;
  let output =
    strip_ansi
      (Sparkline.render sp ~focus:false ~show_value:false ~thresholds:[] ())
  in
  (* Should have descending blocks: █▇▆▅▄▃▂  *)
  check string "descending" "█▇▆▅▄▃▂ " output

let test_flat_line () =
  let sp = Sparkline.create ~width:5 ~max_points:5 () in
  for _ = 1 to 5 do
    Sparkline.push sp 42.0
  done ;
  let output =
    Sparkline.render sp ~focus:false ~show_value:false ~thresholds:[] ()
  in
  (* Flat line should render middle block *)
  check string "flat line" "▄▄▄▄▄" output

let test_circular_buffer () =
  let sp = Sparkline.create ~width:10 ~max_points:5 () in
  (* Push more than max_points *)
  for i = 0 to 9 do
    Sparkline.push sp (float_of_int i)
  done ;
  let min_val, max_val, current = Sparkline.stats sp in
  (* Should only keep last 5 values: 5,6,7,8,9 *)
  check (float 0.01) "min value" 5.0 min_val ;
  check (float 0.01) "max value" 9.0 max_val ;
  check (float 0.01) "current value" 9.0 current

let test_show_value () =
  let sp = Sparkline.create ~width:5 ~max_points:5 () in
  Sparkline.push sp 42.3 ;
  let output =
    Sparkline.render sp ~focus:false ~show_value:true ~thresholds:[] ()
  in
  (* Should contain the value *)
  check bool "contains value" true (String.contains output '4')

let test_render_with_label () =
  let sp = Sparkline.create ~width:5 ~max_points:5 () in
  Sparkline.push sp 78.0 ;
  let output =
    Sparkline.render_with_label sp ~label:"CPU" ~focus:false ~thresholds:[] ()
  in
  check bool "contains label" true (String.length output > 0 && output.[0] = 'C') ;
  check bool "contains brackets" true (String.contains output '[')

let test_fixed_min_max () =
  let sp =
    Sparkline.create ~width:3 ~max_points:3 ~min_value:0.0 ~max_value:100.0 ()
  in
  Sparkline.push sp 0.0 ;
  Sparkline.push sp 50.0 ;
  Sparkline.push sp 100.0 ;
  let output =
    strip_ansi
      (Sparkline.render sp ~focus:false ~show_value:false ~thresholds:[] ())
  in
  (* Should scale to fixed range: 0→min ( ), 50→mid (▄), 100→max (█) *)
  check string "fixed scaling" " ▄█" output

let test_clear () =
  let sp = Sparkline.create ~width:5 ~max_points:5 () in
  Sparkline.push sp 42.0 ;
  Sparkline.clear sp ;
  let output =
    Sparkline.render sp ~focus:false ~show_value:false ~thresholds:[] ()
  in
  check string "cleared" (String.make 5 ' ') output

let test_braille_mode_empty () =
  let sp = Sparkline.create ~width:5 ~max_points:5 () in
  let output =
    Sparkline.render
      sp
      ~focus:false
      ~show_value:false
      ~thresholds:[]
      ~mode:Sparkline.Braille
      ()
  in
  (* Should render empty braille cells *)
  check bool "has output" true (String.length output > 0)

let test_braille_mode_with_data () =
  let sp = Sparkline.create ~width:5 ~max_points:10 () in
  for i = 0 to 9 do
    Sparkline.push sp (float_of_int i)
  done ;
  let output =
    Sparkline.render
      sp
      ~focus:false
      ~show_value:false
      ~thresholds:[]
      ~mode:Sparkline.Braille
      ()
  in
  (* Should contain braille characters (UTF-8 encoded) *)
  check bool "has braille output" true (String.length output > 0)

let test_braille_vs_ascii () =
  let sp = Sparkline.create ~width:10 ~max_points:10 () in
  for i = 0 to 9 do
    Sparkline.push sp (float_of_int (i * i))
  done ;
  let ascii_output =
    Sparkline.render
      sp
      ~focus:false
      ~show_value:false
      ~thresholds:[]
      ~mode:Sparkline.ASCII
      ()
  in
  let braille_output =
    Sparkline.render
      sp
      ~focus:false
      ~show_value:false
      ~thresholds:[]
      ~mode:Sparkline.Braille
      ()
  in
  (* Both should produce non-empty output *)
  check bool "ascii not empty" true (String.length ascii_output > 0) ;
  check bool "braille not empty" true (String.length braille_output > 0)

let test_braille_colors () =
  let sp = Sparkline.create ~width:8 ~max_points:8 () in
  for i = 0 to 7 do
    Sparkline.push sp (float_of_int (i * 10))
  done ;
  let output =
    Sparkline.render
      sp
      ~focus:false
      ~show_value:false
      ~thresholds:[{Sparkline.value = 30.; color = "31"}]
      ~mode:Sparkline.Braille
      ()
  in
  (* Expect ANSI escape when threshold triggers *)
  check bool "braille colored" true (String.contains output '\027')

let suite =
  [
    test_case "empty sparkline" `Quick test_empty_sparkline;
    test_case "single value" `Quick test_single_value;
    test_case "ascending values" `Quick test_ascending_values;
    test_case "descending values" `Quick test_descending_values;
    test_case "flat line" `Quick test_flat_line;
    test_case "circular buffer" `Quick test_circular_buffer;
    test_case "show value" `Quick test_show_value;
    test_case "render with label" `Quick test_render_with_label;
    test_case "fixed min/max" `Quick test_fixed_min_max;
    test_case "clear" `Quick test_clear;
    test_case "braille mode empty" `Quick test_braille_mode_empty;
    test_case "braille mode with data" `Quick test_braille_mode_with_data;
    test_case "braille vs ascii" `Quick test_braille_vs_ascii;
    test_case "braille colors" `Quick test_braille_colors;
  ]

let () = run "sparkline" [("sparkline", suite)]
