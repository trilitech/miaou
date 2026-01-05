(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

open Alcotest
module Diff = Miaou_driver_matrix.Matrix_diff
module Buffer = Miaou_driver_matrix.Matrix_buffer
module Cell = Miaou_driver_matrix.Matrix_cell
module Writer = Miaou_driver_matrix.Matrix_ansi_writer
module Parser = Miaou_driver_matrix.Matrix_ansi_parser

(* Helper to extract text content from buffer row *)
let buffer_row_text buf row =
  let cols = Buffer.cols buf in
  let b = Stdlib.Buffer.create cols in
  for col = 0 to cols - 1 do
    Stdlib.Buffer.add_string b (Buffer.get_back buf ~row ~col).Cell.char
  done ;
  Stdlib.Buffer.contents b

(* Count occurrences of a substring in a string *)
let count_substring str sub =
  let sub_len = String.length sub in
  let str_len = String.length str in
  if sub_len = 0 then 0
  else
    let count = ref 0 in
    let i = ref 0 in
    while !i <= str_len - sub_len do
      if String.sub str !i sub_len = sub then begin
        incr count ;
        i := !i + sub_len
      end
      else incr i
    done ;
    !count

(* Test that diff always starts with cursor positioning *)
let test_diff_starts_with_moveto () =
  let buf = Buffer.create ~rows:5 ~cols:20 in
  (* Write something to back buffer *)
  Buffer.set_char buf ~row:0 ~col:0 ~char:"H" ~style:Cell.default_style ;
  Buffer.set_char buf ~row:0 ~col:1 ~char:"i" ~style:Cell.default_style ;
  (* Front buffer is empty (default), so diff should detect changes *)
  let changes = Diff.compute buf in
  (* Debug: print what we got *)
  let change_to_string = function
    | Diff.MoveTo (r, c) -> Printf.sprintf "MoveTo(%d,%d)" r c
    | Diff.SetStyle _ -> "SetStyle"
    | Diff.WriteChar c -> Printf.sprintf "WriteChar(%s)" c
    | Diff.WriteRun (c, n) -> Printf.sprintf "WriteRun(%s,%d)" c n
  in
  let changes_str =
    String.concat
      ", "
      (List.map change_to_string (List.filteri (fun i _ -> i < 10) changes))
  in
  (* First change should be MoveTo - THIS IS THE BUG: if cursor starts at (0,0)
     and first cell is at (0,0), no MoveTo is emitted! *)
  match changes with
  | Diff.MoveTo (0, 0) :: _ -> ()
  | Diff.MoveTo (r, c) :: _ ->
      fail (Printf.sprintf "First MoveTo should be (0,0), got (%d,%d)" r c)
  | [] -> fail "Expected changes but got none"
  | first :: _ ->
      fail
        (Printf.sprintf
           "First change should be MoveTo but got %s. All changes: %s"
           (change_to_string first)
           changes_str)

(* Test that consecutive identical chars become WriteRun *)
let test_write_run_optimization () =
  let buf = Buffer.create ~rows:5 ~cols:20 in
  (* Write a horizontal line of dashes *)
  for col = 0 to 9 do
    Buffer.set_char buf ~row:0 ~col ~char:"-" ~style:Cell.default_style
  done ;
  let changes = Diff.compute buf in
  (* Should have MoveTo, then WriteRun for 10 dashes *)
  let has_run =
    List.exists
      (function Diff.WriteRun ("-", 10) -> true | _ -> false)
      changes
  in
  check bool "has WriteRun for 10 dashes" true has_run ;
  (* Should NOT have 10 separate WriteChars *)
  let write_char_count =
    List.fold_left
      (fun acc c -> match c with Diff.WriteChar "-" -> acc + 1 | _ -> acc)
      0
      changes
  in
  check int "no individual WriteChar for dashes" 0 write_char_count

(* Test that diff outputs content at correct positions *)
let test_diff_positions () =
  let buf = Buffer.create ~rows:5 ~cols:20 in
  (* Write at specific positions *)
  Buffer.set_char buf ~row:2 ~col:5 ~char:"X" ~style:Cell.default_style ;
  let changes = Diff.compute buf in
  (* Should have MoveTo(2,5) before the character *)
  let has_correct_move =
    List.exists (function Diff.MoveTo (2, 5) -> true | _ -> false) changes
  in
  check bool "has MoveTo(2,5)" true has_correct_move

(* Test simulating modal open scenario *)
let test_modal_scenario () =
  let rows = 30 in
  let cols = 80 in
  let buf = Buffer.create ~rows ~cols in
  let parser = Parser.create () in
  let writer = Writer.create () in

  (* Simulate initial page render - title at row 0 *)
  let initial_content = "octez-manager    Status: OK\nLine 2\nLine 3" in
  Buffer.clear_back buf ;
  Parser.reset parser ;
  let _ = Parser.parse_into parser buf ~row:0 ~col:0 initial_content in

  (* Simulate first render: compute diff and swap *)
  let changes1 = Diff.compute buf in
  let ansi1 = Writer.render writer changes1 in
  Buffer.swap buf ;

  (* Verify initial render has title once *)
  let title_count1 = count_substring ansi1 "octez-manager" in
  check int "initial render has title once" 1 title_count1 ;

  (* Now simulate modal open - same content but with modal overlay *)
  let modal_content =
    "octez-manager    Status: OK\n\
     Line 2\n\
     Line 3\n\n\n\
    \     +---Modal---+\n\
    \     | Content   |\n\
    \     +-----------+"
  in
  Buffer.clear_back buf ;
  Parser.reset parser ;
  let _ = Parser.parse_into parser buf ~row:0 ~col:0 modal_content in

  (* Compute diff for modal frame *)
  Writer.reset writer ;
  let changes2 = Diff.compute buf in
  let ansi2 = Writer.render writer changes2 in
  Buffer.swap buf ;

  (* The diff output should NOT contain octez-manager since row 0 didn't change! *)
  let title_count2 = count_substring ansi2 "octez-manager" in
  check int "modal diff should not repeat unchanged title" 0 title_count2

(* Test that unchanged rows are not re-rendered *)
let test_unchanged_rows_skipped () =
  let buf = Buffer.create ~rows:5 ~cols:20 in

  (* Initial: write "Hello" at row 0 *)
  Buffer.set_char buf ~row:0 ~col:0 ~char:"H" ~style:Cell.default_style ;
  Buffer.set_char buf ~row:0 ~col:1 ~char:"e" ~style:Cell.default_style ;
  Buffer.set_char buf ~row:0 ~col:2 ~char:"l" ~style:Cell.default_style ;
  Buffer.set_char buf ~row:0 ~col:3 ~char:"l" ~style:Cell.default_style ;
  Buffer.set_char buf ~row:0 ~col:4 ~char:"o" ~style:Cell.default_style ;

  (* First render *)
  let _ = Diff.compute buf in
  Buffer.swap buf ;

  (* Now write same content to back buffer *)
  Buffer.set_char buf ~row:0 ~col:0 ~char:"H" ~style:Cell.default_style ;
  Buffer.set_char buf ~row:0 ~col:1 ~char:"e" ~style:Cell.default_style ;
  Buffer.set_char buf ~row:0 ~col:2 ~char:"l" ~style:Cell.default_style ;
  Buffer.set_char buf ~row:0 ~col:3 ~char:"l" ~style:Cell.default_style ;
  Buffer.set_char buf ~row:0 ~col:4 ~char:"o" ~style:Cell.default_style ;

  (* Second render - should have no changes *)
  let changes = Diff.compute buf in
  check int "no changes for identical content" 0 (List.length changes)

(* Test with real ANSI file if it exists *)
let test_real_ansi_file () =
  let file = "/tmp/miaou-modal-with-overlay.ansi" in
  if Sys.file_exists file then begin
    let content =
      let ic = open_in file in
      let n = in_channel_length ic in
      let s = really_input_string ic n in
      close_in ic ;
      s
    in
    let rows = 50 in
    let cols = 200 in
    let buf = Buffer.create ~rows ~cols in
    let parser = Parser.create () in

    (* Parse the real ANSI content *)
    Parser.reset parser ;
    let _ = Parser.parse_into parser buf ~row:0 ~col:0 content in

    (* Check that octez-manager appears only once in buffer *)
    let title_occurrences = ref 0 in
    for row = 0 to rows - 1 do
      let row_text = buffer_row_text buf row in
      title_occurrences :=
        !title_occurrences + count_substring row_text "octez-manager"
    done ;
    check int "title appears once in buffer" 1 !title_occurrences
  end
  else
    (* Skip test if file doesn't exist *)
    ()

let () =
  run
    "matrix_diff"
    [
      ( "basic",
        [
          test_case "diff starts with moveto" `Quick test_diff_starts_with_moveto;
          test_case "write run optimization" `Quick test_write_run_optimization;
          test_case "diff positions" `Quick test_diff_positions;
          test_case "unchanged rows skipped" `Quick test_unchanged_rows_skipped;
        ] );
      ( "modal",
        [
          test_case "modal scenario" `Quick test_modal_scenario;
          test_case "real ansi file" `Quick test_real_ansi_file;
        ] );
    ]
