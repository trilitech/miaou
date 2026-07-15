(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

(* Single-domain coverage of the Matrix driver's double-buffered grid:
   roundtrip get/set, the documented out-of-bounds contract, the
   swap/dirty lifecycle, resize's content-discarding behavior, force_full_redraw,
   and the debug dump. Cross-domain locking claims (this module documents
   itself as "thread-safe: uses internal mutex for cross-domain safety")
   are exercised here only from a single domain; concurrent-access
   behavior is not covered by this suite. *)
open Alcotest
module Buffer = Miaou_driver_matrix.Matrix_buffer
module Cell = Miaou_driver_matrix.Matrix_cell

let cell ?(fg = -1) ?(bg = -1) char : Cell.t =
  Cell.create ~char ~style:{Cell.default_style with fg; bg}

let test_set_get_back_roundtrip () =
  let buf = Buffer.create ~rows:3 ~cols:3 in
  Buffer.set buf ~row:1 ~col:1 (cell "x") ;
  let got = Buffer.get_back buf ~row:1 ~col:1 in
  check string "char roundtrips" "x" got.Cell.char

let test_out_of_bounds_read_returns_empty () =
  let buf = Buffer.create ~rows:2 ~cols:2 in
  let oob_reads = [(-1, 0); (0, -1); (2, 0); (0, 2); (100, 100)] in
  List.iter
    (fun (row, col) ->
      let got_back = Buffer.get_back buf ~row ~col in
      let got_front = Buffer.get_front buf ~row ~col in
      check
        bool
        (Printf.sprintf "get_back(%d,%d) is the empty cell" row col)
        true
        (Cell.is_empty got_back) ;
      check
        bool
        (Printf.sprintf "get_front(%d,%d) is the empty cell" row col)
        true
        (Cell.is_empty got_front))
    oob_reads

let test_out_of_bounds_write_is_silently_ignored () =
  let buf = Buffer.create ~rows:2 ~cols:2 in
  (* Must not raise, and must not corrupt any in-bounds cell. *)
  Buffer.set buf ~row:(-1) ~col:0 (cell "z") ;
  Buffer.set buf ~row:0 ~col:100 (cell "z") ;
  Buffer.set_char buf ~row:5 ~col:5 ~char:"z" ~style:Cell.default_style ;
  for row = 0 to 1 do
    for col = 0 to 1 do
      check
        bool
        (Printf.sprintf "in-bounds cell (%d,%d) stayed empty" row col)
        true
        (Cell.is_empty (Buffer.get_back buf ~row ~col))
    done
  done

let test_swap_and_dirty_lifecycle () =
  let buf = Buffer.create ~rows:2 ~cols:2 in
  check
    bool
    "cell not changed before any write"
    false
    (Buffer.cell_changed buf ~row:0 ~col:0) ;
  Buffer.set buf ~row:0 ~col:0 (cell "a") ;
  check
    bool
    "back differs from front after a write"
    true
    (Buffer.cell_changed buf ~row:0 ~col:0) ;
  check
    string
    "front is unaffected by a back-buffer write"
    " "
    (Buffer.get_front buf ~row:0 ~col:0).Cell.char ;
  Buffer.swap buf ;
  check
    string
    "front now reflects the swapped-in back content"
    "a"
    (Buffer.get_front buf ~row:0 ~col:0).Cell.char ;
  (* Swap is a pointer flip, not a copy: the new back buffer is the old
     (now-stale) front, so it still differs from the new front until the
     next frame redraws it. Only once the same content is written again
     does the cell stop looking "changed". *)
  check
    bool
    "back (old front) differs from new front right after swap"
    true
    (Buffer.cell_changed buf ~row:0 ~col:0) ;
  Buffer.set buf ~row:0 ~col:0 (cell "a") ;
  check
    bool
    "cell no longer changed once redrawn with the same content"
    false
    (Buffer.cell_changed buf ~row:0 ~col:0) ;
  (* Render-dirty flag: independent of front/back content, tracked
     separately for the render domain's "does anything need drawing" gate.
     A fresh buffer starts dirty (it needs an initial render). *)
  check bool "a fresh buffer starts dirty" true (Buffer.is_dirty buf) ;
  Buffer.clear_dirty buf ;
  check bool "not dirty after clear_dirty" false (Buffer.is_dirty buf) ;
  Buffer.mark_dirty buf ;
  check bool "dirty after mark_dirty" true (Buffer.is_dirty buf) ;
  Buffer.clear_dirty buf ;
  check bool "not dirty after clear_dirty again" false (Buffer.is_dirty buf)

let test_resize_replaces_content_and_marks_dirty () =
  (* [matrix_buffer.mli]'s [resize] docstring documents this: resize
     discards existing content and replaces both grids with fresh empty
     cells, forcing a full redraw. This test locks in that behavior. *)
  let buf = Buffer.create ~rows:2 ~cols:2 in
  Buffer.set buf ~row:0 ~col:0 (cell "a") ;
  Buffer.set buf ~row:1 ~col:1 (cell "b") ;
  Buffer.clear_dirty buf ;
  Buffer.resize buf ~rows:4 ~cols:4 ;
  check
    (pair int int)
    "size reports the new dimensions"
    (4, 4)
    (Buffer.size buf) ;
  check bool "resize marks the buffer dirty" true (Buffer.is_dirty buf) ;
  check
    bool
    "content is NOT preserved across a resize (actual behavior)"
    true
    (Cell.is_empty (Buffer.get_back buf ~row:0 ~col:0)
    && Cell.is_empty (Buffer.get_back buf ~row:1 ~col:1)) ;
  check
    bool
    "newly added cells are empty"
    true
    (Cell.is_empty (Buffer.get_back buf ~row:3 ~col:3)) ;
  (* Shrinking behaves the same way (fresh empty grids) and never raises. *)
  Buffer.resize buf ~rows:1 ~cols:1 ;
  check
    (pair int int)
    "size reports the shrunk dimensions"
    (1, 1)
    (Buffer.size buf) ;
  check
    bool
    "out-of-range read after shrink is the empty cell"
    true
    (Cell.is_empty (Buffer.get_back buf ~row:1 ~col:1))

let test_force_full_redraw_invalidates_front_for_diffing () =
  let buf = Buffer.create ~rows:1 ~cols:1 in
  Buffer.set buf ~row:0 ~col:0 (cell "a") ;
  Buffer.swap buf ;
  (* Same content written again: without force_full_redraw the cell would
     not appear changed. *)
  ignore
    (Buffer.with_back_buffer buf (fun ops ->
         ops.Buffer.set_char ~row:0 ~col:0 ~char:"a" ~style:Cell.default_style)) ;
  check
    bool
    "identical content is not marked changed by default"
    false
    (Buffer.cell_changed buf ~row:0 ~col:0) ;
  ignore
    (Buffer.with_back_buffer ~force_full_redraw:true buf (fun ops ->
         ops.Buffer.set_char ~row:0 ~col:0 ~char:"a" ~style:Cell.default_style)) ;
  check
    bool
    "force_full_redraw marks even identical content changed"
    true
    (Buffer.cell_changed buf ~row:0 ~col:0)

let test_mark_region_dirty_scopes_to_the_region () =
  let buf = Buffer.create ~rows:3 ~cols:3 in
  Buffer.set buf ~row:0 ~col:0 (cell "a") ;
  Buffer.set buf ~row:2 ~col:2 (cell "b") ;
  Buffer.swap buf ;
  (* Rewrite the same content everywhere; nothing should look changed yet. *)
  Buffer.set buf ~row:0 ~col:0 (cell "a") ;
  Buffer.set buf ~row:2 ~col:2 (cell "b") ;
  check
    bool
    "unaffected cell not changed before region invalidation"
    false
    (Buffer.cell_changed buf ~row:2 ~col:2) ;
  Buffer.mark_region_dirty buf ~row_start:0 ~row_end:0 ~col_start:0 ~col_end:0 ;
  check
    bool
    "cell inside the marked region now appears changed"
    true
    (Buffer.cell_changed buf ~row:0 ~col:0) ;
  check
    bool
    "cell outside the marked region is unaffected"
    false
    (Buffer.cell_changed buf ~row:2 ~col:2)

let test_dump_to_string_contains_front_buffer_text () =
  let buf = Buffer.create ~rows:1 ~cols:5 in
  Buffer.set buf ~row:0 ~col:0 (cell "h") ;
  Buffer.set buf ~row:0 ~col:1 (cell "i") ;
  Buffer.swap buf ;
  let dumped = Buffer.dump_to_string buf in
  check
    bool
    "dump contains the front-buffer text"
    true
    (Test_helpers.contains_substring dumped "hi")

let () =
  run
    "matrix_buffer"
    [
      ( "buffer",
        [
          test_case "set/get_back roundtrip" `Quick test_set_get_back_roundtrip;
          test_case
            "out-of-bounds reads return the empty cell"
            `Quick
            test_out_of_bounds_read_returns_empty;
          test_case
            "out-of-bounds writes are silently ignored"
            `Quick
            test_out_of_bounds_write_is_silently_ignored;
          test_case "swap/dirty lifecycle" `Quick test_swap_and_dirty_lifecycle;
          test_case
            "resize replaces content and marks dirty"
            `Quick
            test_resize_replaces_content_and_marks_dirty;
          test_case
            "force_full_redraw invalidates front for diffing"
            `Quick
            test_force_full_redraw_invalidates_front_for_diffing;
          test_case
            "mark_region_dirty scopes to the region"
            `Quick
            test_mark_region_dirty_scopes_to_the_region;
          test_case
            "dump_to_string contains front-buffer text"
            `Quick
            test_dump_to_string_contains_front_buffer_text;
        ] );
    ]
