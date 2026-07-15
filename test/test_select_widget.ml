(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Mathias Bourgoin <mathias.bourgoin@atacama.tech>        *)
(*                                                                            *)
(******************************************************************************)

(* Regression tests for crash-ub-fixes slice S2: [Select_widget]'s cursor
   accessors must be total (no exception) for empty item lists and stale
   cursor positions, instead of raising via [List.nth]. *)

open Alcotest
module Select = Miaou_widgets_input.Select_widget

let test_get_selection_empty () =
  let w =
    Select.open_centered ~title:"t" ~items:[] ~to_string:(fun s -> s) ()
  in
  check bool "no selection on empty list" true (Select.get_selection w = None)

let test_value_opt_empty () =
  let w =
    Select.open_centered ~title:"t" ~items:[] ~to_string:(fun s -> s) ()
  in
  check bool "value_opt is None on empty list" true (Select.value_opt w = None)

let test_get_selection_populated () =
  let w =
    Select.open_centered
      ~title:"t"
      ~items:["a"; "b"; "c"]
      ~to_string:(fun s -> s)
      ()
  in
  check
    (option string)
    "first item selected"
    (Some "a")
    (Select.get_selection w)

let test_value_opt_populated () =
  let w =
    Select.open_centered
      ~title:"t"
      ~items:["a"; "b"; "c"]
      ~to_string:(fun s -> s)
      ()
  in
  check
    (option string)
    "value_opt returns label"
    (Some "a")
    (Select.value_opt w)

let test_end_key_at_last_index () =
  (* Regression: End moves cursor to the last valid index; get_selection
     must not raise even with the maximal cursor value. *)
  let w =
    Select.open_centered
      ~title:"t"
      ~items:["a"; "b"; "c"]
      ~to_string:(fun s -> s)
      ()
  in
  let w = Select.handle_key w ~key:"End" in
  check (option string) "last item selected" (Some "c") (Select.get_selection w)

let test_stale_cursor_after_list_shrinks () =
  (* The actual defect class named in the crash-ub-fixes plan: drive the
     cursor to the end of a populated list, then shrink the item list
     in place (via [set_items], which deliberately does not reclamp the
     cursor) so the cursor is now stale (out of range for the new,
     shorter list). [get_selection]/[value_opt] must report "no
     selection" (None) rather than raising via List.nth. *)
  let w =
    Select.open_centered
      ~title:"t"
      ~items:["a"; "b"; "c"; "d"; "e"]
      ~to_string:(fun s -> s)
      ()
  in
  let w = Select.handle_key w ~key:"End" in
  check
    (option string)
    "cursor at last index before shrinking"
    (Some "e")
    (Select.get_selection w) ;
  (* Shrink from 5 items to 2: the cursor (now pointing at index 4) is
     stale for the new list. *)
  let w = Select.set_items w ["x"; "y"] in
  check
    (option string)
    "get_selection is None for a stale cursor (no exception)"
    None
    (Select.get_selection w) ;
  check
    bool
    "value_opt is None for a stale cursor (no exception)"
    true
    (Select.value_opt w = None) ;
  (* Home brings the cursor back in range; selection resumes normally.
     [handle_key] doesn't reclamp automatically for set_items (only for
     Up/Down/Home/End movement), so an explicit Home confirms the widget
     recovers once the cursor is valid again rather than staying wedged. *)
  let w = Select.handle_key w ~key:"Home" in
  check
    (option string)
    "selection resumes once cursor is back in range"
    (Some "x")
    (Select.get_selection w)

let () =
  run
    "select_widget"
    [
      ( "select_widget",
        [
          test_case "get_selection empty" `Quick test_get_selection_empty;
          test_case "value_opt empty" `Quick test_value_opt_empty;
          test_case
            "get_selection populated"
            `Quick
            test_get_selection_populated;
          test_case "value_opt populated" `Quick test_value_opt_populated;
          test_case "End key at last index" `Quick test_end_key_at_last_index;
          test_case
            "stale cursor after list shrinks via set_items"
            `Quick
            test_stale_cursor_after_list_shrinks;
        ] );
    ]
