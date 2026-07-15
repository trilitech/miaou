(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

(* Matrix driver text selection: click/drag/word/line selection and
   highlight overlay. Multi-click detection is time-windowed (0.4s), but
   consecutive [start_selection] calls in a test execute far faster than
   that, so double/triple-click detection is exercised deterministically
   without needing a fake clock. *)
open Alcotest
module Selection = Miaou_driver_matrix.Matrix_selection

(* A tiny fixed "screen" of rows, each row an array of one-grapheme cell
   strings, so [get_char] behaves like reading real Matrix_buffer cells. *)
let get_char_of (rows : string array array) ~row ~col =
  if row >= 0 && row < Array.length rows then
    let r = rows.(row) in
    if col >= 0 && col < Array.length r then r.(col) else " "
  else " "

let row_of_string s =
  Array.init (String.length s) (fun i -> String.make 1 s.[i])

let test_single_click_selects_a_point () =
  let rows = [|row_of_string "hello"|] in
  let sel = Selection.create () in
  Selection.start_selection
    sel
    ~row:0
    ~col:2
    ~get_char:(get_char_of rows)
    ~cols:5 ;
  check
    bool
    "is_single_point true for a plain click"
    true
    (Selection.is_single_point sel) ;
  check
    bool
    "clicked cell is selected"
    true
    (Selection.is_selected sel ~row:0 ~col:2) ;
  check
    bool
    "adjacent cell is not selected"
    false
    (Selection.is_selected sel ~row:0 ~col:3) ;
  check int "click_count is 1" 1 (Selection.click_count sel)

let test_drag_selects_a_range_and_finish_extracts_text () =
  let rows = [|row_of_string "hello world"|] in
  let sel = Selection.create () in
  Selection.start_selection
    sel
    ~row:0
    ~col:0
    ~get_char:(get_char_of rows)
    ~cols:11 ;
  Selection.update_selection sel ~row:0 ~col:4 ;
  check
    bool
    "drag makes it a range, not a single point"
    false
    (Selection.is_single_point sel) ;
  check
    bool
    "start of range is selected"
    true
    (Selection.is_selected sel ~row:0 ~col:0) ;
  check
    bool
    "end of range is selected"
    true
    (Selection.is_selected sel ~row:0 ~col:4) ;
  check
    bool
    "past the end of range is not selected"
    false
    (Selection.is_selected sel ~row:0 ~col:5) ;
  match
    Selection.finish_selection sel ~get_char:(get_char_of rows) ~cols:11
  with
  | Some text -> check string "extracted text" "hello" text
  | None -> fail "expected Some text from finish_selection"

let test_multiline_selection_joins_with_newline () =
  let rows = [|row_of_string "abcde"; row_of_string "fghij"|] in
  let sel = Selection.create () in
  Selection.start_selection
    sel
    ~row:0
    ~col:3
    ~get_char:(get_char_of rows)
    ~cols:5 ;
  Selection.update_selection sel ~row:1 ~col:1 ;
  match Selection.finish_selection sel ~get_char:(get_char_of rows) ~cols:5 with
  | Some text -> check string "multiline text joined with \\n" "de\nfg" text
  | None -> fail "expected Some text"

let test_finish_selection_trims_trailing_spaces_per_line () =
  let rows = [|row_of_string "ab   "; row_of_string "cd   "|] in
  let sel = Selection.create () in
  Selection.start_selection
    sel
    ~row:0
    ~col:0
    ~get_char:(get_char_of rows)
    ~cols:5 ;
  Selection.update_selection sel ~row:1 ~col:4 ;
  match Selection.finish_selection sel ~get_char:(get_char_of rows) ~cols:5 with
  | Some text ->
      check string "trailing spaces trimmed on each line" "ab\ncd" text
  | None -> fail "expected Some text"

let test_finish_selection_with_no_selection_is_none () =
  let rows = [|row_of_string "abc"|] in
  let sel = Selection.create () in
  check
    (option string)
    "finish with no prior start_selection is None"
    None
    (Selection.finish_selection sel ~get_char:(get_char_of rows) ~cols:3)

let test_double_click_selects_word () =
  let rows = [|row_of_string "foo bar baz"|] in
  let sel = Selection.create () in
  let click () =
    Selection.start_selection
      sel
      ~row:0
      ~col:5
      ~get_char:(get_char_of rows)
      ~cols:11
  in
  click () ;
  click () ;
  check
    int
    "click_count is 2 on rapid same-position double click"
    2
    (Selection.click_count sel) ;
  check bool "is_multi_click true" true (Selection.is_multi_click sel) ;
  check
    bool
    "start of the clicked word is selected"
    true
    (Selection.is_selected sel ~row:0 ~col:4) ;
  check
    bool
    "end of the clicked word is selected"
    true
    (Selection.is_selected sel ~row:0 ~col:6) ;
  check
    bool
    "the space before the word is not selected"
    false
    (Selection.is_selected sel ~row:0 ~col:3) ;
  check
    bool
    "the space after the word is not selected"
    false
    (Selection.is_selected sel ~row:0 ~col:7)

let test_triple_click_selects_line_segment_stopping_at_box_char () =
  (* U+2500 BOX DRAWINGS LIGHT HORIZONTAL, encoded as UTF-8 bytes, occupying
     one "cell" the way a real Matrix_buffer grapheme would. *)
  let box = "\xe2\x94\x80" in
  let rows =
    [|
      Array.append
        (row_of_string "ab")
        (Array.append [|box|] (row_of_string "cd"));
    |]
  in
  let sel = Selection.create () in
  let click () =
    Selection.start_selection
      sel
      ~row:0
      ~col:0
      ~get_char:(get_char_of rows)
      ~cols:6
  in
  click () ;
  click () ;
  click () ;
  check
    int
    "click_count is 3 on a rapid triple click"
    3
    (Selection.click_count sel) ;
  check
    bool
    "segment before the box char is selected"
    true
    (Selection.is_selected sel ~row:0 ~col:1) ;
  check
    bool
    "the box char itself is not part of the segment"
    false
    (Selection.is_selected sel ~row:0 ~col:2) ;
  check
    bool
    "content past the box char is not part of this segment"
    false
    (Selection.is_selected sel ~row:0 ~col:3)

let test_apply_highlight_marks_only_selected_cells () =
  let rows = [|row_of_string "abcde"|] in
  let sel = Selection.create () in
  Selection.start_selection
    sel
    ~row:0
    ~col:1
    ~get_char:(get_char_of rows)
    ~cols:5 ;
  Selection.update_selection sel ~row:0 ~col:2 ;
  let marked = Hashtbl.create 8 in
  Selection.apply_highlight
    sel
    ~set_style:(fun ~row ~col ~reverse ->
      Hashtbl.replace marked (row, col) reverse)
    ~rows:1
    ~cols:5 ;
  check bool "col 1 is marked reverse" true (Hashtbl.mem marked (0, 1)) ;
  check bool "col 2 is marked reverse" true (Hashtbl.mem marked (0, 2)) ;
  check bool "col 0 is untouched" false (Hashtbl.mem marked (0, 0)) ;
  check bool "col 3 is untouched" false (Hashtbl.mem marked (0, 3))

let test_clear_resets_state () =
  let rows = [|row_of_string "abc"|] in
  let sel = Selection.create () in
  Selection.start_selection
    sel
    ~row:0
    ~col:0
    ~get_char:(get_char_of rows)
    ~cols:3 ;
  Selection.update_selection sel ~row:0 ~col:2 ;
  check bool "has_selection before clear" true (Selection.has_selection sel) ;
  Selection.clear sel ;
  check
    bool
    "has_selection false after clear"
    false
    (Selection.has_selection sel) ;
  check bool "is_active false after clear" false (Selection.is_active sel) ;
  check
    bool
    "nothing is selected after clear"
    false
    (Selection.is_selected sel ~row:0 ~col:0)

let () =
  run
    "matrix_selection"
    [
      ( "selection",
        [
          test_case
            "single click selects a point"
            `Quick
            test_single_click_selects_a_point;
          test_case
            "drag selects a range; finish extracts text"
            `Quick
            test_drag_selects_a_range_and_finish_extracts_text;
          test_case
            "multiline selection joins with newline"
            `Quick
            test_multiline_selection_joins_with_newline;
          test_case
            "finish_selection trims trailing spaces per line"
            `Quick
            test_finish_selection_trims_trailing_spaces_per_line;
          test_case
            "finish_selection with no selection is None"
            `Quick
            test_finish_selection_with_no_selection_is_none;
          test_case
            "double click selects a word"
            `Quick
            test_double_click_selects_word;
          test_case
            "triple click selects a line segment, stops at box char"
            `Quick
            test_triple_click_selects_line_segment_stopping_at_box_char;
          test_case
            "apply_highlight marks only selected cells"
            `Quick
            test_apply_highlight_marks_only_selected_cells;
          test_case "clear resets state" `Quick test_clear_resets_state;
        ] );
    ]
