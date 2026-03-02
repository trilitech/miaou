(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                 *)
(* Copyright (c) 2026 Mathias Bourgoin <mathias.bourgoin@atacama.tech>        *)
(*                                                                            *)
(******************************************************************************)

open Alcotest
module Grid = Miaou_widgets_layout.Grid_layout

let size cols rows = {LTerm_geom.cols; rows}

let count_char s ch =
  String.fold_left (fun acc c -> if Char.equal c ch then acc + 1 else acc) 0 s

let fill_char ch ~size =
  let lines =
    List.init size.LTerm_geom.rows (fun _ ->
        String.make size.LTerm_geom.cols ch)
  in
  String.concat "\n" lines

let test_single_cell () =
  let grid =
    Grid.create
      ~rows:[Grid.Px 2]
      ~cols:[Grid.Px 5]
      [Grid.cell ~row:0 ~col:0 (fill_char 'A')]
  in
  let out = Grid.render grid ~size:(size 5 2) in
  let lines = String.split_on_char '\n' out in
  check int "line count" 2 (List.length lines) ;
  check int "A count" 10 (count_char out 'A')

let test_two_columns () =
  let grid =
    Grid.create
      ~rows:[Grid.Px 1]
      ~cols:[Grid.Px 3; Grid.Px 3]
      [
        Grid.cell ~row:0 ~col:0 (fill_char 'A');
        Grid.cell ~row:0 ~col:1 (fill_char 'B');
      ]
  in
  let out = Grid.render grid ~size:(size 6 1) in
  check int "A count" 3 (count_char out 'A') ;
  check int "B count" 3 (count_char out 'B')

let test_col_gap () =
  let grid =
    Grid.create
      ~rows:[Grid.Px 1]
      ~cols:[Grid.Px 3; Grid.Px 3]
      ~col_gap:2
      [
        Grid.cell ~row:0 ~col:0 (fill_char 'A');
        Grid.cell ~row:0 ~col:1 (fill_char 'B');
      ]
  in
  let out = Grid.render grid ~size:(size 8 1) in
  check int "A count" 3 (count_char out 'A') ;
  check int "B count" 3 (count_char out 'B') ;
  check int "space count" 2 (count_char out ' ')

let test_fr_tracks () =
  let grid =
    Grid.create
      ~rows:[Grid.Px 1]
      ~cols:[Grid.Fr 1.; Grid.Fr 1.]
      [
        Grid.cell ~row:0 ~col:0 (fill_char 'A');
        Grid.cell ~row:0 ~col:1 (fill_char 'B');
      ]
  in
  let out = Grid.render grid ~size:(size 10 1) in
  check int "A count" 5 (count_char out 'A') ;
  check int "B count" 5 (count_char out 'B')

let test_percent_track () =
  let grid =
    Grid.create
      ~rows:[Grid.Px 1]
      ~cols:[Grid.Percent 50.; Grid.Percent 50.]
      [
        Grid.cell ~row:0 ~col:0 (fill_char 'A');
        Grid.cell ~row:0 ~col:1 (fill_char 'B');
      ]
  in
  let out = Grid.render grid ~size:(size 20 1) in
  check int "A count" 10 (count_char out 'A') ;
  check int "B count" 10 (count_char out 'B')

let test_column_span () =
  let grid =
    Grid.create
      ~rows:[Grid.Px 1; Grid.Px 1]
      ~cols:[Grid.Px 5; Grid.Px 5]
      [
        Grid.span ~row:0 ~col:0 ~row_span:1 ~col_span:2 (fill_char 'H');
        Grid.cell ~row:1 ~col:0 (fill_char 'A');
        Grid.cell ~row:1 ~col:1 (fill_char 'B');
      ]
  in
  let out = Grid.render grid ~size:(size 10 2) in
  check int "H count" 10 (count_char out 'H') ;
  check int "A count" 5 (count_char out 'A') ;
  check int "B count" 5 (count_char out 'B')

let test_row_span () =
  let grid =
    Grid.create
      ~rows:[Grid.Px 2; Grid.Px 2]
      ~cols:[Grid.Px 3; Grid.Px 3]
      [
        Grid.span ~row:0 ~col:0 ~row_span:2 ~col_span:1 (fill_char 'S');
        Grid.cell ~row:0 ~col:1 (fill_char 'A');
        Grid.cell ~row:1 ~col:1 (fill_char 'B');
      ]
  in
  let out = Grid.render grid ~size:(size 6 4) in
  let lines = String.split_on_char '\n' out in
  check int "line count" 4 (List.length lines) ;
  check int "S count" 12 (count_char out 'S')

let test_empty_grid () =
  let grid = Grid.create ~rows:[] ~cols:[] [] in
  let out = Grid.render grid ~size:(size 10 5) in
  check string "empty" "" out

let test_minmax_track () =
  let grid =
    Grid.create
      ~rows:[Grid.Px 1]
      ~cols:[Grid.MinMax (3, 8); Grid.Fr 1.]
      [
        Grid.cell ~row:0 ~col:0 (fill_char 'A');
        Grid.cell ~row:0 ~col:1 (fill_char 'B');
      ]
  in
  let out = Grid.render grid ~size:(size 20 1) in
  let a_count = count_char out 'A' in
  check bool "minmax at least 3" true (a_count >= 3) ;
  check bool "minmax at most 8" true (a_count <= 8)

let test_row_gap () =
  let grid =
    Grid.create
      ~rows:[Grid.Px 1; Grid.Px 1]
      ~cols:[Grid.Px 5]
      ~row_gap:1
      [
        Grid.cell ~row:0 ~col:0 (fill_char 'A');
        Grid.cell ~row:1 ~col:0 (fill_char 'B');
      ]
  in
  let out = Grid.render grid ~size:(size 5 3) in
  let lines = String.split_on_char '\n' out in
  check int "line count" 3 (List.length lines) ;
  check string "row 0" "AAAAA" (List.nth lines 0) ;
  check string "gap" "     " (List.nth lines 1) ;
  check string "row 1" "BBBBB" (List.nth lines 2)

let test_row_gap_multi_line () =
  let grid =
    Grid.create
      ~rows:[Grid.Px 2; Grid.Px 2]
      ~cols:[Grid.Px 4]
      ~row_gap:1
      [
        Grid.cell ~row:0 ~col:0 (fill_char 'A');
        Grid.cell ~row:1 ~col:0 (fill_char 'B');
      ]
  in
  let out = Grid.render grid ~size:(size 4 5) in
  let lines = String.split_on_char '\n' out in
  check int "line count" 5 (List.length lines) ;
  check string "row 0 line 0" "AAAA" (List.nth lines 0) ;
  check string "row 0 line 1" "AAAA" (List.nth lines 1) ;
  check string "gap" "    " (List.nth lines 2) ;
  check string "row 1 line 0" "BBBB" (List.nth lines 3) ;
  check string "row 1 line 1" "BBBB" (List.nth lines 4)

let () =
  run
    "grid_layout"
    [
      ( "grid_layout",
        [
          test_case "single cell" `Quick test_single_cell;
          test_case "two columns" `Quick test_two_columns;
          test_case "column gap" `Quick test_col_gap;
          test_case "fr tracks" `Quick test_fr_tracks;
          test_case "percent track" `Quick test_percent_track;
          test_case "column span" `Quick test_column_span;
          test_case "row span" `Quick test_row_span;
          test_case "empty grid" `Quick test_empty_grid;
          test_case "minmax track" `Quick test_minmax_track;
          test_case "row gap" `Quick test_row_gap;
          test_case "row gap multi-line" `Quick test_row_gap_multi_line;
        ] );
    ]
