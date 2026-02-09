(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

open Alcotest
module Cw = Miaou_widgets_layout.Canvas_widget
module Canvas = Miaou_canvas.Canvas

let mk_size r c = LTerm_geom.{rows = r; cols = c}

(* --- Creation ------------------------------------------------------------ *)

let test_create_empty () =
  let cw = Cw.create () in
  check (option reject) "canvas is None before render" None (Cw.canvas cw) ;
  check int "rows is 0" 0 (Cw.rows cw) ;
  check int "cols is 0" 0 (Cw.cols cw)

(* --- canvas_exn ---------------------------------------------------------- *)

let test_canvas_exn_before_render () =
  let cw = Cw.create () in
  match Cw.canvas_exn cw with
  | _ -> fail "canvas_exn should raise before render"
  | exception Invalid_argument _ -> ()

let test_canvas_exn_after_render () =
  let cw = Cw.create () in
  let _output = Cw.render cw ~size:(mk_size 5 10) in
  let _c = Cw.canvas_exn cw in
  (* Should not raise *)
  ()

(* --- Ensure -------------------------------------------------------------- *)

let test_ensure_allocates () =
  let cw = Cw.create () in
  let cw = Cw.ensure cw ~rows:3 ~cols:8 in
  check int "rows" 3 (Cw.rows cw) ;
  check int "cols" 8 (Cw.cols cw) ;
  check bool "canvas exists" true (Option.is_some (Cw.canvas cw))

let test_ensure_idempotent () =
  let cw = Cw.create () in
  let cw = Cw.ensure cw ~rows:4 ~cols:6 in
  let c1 = Cw.canvas cw in
  let cw = Cw.ensure cw ~rows:4 ~cols:6 in
  let c2 = Cw.canvas cw in
  check bool "same canvas when size unchanged" true (c1 == c2)

let test_ensure_resizes () =
  let cw = Cw.create () in
  let cw = Cw.ensure cw ~rows:4 ~cols:6 in
  let c1 = Cw.canvas cw in
  let cw = Cw.ensure cw ~rows:8 ~cols:12 in
  let c2 = Cw.canvas cw in
  check bool "new canvas on resize" false (c1 == c2) ;
  check int "new rows" 8 (Cw.rows cw) ;
  check int "new cols" 12 (Cw.cols cw)

(* --- Clear --------------------------------------------------------------- *)

let test_clear () =
  let cw = Cw.create () in
  let cw = Cw.ensure cw ~rows:3 ~cols:5 in
  let c = Cw.canvas_exn cw in
  Canvas.draw_text c ~row:0 ~col:0 ~style:Canvas.default_style "hello" ;
  let _cw = Cw.clear cw in
  let cell = Canvas.get_cell c ~row:0 ~col:0 in
  check string "cleared to space" " " cell.char

let test_clear_before_alloc () =
  let cw = Cw.create () in
  (* Should not raise on empty widget *)
  let _cw = Cw.clear cw in
  ()

(* --- Render -------------------------------------------------------------- *)

let test_render_allocates () =
  let cw = Cw.create () in
  let _output = Cw.render cw ~size:(mk_size 3 5) in
  check int "rows after render" 3 (Cw.rows cw) ;
  check int "cols after render" 5 (Cw.cols cw) ;
  check bool "canvas exists" true (Option.is_some (Cw.canvas cw))

let test_render_returns_ansi () =
  let cw = Cw.create () in
  let cw = Cw.ensure cw ~rows:2 ~cols:4 in
  let c = Cw.canvas_exn cw in
  Canvas.draw_text c ~row:0 ~col:0 ~style:Canvas.default_style "AB" ;
  let output = Cw.render cw ~size:(mk_size 2 4) in
  check bool "output is non-empty" true (String.length output > 0) ;
  check bool "contains A" true (String.contains output 'A') ;
  check bool "contains B" true (String.contains output 'B')

let test_render_resize () =
  let cw = Cw.create () in
  let _out1 = Cw.render cw ~size:(mk_size 3 5) in
  check int "initial rows" 3 (Cw.rows cw) ;
  let _out2 = Cw.render cw ~size:(mk_size 6 10) in
  check int "resized rows" 6 (Cw.rows cw) ;
  check int "resized cols" 10 (Cw.cols cw)

let test_render_same_size_reuses () =
  let cw = Cw.create () in
  let _out = Cw.render cw ~size:(mk_size 4 8) in
  let c1 = Cw.canvas cw in
  let _out = Cw.render cw ~size:(mk_size 4 8) in
  let c2 = Cw.canvas cw in
  check bool "reuses canvas at same size" true (c1 == c2)

(* --- Drawing persists across renders ------------------------------------- *)

let test_drawing_persists () =
  let cw = Cw.create () in
  let cw = Cw.ensure cw ~rows:3 ~cols:10 in
  let c = Cw.canvas_exn cw in
  Canvas.draw_text c ~row:1 ~col:0 ~style:Canvas.default_style "test" ;
  (* Re-render at same size — drawing should still be there *)
  let output = Cw.render cw ~size:(mk_size 3 10) in
  check bool "drawing visible" true (String.contains output 't')

(* --- Test suite ---------------------------------------------------------- *)

let () =
  run
    "Canvas_widget"
    [
      ("creation", [test_case "empty initial state" `Quick test_create_empty]);
      ( "canvas_exn",
        [
          test_case "raises before render" `Quick test_canvas_exn_before_render;
          test_case "succeeds after render" `Quick test_canvas_exn_after_render;
        ] );
      ( "ensure",
        [
          test_case "allocates canvas" `Quick test_ensure_allocates;
          test_case "idempotent same size" `Quick test_ensure_idempotent;
          test_case "resizes on change" `Quick test_ensure_resizes;
        ] );
      ( "clear",
        [
          test_case "clears content" `Quick test_clear;
          test_case "no-op before alloc" `Quick test_clear_before_alloc;
        ] );
      ( "render",
        [
          test_case "allocates on first call" `Quick test_render_allocates;
          test_case "returns ANSI output" `Quick test_render_returns_ansi;
          test_case "resizes on size change" `Quick test_render_resize;
          test_case
            "reuses canvas same size"
            `Quick
            test_render_same_size_reuses;
        ] );
      ( "integration",
        [
          test_case
            "drawing persists across renders"
            `Quick
            test_drawing_persists;
        ] );
    ]
