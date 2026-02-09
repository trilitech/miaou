(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

open Alcotest
module Navigation = Miaou_core.Navigation
module Direct_page = Miaou_core.Direct_page
module Tui_page = Miaou_core.Tui_page

let size = LTerm_geom.{rows = 24; cols = 80}

let nav_option_testable =
  Alcotest.testable
    (fun fmt -> function
      | None -> Fmt.string fmt "None"
      | Some (Navigation.Goto s) -> Fmt.pf fmt "Some (Goto %S)" s
      | Some Navigation.Back -> Fmt.string fmt "Some Back"
      | Some Navigation.Quit -> Fmt.string fmt "Some Quit")
    ( = )

(* Test page: counter with navigation effects *)
module Counter_input = struct
  type state = int

  let init () = 0

  let view n ~focus:_ ~size:_ = string_of_int n

  let on_key n key ~size:_ =
    match key with
    | "Up" -> n + 1
    | "Down" -> n - 1
    | "q" ->
        Direct_page.quit () ;
        n
    | "g" ->
        Direct_page.navigate "other" ;
        n
    | "b" ->
        Direct_page.go_back () ;
        n
    | _ -> n
end

module Counter = Direct_page.Make (Direct_page.With_defaults (Counter_input))

(* -- make tests -- *)

let test_init_wraps () =
  let ps = Counter.init () in
  (* State is abstract through PAGE_SIG, but we can check via view *)
  let output = Counter.view ps ~focus:true ~size in
  check string "init state renders as 0" "0" output ;
  check nav_option_testable "no pending nav" None (Navigation.pending ps)

let test_view_unwraps () =
  let ps = Counter.init () in
  let ps' = Counter.handle_key ps "Up" ~size in
  let output = Counter.view ps' ~focus:true ~size in
  check string "view shows updated state" "1" output

(* -- effects tests -- *)

let test_navigate () =
  let ps = Counter.init () in
  let ps' = Counter.handle_key ps "g" ~size in
  check
    nav_option_testable
    "navigates to other"
    (Some (Navigation.Goto "other"))
    (Navigation.pending ps')

let test_go_back () =
  let ps = Counter.init () in
  let ps' = Counter.handle_key ps "b" ~size in
  check
    nav_option_testable
    "goes back"
    (Some Navigation.Back)
    (Navigation.pending ps')

let test_quit () =
  let ps = Counter.init () in
  let ps' = Counter.handle_key ps "q" ~size in
  check
    nav_option_testable
    "quits"
    (Some Navigation.Quit)
    (Navigation.pending ps')

let test_no_effect () =
  let ps = Counter.init () in
  let ps' = Counter.handle_key ps "Up" ~size in
  let output = Counter.view ps' ~focus:true ~size in
  check string "state incremented" "1" output ;
  check nav_option_testable "no nav" None (Navigation.pending ps')

let test_state_and_nav () =
  (* Press Up then g: first increment, then navigate. *)
  let ps = Counter.init () in
  let ps' = Counter.handle_key ps "Up" ~size in
  let ps'' = Counter.handle_key ps' "g" ~size in
  let output = Counter.view ps'' ~focus:true ~size in
  check string "state preserved after nav" "1" output ;
  check
    nav_option_testable
    "nav set"
    (Some (Navigation.Goto "other"))
    (Navigation.pending ps'')

let test_last_wins () =
  let module Double_nav = Direct_page.Make (Direct_page.With_defaults (struct
    type state = int

    let init () = 0

    let view n ~focus:_ ~size:_ = string_of_int n

    let on_key n key ~size:_ =
      match key with
      | "x" ->
          Direct_page.navigate "first" ;
          Direct_page.navigate "second" ;
          n
      | _ -> n
  end)) in
  let ps = Double_nav.init () in
  let ps' = Double_nav.handle_key ps "x" ~size in
  check
    nav_option_testable
    "last nav wins"
    (Some (Navigation.Goto "second"))
    (Navigation.pending ps')

(* -- run tests -- *)

let nav_testable =
  testable
    (fun fmt -> function
      | `Goto s -> Fmt.pf fmt "`Goto %s" s
      | `Back -> Fmt.string fmt "`Back"
      | `Quit -> Fmt.string fmt "`Quit")
    ( = )

let test_run_captures () =
  let result, nav =
    Direct_page.run (fun () ->
        Direct_page.navigate "target" ;
        42)
  in
  check int "result" 42 result ;
  check (option nav_testable) "nav captured" (Some (`Goto "target")) nav

let test_run_no_nav () =
  let result, nav = Direct_page.run (fun () -> 99) in
  check int "result" 99 result ;
  check (option nav_testable) "no nav" None nav

(* -- keymap test -- *)

let test_keymap_display_only () =
  let module Page = Direct_page.Make (struct
    include Direct_page.With_defaults (struct
      type state = unit

      let init () = ()

      let view () ~focus:_ ~size:_ = ""

      let on_key () _ ~size:_ = ()
    end)

    let keymap () = [("Up", "Increment"); ("q", "Quit")]
  end) in
  let ps = Page.init () in
  let km = Page.keymap ps in
  check int "two entries" 2 (List.length km) ;
  List.iter
    (fun (entry : Page.key_binding) ->
      check bool "display_only" true entry.display_only)
    km

(* -- defaults tests -- *)

let test_defaults_identity () =
  let module D = Direct_page.With_defaults (Counter_input) in
  let s = D.init () in
  check int "refresh is identity" s (D.refresh s) ;
  check int "on_modal_key is identity" s (D.on_modal_key s "x" ~size) ;
  check bool "has_modal is false" false (D.has_modal s) ;
  check (list (pair string string)) "keymap is empty" [] (D.keymap s)

let test_defaults_override () =
  let module D = struct
    include Direct_page.With_defaults (Counter_input)

    let refresh s = s + 1

    let keymap _ = [("r", "Refresh")]
  end in
  let s = D.init () in
  check int "refresh overridden" 1 (D.refresh s) ;
  check
    (list (pair string string))
    "keymap overridden"
    [("r", "Refresh")]
    (D.keymap s)

let () =
  run
    "Direct_page"
    [
      ( "make",
        [
          test_case "init_wraps" `Quick test_init_wraps;
          test_case "view_unwraps" `Quick test_view_unwraps;
        ] );
      ( "effects",
        [
          test_case "navigate" `Quick test_navigate;
          test_case "go_back" `Quick test_go_back;
          test_case "quit" `Quick test_quit;
          test_case "no_effect" `Quick test_no_effect;
          test_case "state_and_nav" `Quick test_state_and_nav;
          test_case "last_wins" `Quick test_last_wins;
        ] );
      ( "run",
        [
          test_case "captures" `Quick test_run_captures;
          test_case "no_nav" `Quick test_run_no_nav;
        ] );
      ("keymap", [test_case "display_only" `Quick test_keymap_display_only]);
      ( "defaults",
        [
          test_case "identity" `Quick test_defaults_identity;
          test_case "override" `Quick test_defaults_override;
        ] );
    ]
