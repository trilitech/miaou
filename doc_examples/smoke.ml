(******************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(******************************************************************************)

open Alcotest

let contains_substring ~needle haystack =
  let nlen = String.length needle in
  let hlen = String.length haystack in
  let rec loop i =
    if i + nlen > hlen then false
    else if String.sub haystack i nlen = needle then true
    else loop (i + 1)
  in
  nlen = 0 || loop 0

let check_contains label ~needle haystack =
  check bool label true (contains_substring ~needle haystack)

let test_first_app () =
  let initial = Miaou_doc_examples.First_app.render_initial () in
  check_contains "initial counter shows zero" ~needle:"Count: 0" initial ;
  let after = Miaou_doc_examples.First_app.render_after ["Up"; "Up"; "Down"] in
  check_contains "updated counter shows one" ~needle:"Count: 1" after

let test_responsive_dashboard () =
  let open Miaou_doc_examples.Responsive_dashboard in
  check string "narrow" "single stacked column" (layout_for_width 40 |> describe) ;
  check string "medium" "two by two grid" (layout_for_width 80 |> describe) ;
  check string "wide" "four tiles in one row" (layout_for_width 140 |> describe)

let test_themed_app () =
  let rendered = Miaou_doc_examples.Themed_app.render_panel () in
  check_contains "emphasis heading" ~needle:"Deployment status" rendered ;
  check_contains "success message" ~needle:"Node is running" rendered ;
  check_contains "muted footer" ~needle:"semantic styles" rendered

let test_chart_dashboard () =
  let rendered = Miaou_doc_examples.Chart_dashboard.sample () in
  check_contains "sparkline label" ~needle:"Latency" rendered

let test_modal_form_commit () =
  let confirmed, name, backend =
    Miaou_doc_examples.Modal_form.sample_results ()
  in
  check bool "confirmed" true confirmed ;
  check (option string) "name" (Some "mainnet-node") name ;
  check (option string) "backend" (Some "matrix") backend

let test_modal_form_cancel () =
  let open Miaou_doc_examples.Modal_form in
  check bool "cancel does not confirm" false (confirmed_delete `Cancel) ;
  check
    (option string)
    "cancel discards input"
    None
    (submitted_name `Cancel ~text:"mainnet-node") ;
  check
    (option string)
    "cancel discards selection"
    None
    (selected_backend `Cancel ~selected:(Some "matrix"))

let () =
  run
    "doc examples"
    [
      ( "smoke",
        [
          test_case "first app" `Quick test_first_app;
          test_case "responsive dashboard" `Quick test_responsive_dashboard;
          test_case "themed app" `Quick test_themed_app;
          test_case "chart dashboard" `Quick test_chart_dashboard;
          test_case "modal form commit" `Quick test_modal_form_commit;
          test_case "modal form cancel" `Quick test_modal_form_cancel;
        ] );
    ]
