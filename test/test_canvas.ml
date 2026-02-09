(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

open Alcotest
module C = Miaou_canvas.Canvas

(* --- Helpers --- *)

let style = C.default_style

let red_style = {C.default_style with fg = 196}

let bold_style = {C.default_style with bold = true}

let cell_char c ~row ~col = (C.get_cell c ~row ~col).char

let cell_fg c ~row ~col = (C.get_cell c ~row ~col).style.fg

let cell_bold c ~row ~col = (C.get_cell c ~row ~col).style.bold

(* --- Creation tests --- *)

let test_create_dimensions () =
  let c = C.create ~rows:5 ~cols:10 in
  check int "rows" 5 (C.rows c) ;
  check int "cols" 10 (C.cols c)

let test_create_empty () =
  let c = C.create ~rows:3 ~cols:3 in
  for r = 0 to 2 do
    for col = 0 to 2 do
      check string "empty cell" " " (cell_char c ~row:r ~col)
    done
  done

let test_create_zero () =
  let c = C.create ~rows:0 ~cols:0 in
  check int "rows" 0 (C.rows c) ;
  check int "cols" 0 (C.cols c)

let test_create_negative () =
  try
    ignore (C.create ~rows:(-1) ~cols:5) ;
    fail "expected Invalid_argument"
  with Invalid_argument _ -> ()

(* --- Cell access tests --- *)

let test_set_get () =
  let c = C.create ~rows:3 ~cols:3 in
  C.set_char c ~row:1 ~col:2 ~char:"X" ~style:red_style ;
  let cell = C.get_cell c ~row:1 ~col:2 in
  check string "char" "X" cell.char ;
  check int "fg" 196 cell.style.fg

let test_set_out_of_bounds_silent () =
  let c = C.create ~rows:3 ~cols:3 in
  (* Should not raise *)
  C.set_char c ~row:(-1) ~col:0 ~char:"X" ~style ;
  C.set_char c ~row:0 ~col:99 ~char:"X" ~style ;
  C.set_char c ~row:99 ~col:0 ~char:"X" ~style ;
  (* All cells remain empty *)
  for r = 0 to 2 do
    for col = 0 to 2 do
      check string "still empty" " " (cell_char c ~row:r ~col)
    done
  done

let test_get_out_of_bounds_raises () =
  let c = C.create ~rows:3 ~cols:3 in
  try
    ignore (C.get_cell c ~row:3 ~col:0) ;
    fail "expected Invalid_argument"
  with Invalid_argument _ -> ()

(* --- Drawing primitives --- *)

let test_draw_text () =
  let c = C.create ~rows:1 ~cols:10 in
  C.draw_text c ~row:0 ~col:2 ~style:bold_style "Hello" ;
  check string "before text" " " (cell_char c ~row:0 ~col:0) ;
  check string "before text" " " (cell_char c ~row:0 ~col:1) ;
  check string "H" "H" (cell_char c ~row:0 ~col:2) ;
  check string "e" "e" (cell_char c ~row:0 ~col:3) ;
  check string "l" "l" (cell_char c ~row:0 ~col:4) ;
  check string "l" "l" (cell_char c ~row:0 ~col:5) ;
  check string "o" "o" (cell_char c ~row:0 ~col:6) ;
  check bool "bold" true (cell_bold c ~row:0 ~col:2) ;
  check string "after text" " " (cell_char c ~row:0 ~col:7)

let test_draw_text_clip () =
  let c = C.create ~rows:1 ~cols:5 in
  C.draw_text c ~row:0 ~col:3 ~style "Hello" ;
  (* Only "He" should fit at cols 3-4 *)
  check string "col 3" "H" (cell_char c ~row:0 ~col:3) ;
  check string "col 4" "e" (cell_char c ~row:0 ~col:4)

let test_draw_text_utf8 () =
  let c = C.create ~rows:1 ~cols:10 in
  C.draw_text c ~row:0 ~col:0 ~style "caf\xc3\xa9" ;
  check string "c" "c" (cell_char c ~row:0 ~col:0) ;
  check string "a" "a" (cell_char c ~row:0 ~col:1) ;
  check string "f" "f" (cell_char c ~row:0 ~col:2) ;
  check string "\xc3\xa9" "\xc3\xa9" (cell_char c ~row:0 ~col:3)

let test_draw_hline () =
  let c = C.create ~rows:3 ~cols:5 in
  C.draw_hline c ~row:1 ~col:0 ~len:5 ~char:"-" ~style ;
  for col = 0 to 4 do
    check string "hline cell" "-" (cell_char c ~row:1 ~col)
  done ;
  check string "above" " " (cell_char c ~row:0 ~col:0) ;
  check string "below" " " (cell_char c ~row:2 ~col:0)

let test_draw_vline () =
  let c = C.create ~rows:5 ~cols:3 in
  C.draw_vline c ~row:0 ~col:1 ~len:5 ~char:"|" ~style ;
  for row = 0 to 4 do
    check string "vline cell" "|" (cell_char c ~row ~col:1)
  done ;
  check string "left" " " (cell_char c ~row:0 ~col:0) ;
  check string "right" " " (cell_char c ~row:0 ~col:2)

let test_fill_rect () =
  let c = C.create ~rows:5 ~cols:5 in
  C.fill_rect c ~row:1 ~col:1 ~width:3 ~height:2 ~char:"#" ~style:red_style ;
  (* Interior filled *)
  check string "inside" "#" (cell_char c ~row:1 ~col:1) ;
  check string "inside" "#" (cell_char c ~row:2 ~col:3) ;
  check int "fg inside" 196 (cell_fg c ~row:1 ~col:1) ;
  (* Outside untouched *)
  check string "outside" " " (cell_char c ~row:0 ~col:0) ;
  check string "outside" " " (cell_char c ~row:1 ~col:0) ;
  check string "outside" " " (cell_char c ~row:1 ~col:4)

let test_fill_rect_clip () =
  let c = C.create ~rows:3 ~cols:3 in
  (* Rect extends beyond bounds *)
  C.fill_rect c ~row:1 ~col:1 ~width:10 ~height:10 ~char:"#" ~style ;
  check string "inside" "#" (cell_char c ~row:1 ~col:1) ;
  check string "inside" "#" (cell_char c ~row:2 ~col:2) ;
  (* Unaffected *)
  check string "outside" " " (cell_char c ~row:0 ~col:0)

let test_clear () =
  let c = C.create ~rows:3 ~cols:3 in
  C.fill_rect c ~row:0 ~col:0 ~width:3 ~height:3 ~char:"X" ~style:red_style ;
  C.clear c ;
  for r = 0 to 2 do
    for col = 0 to 2 do
      let cell = C.get_cell c ~row:r ~col in
      check string "cleared char" " " cell.char ;
      check int "cleared fg" (-1) cell.style.fg
    done
  done

(* --- Box drawing --- *)

let test_draw_box_single () =
  let c = C.create ~rows:5 ~cols:8 in
  C.draw_box c ~row:0 ~col:0 ~width:8 ~height:5 ~border:Single ~style ;
  (* Corners *)
  check string "tl" "\xe2\x94\x8c" (cell_char c ~row:0 ~col:0) ;
  check string "tr" "\xe2\x94\x90" (cell_char c ~row:0 ~col:7) ;
  check string "bl" "\xe2\x94\x94" (cell_char c ~row:4 ~col:0) ;
  check string "br" "\xe2\x94\x98" (cell_char c ~row:4 ~col:7) ;
  (* Horizontal edges *)
  check string "h top" "\xe2\x94\x80" (cell_char c ~row:0 ~col:3) ;
  check string "h bottom" "\xe2\x94\x80" (cell_char c ~row:4 ~col:3) ;
  (* Vertical edges *)
  check string "v left" "\xe2\x94\x82" (cell_char c ~row:2 ~col:0) ;
  check string "v right" "\xe2\x94\x82" (cell_char c ~row:2 ~col:7) ;
  (* Interior untouched *)
  check string "interior" " " (cell_char c ~row:2 ~col:3)

let test_draw_box_too_small () =
  let c = C.create ~rows:1 ~cols:1 in
  (* Should be silently ignored *)
  C.draw_box c ~row:0 ~col:0 ~width:1 ~height:1 ~border:Single ~style ;
  check string "unchanged" " " (cell_char c ~row:0 ~col:0)

let test_draw_box_ascii () =
  let c = C.create ~rows:3 ~cols:4 in
  C.draw_box c ~row:0 ~col:0 ~width:4 ~height:3 ~border:Ascii ~style ;
  check string "tl" "+" (cell_char c ~row:0 ~col:0) ;
  check string "tr" "+" (cell_char c ~row:0 ~col:3) ;
  check string "h" "-" (cell_char c ~row:0 ~col:1) ;
  check string "v" "|" (cell_char c ~row:1 ~col:0)

let test_draw_box_all_styles () =
  (* Verify each style has distinct corner chars *)
  let styles = [C.Single; Double; Rounded; Heavy; Ascii] in
  let corners =
    List.map
      (fun border ->
        let c = C.create ~rows:3 ~cols:3 in
        C.draw_box c ~row:0 ~col:0 ~width:3 ~height:3 ~border ~style ;
        cell_char c ~row:0 ~col:0)
      styles
  in
  (* All corners should be distinct *)
  let unique = List.sort_uniq String.compare corners in
  check int "distinct corners" 5 (List.length unique)

(* --- Composition --- *)

let test_blit_transparent () =
  let dst = C.create ~rows:3 ~cols:5 in
  C.fill_rect dst ~row:0 ~col:0 ~width:5 ~height:3 ~char:"." ~style ;
  let src = C.create ~rows:1 ~cols:3 in
  (* Only set col 0 and 2, leave col 1 as space (transparent) *)
  C.set_char src ~row:0 ~col:0 ~char:"A" ~style ;
  C.set_char src ~row:0 ~col:2 ~char:"C" ~style ;
  C.blit ~src ~dst ~row:1 ~col:1 ;
  check string "blitted A" "A" (cell_char dst ~row:1 ~col:1) ;
  check string "transparent" "." (cell_char dst ~row:1 ~col:2) ;
  check string "blitted C" "C" (cell_char dst ~row:1 ~col:3)

let test_blit_all () =
  let dst = C.create ~rows:3 ~cols:5 in
  C.fill_rect dst ~row:0 ~col:0 ~width:5 ~height:3 ~char:"." ~style ;
  let src = C.create ~rows:1 ~cols:3 in
  C.set_char src ~row:0 ~col:0 ~char:"A" ~style ;
  (* col 1 is space *)
  C.set_char src ~row:0 ~col:2 ~char:"C" ~style ;
  C.blit_all ~src ~dst ~row:1 ~col:1 ;
  check string "blitted A" "A" (cell_char dst ~row:1 ~col:1) ;
  check string "space overwrites" " " (cell_char dst ~row:1 ~col:2) ;
  check string "blitted C" "C" (cell_char dst ~row:1 ~col:3)

let test_blit_clip () =
  let dst = C.create ~rows:3 ~cols:3 in
  let src = C.create ~rows:2 ~cols:2 in
  C.fill_rect src ~row:0 ~col:0 ~width:2 ~height:2 ~char:"X" ~style ;
  (* Blit at offset (2,2) — only top-left cell of src fits *)
  C.blit ~src ~dst ~row:2 ~col:2 ;
  check string "fits" "X" (cell_char dst ~row:2 ~col:2) ;
  (* Others untouched *)
  check string "untouched" " " (cell_char dst ~row:0 ~col:0)

let test_blit_negative_offset () =
  let dst = C.create ~rows:3 ~cols:3 in
  let src = C.create ~rows:2 ~cols:2 in
  C.fill_rect src ~row:0 ~col:0 ~width:2 ~height:2 ~char:"X" ~style ;
  (* Blit at (-1, -1) — only bottom-right cell of src visible *)
  C.blit ~src ~dst ~row:(-1) ~col:(-1) ;
  check string "visible cell" "X" (cell_char dst ~row:0 ~col:0) ;
  check string "untouched" " " (cell_char dst ~row:1 ~col:0)

(* --- ANSI output --- *)

let test_to_ansi_empty () =
  let c = C.create ~rows:1 ~cols:3 in
  let out = C.to_ansi c in
  check string "plain spaces" "   " out

let test_to_ansi_styled () =
  let c = C.create ~rows:1 ~cols:3 in
  C.set_char c ~row:0 ~col:0 ~char:"A" ~style:red_style ;
  C.set_char c ~row:0 ~col:1 ~char:"B" ~style:red_style ;
  C.set_char c ~row:0 ~col:2 ~char:"C" ~style ;
  let out = C.to_ansi c in
  (* Should contain SGR for red, then AB, then SGR reset for C *)
  check bool "contains red SGR" true (String.length out > 3) ;
  check
    bool
    "starts with ESC"
    true
    (String.length out >= 2 && out.[0] = '\027' && out.[1] = '[') ;
  (* Contains ABC in order *)
  check bool "contains A" true (String.contains out 'A') ;
  check bool "contains B" true (String.contains out 'B') ;
  check bool "contains C" true (String.contains out 'C') ;
  (* Contains the red fg code *)
  check
    bool
    "contains 38;5;196"
    true
    (let s = "38;5;196" in
     let slen = String.length s in
     let olen = String.length out in
     let found = ref false in
     for i = 0 to olen - slen do
       if String.sub out i slen = s then found := true
     done ;
     !found)

let test_to_ansi_multiline () =
  let c = C.create ~rows:2 ~cols:2 in
  C.set_char c ~row:0 ~col:0 ~char:"A" ~style ;
  C.set_char c ~row:1 ~col:0 ~char:"C" ~style ;
  let out = C.to_ansi c in
  check bool "contains newline" true (String.contains out '\n')

let test_to_ansi_zero () =
  let c = C.create ~rows:0 ~cols:0 in
  check string "empty" "" (C.to_ansi c)

let test_to_ansi_minimal_sgr () =
  (* When all cells have the same non-default style, only one SGR should be emitted *)
  let c = C.create ~rows:1 ~cols:3 in
  C.set_char c ~row:0 ~col:0 ~char:"A" ~style:bold_style ;
  C.set_char c ~row:0 ~col:1 ~char:"B" ~style:bold_style ;
  C.set_char c ~row:0 ~col:2 ~char:"C" ~style:bold_style ;
  let out = C.to_ansi c in
  (* Count ESC occurrences — should be exactly 2: one SGR set + one reset *)
  let esc_count = ref 0 in
  String.iter (fun ch -> if ch = '\027' then incr esc_count) out ;
  check int "exactly 2 ESC sequences" 2 !esc_count

(* --- Iteration --- *)

let test_iter_count () =
  let c = C.create ~rows:3 ~cols:4 in
  let count = ref 0 in
  C.iter c ~f:(fun ~row:_ ~col:_ _ -> incr count) ;
  check int "cell count" 12 !count

let test_iter_order () =
  let c = C.create ~rows:2 ~cols:2 in
  C.set_char c ~row:0 ~col:0 ~char:"A" ~style ;
  C.set_char c ~row:0 ~col:1 ~char:"B" ~style ;
  C.set_char c ~row:1 ~col:0 ~char:"C" ~style ;
  C.set_char c ~row:1 ~col:1 ~char:"D" ~style ;
  let chars = Buffer.create 4 in
  C.iter c ~f:(fun ~row:_ ~col:_ cell -> Buffer.add_string chars cell.char) ;
  check string "row-major order" "ABCD" (Buffer.contents chars)

(* --- Border utilities --- *)

let test_border_chars_of_style () =
  let chars = C.border_chars_of_style Single in
  check string "single h" "\xe2\x94\x80" chars.h ;
  let chars = C.border_chars_of_style Ascii in
  check string "ascii h" "-" chars.h

(* --- Test runner --- *)

let () =
  run
    "Canvas"
    [
      ( "creation",
        [
          test_case "dimensions" `Quick test_create_dimensions;
          test_case "empty cells" `Quick test_create_empty;
          test_case "zero size" `Quick test_create_zero;
          test_case "negative raises" `Quick test_create_negative;
        ] );
      ( "cell access",
        [
          test_case "set and get" `Quick test_set_get;
          test_case
            "set out of bounds silent"
            `Quick
            test_set_out_of_bounds_silent;
          test_case
            "get out of bounds raises"
            `Quick
            test_get_out_of_bounds_raises;
        ] );
      ( "drawing",
        [
          test_case "draw_text" `Quick test_draw_text;
          test_case "draw_text clip" `Quick test_draw_text_clip;
          test_case "draw_text utf8" `Quick test_draw_text_utf8;
          test_case "draw_hline" `Quick test_draw_hline;
          test_case "draw_vline" `Quick test_draw_vline;
          test_case "fill_rect" `Quick test_fill_rect;
          test_case "fill_rect clip" `Quick test_fill_rect_clip;
          test_case "clear" `Quick test_clear;
        ] );
      ( "boxes",
        [
          test_case "single border" `Quick test_draw_box_single;
          test_case "too small" `Quick test_draw_box_too_small;
          test_case "ascii border" `Quick test_draw_box_ascii;
          test_case "all styles distinct" `Quick test_draw_box_all_styles;
        ] );
      ( "composition",
        [
          test_case "blit transparent" `Quick test_blit_transparent;
          test_case "blit_all opaque" `Quick test_blit_all;
          test_case "blit clip" `Quick test_blit_clip;
          test_case "blit negative offset" `Quick test_blit_negative_offset;
        ] );
      ( "ansi output",
        [
          test_case "empty canvas" `Quick test_to_ansi_empty;
          test_case "styled cells" `Quick test_to_ansi_styled;
          test_case "multiline" `Quick test_to_ansi_multiline;
          test_case "zero size" `Quick test_to_ansi_zero;
          test_case "minimal SGR" `Quick test_to_ansi_minimal_sgr;
        ] );
      ( "iteration",
        [
          test_case "cell count" `Quick test_iter_count;
          test_case "row-major order" `Quick test_iter_order;
        ] );
      ( "border utils",
        [test_case "border_chars_of_style" `Quick test_border_chars_of_style] );
    ]
