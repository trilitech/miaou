(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

open Alcotest
module FC = Miaou_internals.Focus_container
module FR = Miaou_internals.Focus_ring
module Key_event = Miaou_interfaces.Key_event

(* --- Inline test widgets --- *)

type counter = {value : int}

let counter_ops : counter FC.widget_ops =
  {
    render =
      (fun c ~focus -> (if focus then "> " else "  ") ^ string_of_int c.value);
    on_key =
      (fun c ~key ->
        match key with
        | "Up" -> ({value = c.value + 1}, Key_event.Handled)
        | "Down" -> ({value = c.value - 1}, Key_event.Handled)
        | _ -> (c, Key_event.Bubble));
  }

type label = {text : string}

let label_ops : label FC.widget_ops =
  {
    render = (fun l ~focus -> (if focus then "> " else "  ") ^ l.text);
    on_key = (fun l ~key:_ -> (l, Key_event.Bubble));
  }

let make_two () =
  FC.create
    [FC.slot "a" counter_ops {value = 0}; FC.slot "b" label_ops {text = "hi"}]

(* --- Core tests --- *)

let test_create () =
  let c = make_two () in
  check int "count" 2 (FC.count c) ;
  check (option string) "focused" (Some "a") (FC.focused_id c)

let test_render_all () =
  let c = make_two () in
  let items = FC.render_all c in
  check int "items" 2 (List.length items) ;
  let id0, foc0, _ = List.nth items 0 in
  let id1, foc1, _ = List.nth items 1 in
  check string "first id" "a" id0 ;
  check bool "first focused" true foc0 ;
  check string "second id" "b" id1 ;
  check bool "second not focused" false foc1

let test_tab_cycles () =
  let c = make_two () in
  let c', result = FC.on_key c ~key:"Tab" in
  check (option string) "after tab" (Some "b") (FC.focused_id c') ;
  match result with
  | Key_event.Handled -> ()
  | Key_event.Bubble -> fail "expected Handled"

let test_shift_tab () =
  let c = make_two () in
  let c', _result = FC.on_key c ~key:"S-Tab" in
  check (option string) "wrap to last" (Some "b") (FC.focused_id c')

let test_key_routing () =
  let w = FC.witness () in
  let c =
    FC.create
      [
        FC.slot_w "a" counter_ops {value = 0} w;
        FC.slot "b" label_ops {text = "x"};
      ]
  in
  let c', result = FC.on_key c ~key:"Up" in
  (match result with
  | Key_event.Handled -> ()
  | Key_event.Bubble -> fail "expected Handled") ;
  match FC.get c' "a" w with
  | Some v -> check int "incremented" 1 v.value
  | None -> fail "witness get failed"

let test_bubble () =
  let c = make_two () in
  (* Focus is on "a" (counter), send unknown key *)
  let _, result = FC.on_key c ~key:"Unknown" in
  match result with
  | Key_event.Bubble -> ()
  | Key_event.Handled -> fail "expected Bubble"

let test_focus_by_name () =
  let c = make_two () in
  let c' = FC.focus c "b" in
  check (option string) "focused b" (Some "b") (FC.focused_id c')

let test_render_focused () =
  let c = make_two () in
  match FC.render_focused c with
  | Some (id, _rendered) -> check string "focused id" "a" id
  | None -> fail "expected Some"

let test_empty () =
  let c = FC.create [] in
  check int "count" 0 (FC.count c) ;
  check (option string) "focused" None (FC.focused_id c) ;
  let c', result = FC.on_key c ~key:"Tab" in
  ignore c' ;
  ignore result

let test_single_slot () =
  let c = FC.create [FC.slot "only" label_ops {text = "alone"}] in
  let c', _ = FC.on_key c ~key:"Tab" in
  check (option string) "stays" (Some "only") (FC.focused_id c')

let test_ring_access () =
  let c = make_two () in
  let r = FC.ring c in
  check int "ring total" 2 (FR.total r) ;
  check (option string) "ring current" (Some "a") (FR.current r)

let test_multiple_routes () =
  let wa = FC.witness () in
  let wb = FC.witness () in
  let c =
    FC.create
      [
        FC.slot_w "a" counter_ops {value = 0} wa;
        FC.slot_w "b" counter_ops {value = 10} wb;
      ]
  in
  (* Key to a *)
  let c, _ = FC.on_key c ~key:"Up" in
  (* Tab to b *)
  let c, _ = FC.on_key c ~key:"Tab" in
  (* Key to b *)
  let c, _ = FC.on_key c ~key:"Up" in
  (match FC.get c "a" wa with
  | Some v -> check int "a incremented" 1 v.value
  | None -> fail "get a") ;
  match FC.get c "b" wb with
  | Some v -> check int "b incremented" 11 v.value
  | None -> fail "get b"

(* --- Witness tests --- *)

let test_witness_get () =
  let w = FC.witness () in
  let c = FC.create [FC.slot_w "x" counter_ops {value = 42} w] in
  match FC.get c "x" w with
  | Some v -> check int "value" 42 v.value
  | None -> fail "expected Some"

let test_witness_wrong_id () =
  let w = FC.witness () in
  let c = FC.create [FC.slot_w "x" counter_ops {value = 42} w] in
  check bool "wrong id" true (Option.is_none (FC.get c "y" w))

let test_witness_set () =
  let w = FC.witness () in
  let c = FC.create [FC.slot_w "x" counter_ops {value = 0} w] in
  let c' = FC.set c "x" w {value = 99} in
  match FC.get c' "x" w with
  | Some v -> check int "updated" 99 v.value
  | None -> fail "expected Some after set"

(* --- Adapter tests --- *)

let test_ops_simple () =
  let ops =
    FC.ops_simple
      ~render:(fun (l : label) ~focus -> (if focus then ">" else " ") ^ l.text)
      ~handle_key:(fun l ~key:_ -> l)
  in
  let rendered = ops.render {text = "hi"} ~focus:true in
  check bool "renders" true (String.length rendered > 0) ;
  let _, result = ops.on_key {text = "hi"} ~key:"x" in
  match result with
  | Key_event.Bubble -> ()
  | Key_event.Handled -> fail "simple always bubbles"

let test_ops_bool () =
  let ops =
    FC.ops_bool
      ~render:(fun (c : counter) ~focus ->
        (if focus then ">" else " ") ^ string_of_int c.value)
      ~handle_key:(fun c ~key ->
        match key with "fire" -> (c, true) | _ -> (c, false))
  in
  let _, result1 = ops.on_key {value = 0} ~key:"fire" in
  (match result1 with
  | Key_event.Handled -> ()
  | Key_event.Bubble -> fail "expected Handled on fire") ;
  let _, result2 = ops.on_key {value = 0} ~key:"other" in
  match result2 with
  | Key_event.Bubble -> ()
  | Key_event.Handled -> fail "expected Bubble on other"

let () =
  run
    "Focus_container"
    [
      ( "core",
        [
          test_case "create" `Quick test_create;
          test_case "render_all" `Quick test_render_all;
          test_case "tab_cycles" `Quick test_tab_cycles;
          test_case "shift_tab" `Quick test_shift_tab;
          test_case "key_routing" `Quick test_key_routing;
          test_case "bubble" `Quick test_bubble;
          test_case "focus_by_name" `Quick test_focus_by_name;
          test_case "render_focused" `Quick test_render_focused;
          test_case "empty" `Quick test_empty;
          test_case "single_slot" `Quick test_single_slot;
          test_case "ring_access" `Quick test_ring_access;
          test_case "multiple_routes" `Quick test_multiple_routes;
        ] );
      ( "witness",
        [
          test_case "get" `Quick test_witness_get;
          test_case "wrong_id" `Quick test_witness_wrong_id;
          test_case "set" `Quick test_witness_set;
        ] );
      ( "adapters",
        [
          test_case "ops_simple" `Quick test_ops_simple;
          test_case "ops_bool" `Quick test_ops_bool;
        ] );
    ]
