(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(** Term-shaped instantiation of the narrow-seam modal/navigation parity
    scenario (see {!Modal_nav_parity.Modal_nav_scenario} for the honest scope
    note: this is not a full term-driver-loop test). Run in its own
    executable, separate from the matrix instantiation, because
    {!Miaou_core.Modal_manager} is a process-global singleton. *)
open Alcotest

module Scenario = Modal_nav_parity.Modal_nav_scenario

let nav_testable =
  Alcotest.of_pp (fun fmt -> function
    | `Quit -> Format.fprintf fmt "Quit"
    | `Back -> Format.fprintf fmt "Back"
    | `SwitchTo s -> Format.fprintf fmt "SwitchTo %s" s)

let test_enter_commits_and_navigates () =
  let res =
    Scenario.run
      ~read_key:(Scenario.script [Key "Enter"])
      (module Modal_nav_parity.Modal_nav_page.Dummy_page)
  in
  check nav_testable "enter closes modal and navigates" (`SwitchTo "NEXT") res

let test_esc_cancels_without_navigating () =
  (* Untested (even for the term driver) before this parity slice: Esc
     closes the modal via `Cancel`, which the fixture's on_close callback
     does not turn into a pending navigation, so the scenario simply runs
     out of script and terminates on the explicit Quit sentinel. *)
  let res =
    Scenario.run
      ~read_key:(Scenario.script [Key "Esc"; Quit])
      (module Modal_nav_parity.Modal_nav_page.Dummy_page)
  in
  check nav_testable "esc cancels; no navigation is triggered" `Quit res

let test_arrow_keys_are_dropped_before_commit () =
  (* Mirrors the term driver's documented behavior of not reacting to
     Up/Down/Left/Right: they reach the active modal, which ignores them,
     leaving the eventual Enter free to commit as usual. *)
  let res =
    Scenario.run
      ~read_key:(Scenario.script [Key "Up"; Key "Down"; Key "Enter"])
      (module Modal_nav_parity.Modal_nav_page.Dummy_page)
  in
  check
    nav_testable
    "arrow keys dropped, enter still commits"
    (`SwitchTo "NEXT")
    res

let () =
  run
    "modal_nav_parity_term"
    [
      ( "modal_navigation",
        [
          test_case
            "enter closes modal and navigates"
            `Quick
            test_enter_commits_and_navigates;
          test_case
            "esc cancels without navigating"
            `Quick
            test_esc_cancels_without_navigating;
          test_case
            "arrow keys dropped before commit"
            `Quick
            test_arrow_keys_are_dropped_before_commit;
        ] );
    ]
