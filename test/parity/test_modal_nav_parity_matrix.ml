(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(** Matrix-shaped instantiation of the narrow-seam modal/navigation parity
    scenario (see {!Modal_nav_parity.Modal_nav_scenario} for the honest scope
    note: the matrix driver's real loop needs an unconstructible
    [Eio_unix.Stdenv.base] plus a real [Domain] over non-domain-safe globals,
    so this is a scripted fake, not a full matrix-driver-loop test). Run in
    its own executable, separate from the term instantiation, because
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
  let res =
    Scenario.run
      ~read_key:(Scenario.script [Key "Esc"; Quit])
      (module Modal_nav_parity.Modal_nav_page.Dummy_page)
  in
  check nav_testable "esc cancels; no navigation is triggered" `Quit res

let test_matrix_style_mouse_key_is_inert_before_commit () =
  (* Matrix producer-side key strings use a "Mouse:row:col" shape (see T4/T6
     mouse parity). The modal's key handler only reacts to "Enter"/"Esc", so
     a raw mouse-format string reaching it must not crash and must not
     commit; the following Enter still commits normally. *)
  let res =
    Scenario.run
      ~read_key:(Scenario.script [Key "Mouse:3:5"; Key "Enter"])
      (module Modal_nav_parity.Modal_nav_page.Dummy_page)
  in
  check
    nav_testable
    "mouse-format key inert, enter still commits"
    (`SwitchTo "NEXT")
    res

let () =
  run
    "modal_nav_parity_matrix"
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
            "matrix-style mouse key is inert before commit"
            `Quick
            test_matrix_style_mouse_key_is_inert_before_commit;
        ] );
    ]
