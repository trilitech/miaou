(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

open Alcotest
module FR = Miaou_internals.Focus_ring

let test_create () =
  let r = FR.create ["a"; "b"; "c"] in
  check int "total" 3 (FR.total r) ;
  check (option string) "current" (Some "a") (FR.current r)

let test_create_empty () =
  let r = FR.create [] in
  check int "total" 0 (FR.total r) ;
  check (option string) "current" None (FR.current r)

let test_move_next () =
  let r = FR.create ["a"; "b"; "c"] in
  let r = FR.move r `Next in
  check (option string) "after next" (Some "b") (FR.current r)

let test_move_prev () =
  let r = FR.create ["a"; "b"; "c"] in
  let r = FR.move r `Prev in
  check (option string) "wrap to last" (Some "c") (FR.current r)

let test_wrap_forward () =
  let r = FR.create ["a"; "b"] in
  let r = FR.move r `Next in
  let r = FR.move r `Next in
  check (option string) "wrap around" (Some "a") (FR.current r)

let test_is_focused () =
  let r = FR.create ["a"; "b"; "c"] in
  check bool "a focused" true (FR.is_focused r "a") ;
  check bool "b not focused" false (FR.is_focused r "b")

let test_focus_by_name () =
  let r = FR.create ["a"; "b"; "c"] in
  let r = FR.focus r "c" in
  check (option string) "focused c" (Some "c") (FR.current r)

let test_focus_unknown () =
  let r = FR.create ["a"; "b"] in
  let r = FR.focus r "z" in
  check (option string) "unchanged" (Some "a") (FR.current r)

let test_handle_tab () =
  let r = FR.create ["a"; "b"; "c"] in
  let r, status = FR.handle_key r ~key:"Tab" in
  check (option string) "after tab" (Some "b") (FR.current r) ;
  check bool "handled" true (status = `Handled)

let test_handle_shift_tab () =
  let r = FR.create ["a"; "b"; "c"] in
  let r, _ = FR.handle_key r ~key:"S-Tab" in
  check (option string) "after s-tab" (Some "c") (FR.current r)

let test_handle_other_bubbles () =
  let r = FR.create ["a"; "b"] in
  let r', status = FR.handle_key r ~key:"Enter" in
  check bool "bubbles" true (status = `Bubble) ;
  check (option string) "unchanged" (Some "a") (FR.current r')

let test_set_focusable_skip () =
  let r = FR.create ["a"; "b"; "c"] in
  let r = FR.set_focusable r "b" false in
  check int "focusable count" 2 (FR.focusable_count r) ;
  let r = FR.move r `Next in
  check (option string) "skips b" (Some "c") (FR.current r)

let test_disable_current () =
  let r = FR.create ["a"; "b"; "c"] in
  let r = FR.set_focusable r "a" false in
  check (option string) "moved to next" (Some "b") (FR.current r)

let test_single_slot () =
  let r = FR.create ["only"] in
  check (option string) "current" (Some "only") (FR.current r) ;
  let r = FR.move r `Next in
  check (option string) "stays" (Some "only") (FR.current r)

let test_current_index () =
  let r = FR.create ["a"; "b"; "c"] in
  check (option int) "index 0" (Some 0) (FR.current_index r) ;
  let r = FR.move r `Next in
  check (option int) "index 1" (Some 1) (FR.current_index r)

(* Scope tests *)

let test_scope_create () =
  let parent = FR.create ["left"; "right"] in
  let left = FR.create ["x"; "y"] in
  let sc = FR.scope ~parent ~children:[("left", left)] in
  check bool "not in child" false (FR.in_child sc) ;
  check
    (option string)
    "active is parent"
    (Some "left")
    (FR.current (FR.active sc))

let test_scope_enter () =
  let parent = FR.create ["left"; "right"] in
  let left = FR.create ["x"; "y"] in
  let sc = FR.scope ~parent ~children:[("left", left)] in
  let sc = FR.enter sc in
  check bool "in child" true (FR.in_child sc) ;
  check (option string) "child id" (Some "left") (FR.active_child_id sc) ;
  check (option string) "child ring" (Some "x") (FR.current (FR.active sc))

let test_scope_exit () =
  let parent = FR.create ["left"; "right"] in
  let left = FR.create ["x"; "y"] in
  let sc = FR.scope ~parent ~children:[("left", left)] in
  let sc = FR.enter sc in
  let sc = FR.exit sc in
  check bool "back to parent" false (FR.in_child sc) ;
  check (option string) "parent focus" (Some "left") (FR.current (FR.active sc))

let test_scope_tab_in_child () =
  let parent = FR.create ["left"; "right"] in
  let left = FR.create ["x"; "y"] in
  let sc = FR.scope ~parent ~children:[("left", left)] in
  let sc = FR.enter sc in
  let sc, _ = FR.handle_scope_key sc ~key:"Tab" in
  check (option string) "moved in child" (Some "y") (FR.current (FR.active sc)) ;
  check bool "still in child" true (FR.in_child sc)

let test_scope_esc_exits () =
  let parent = FR.create ["left"; "right"] in
  let left = FR.create ["x"; "y"] in
  let sc = FR.scope ~parent ~children:[("left", left)] in
  let sc = FR.enter sc in
  let sc, status = FR.handle_scope_key sc ~key:"Esc" in
  check bool "handled" true (status = `Handled) ;
  check bool "exited" false (FR.in_child sc)

let test_scope_enter_no_child () =
  let parent = FR.create ["left"; "right"] in
  let sc = FR.scope ~parent ~children:[] in
  let sc' = FR.enter sc in
  check bool "still parent" false (FR.in_child sc')

let test_scope_enter_via_key () =
  let parent = FR.create ["left"; "right"] in
  let left = FR.create ["x"; "y"] in
  let sc = FR.scope ~parent ~children:[("left", left)] in
  let sc, status = FR.handle_scope_key sc ~key:"Enter" in
  check bool "handled" true (status = `Handled) ;
  check bool "entered" true (FR.in_child sc)

let () =
  run
    "focus_ring"
    [
      ( "flat_ring",
        [
          test_case "create" `Quick test_create;
          test_case "create empty" `Quick test_create_empty;
          test_case "move next" `Quick test_move_next;
          test_case "move prev" `Quick test_move_prev;
          test_case "wrap forward" `Quick test_wrap_forward;
          test_case "is_focused" `Quick test_is_focused;
          test_case "focus by name" `Quick test_focus_by_name;
          test_case "focus unknown" `Quick test_focus_unknown;
          test_case "handle tab" `Quick test_handle_tab;
          test_case "handle shift-tab" `Quick test_handle_shift_tab;
          test_case "handle other bubbles" `Quick test_handle_other_bubbles;
          test_case "set_focusable skip" `Quick test_set_focusable_skip;
          test_case "disable current" `Quick test_disable_current;
          test_case "single slot" `Quick test_single_slot;
          test_case "current index" `Quick test_current_index;
        ] );
      ( "scope",
        [
          test_case "scope create" `Quick test_scope_create;
          test_case "scope enter" `Quick test_scope_enter;
          test_case "scope exit" `Quick test_scope_exit;
          test_case "scope tab in child" `Quick test_scope_tab_in_child;
          test_case "scope esc exits" `Quick test_scope_esc_exits;
          test_case "scope enter no child" `Quick test_scope_enter_no_child;
          test_case "scope enter via key" `Quick test_scope_enter_via_key;
        ] );
    ]
