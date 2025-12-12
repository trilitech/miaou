open Alcotest

module Good_page : Miaou_core.Tui_page.PAGE_SIG = struct
  type state = unit

  type msg = unit

  let init () = ()

  let update s _ = s

  let view _ ~focus:_ ~size:_ = "good"

  let move s _ = s

  let refresh s = s

  let enter s = s

  let service_select s _ = s

  let service_cycle s _ = s

  let back s = s

  let keymap _ = [("a", Fun.id, "action")]

  let handled_keys () = [Miaou_core.Keys.Char "a"; Miaou_core.Keys.Enter]

  let handle_modal_key s _ ~size:_ = s

  let handle_key s _ ~size:_ = s

  let next_page _ = None

  let has_modal _ = false
end

module Bad_page : Miaou_core.Tui_page.PAGE_SIG = struct
  type state = unit

  type msg = unit

  let init () = ()

  let update s _ = s

  let view _ ~focus:_ ~size:_ = "bad"

  let move s _ = s

  let refresh s = s

  let enter s = s

  let service_select s _ = s

  let service_cycle s _ = s

  let back s = s

  let keymap _ = [("C-q", Fun.id, "quit")]

  (* This page tries to handle a global key (C-q = Quit) *)
  let handled_keys () = [Miaou_core.Keys.Control "q"]

  let handle_modal_key s _ ~size:_ = s

  let handle_key s _ ~size:_ = s

  let next_page _ = None

  let has_modal _ = false
end

module Conflicting_page : Miaou_core.Tui_page.PAGE_SIG = struct
  type state = unit

  type msg = unit

  let init () = ()

  let update s _ = s

  let view _ ~focus:_ ~size:_ = "conflicting"

  let move s _ = s

  let refresh s = s

  let enter s = s

  let service_select s _ = s

  let service_cycle s _ = s

  let back s = s

  let keymap _ = [("a", Fun.id, "other action")]

  (* This page handles same key as Good_page *)
  let handled_keys () = [Miaou_core.Keys.Char "a"]

  let handle_modal_key s _ ~size:_ = s

  let handle_key s _ ~size:_ = s

  let next_page _ = None

  let has_modal _ = false
end

let test_valid_page_registration () =
  let module Reg = Miaou_core.Registry in
  Reg.unregister "test.good" ;
  (* Should succeed without exception *)
  Reg.register "test.good" (module Good_page) ;
  check bool "page registered" true (Reg.exists "test.good")

let test_invalid_page_global_key_conflict () =
  let module Reg = Miaou_core.Registry in
  Reg.unregister "test.bad" ;
  (* Should raise an exception *)
  try
    Reg.register "test.bad" (module Bad_page) ;
    fail "Expected exception for global key conflict"
  with Failure msg ->
    check
      bool
      "error mentions reserved keys"
      true
      (String.length msg > 0
      && (Str.string_match (Str.regexp ".*reserved.*") msg 0
         || Str.string_match (Str.regexp ".*global.*") msg 0))

let test_inter_page_conflict_detection () =
  let module Reg = Miaou_core.Registry in
  (* Clear registry *)
  Reg.unregister "test.good" ;
  Reg.unregister "test.conflicting" ;
  (* Register two pages with overlapping keys *)
  Reg.register "test.good" (module Good_page) ;
  Reg.register "test.conflicting" (module Conflicting_page) ;
  (* Check for conflicts *)
  let conflicts = Reg.check_all_conflicts () in
  check
    bool
    "conflict detected"
    true
    (List.exists (fun (key, _) -> key = "a") conflicts) ;
  (* Check report *)
  match Reg.conflict_report () with
  | None -> fail "Expected conflict report"
  | Some report ->
      check bool "report mentions both pages" true (String.length report > 0)

let test_no_conflicts_when_clean () =
  let module Reg = Miaou_core.Registry in
  (* Clear and register only one page *)
  Reg.unregister "test.good" ;
  Reg.unregister "test.conflicting" ;
  Reg.register "test.good.solo" (module Good_page) ;
  (* Should have no conflicts *)
  let conflicts = Reg.check_all_conflicts () in
  check int "no conflicts" 0 (List.length conflicts) ;
  check (option string) "no conflict report" None (Reg.conflict_report ())

let () =
  run
    "Registry Validation"
    [
      ( "key validation",
        [
          test_case
            "valid page registers successfully"
            `Quick
            test_valid_page_registration;
          test_case
            "page with global key conflicts rejected"
            `Quick
            test_invalid_page_global_key_conflict;
        ] );
      ( "conflict detection",
        [
          test_case
            "inter-page conflicts detected"
            `Quick
            test_inter_page_conflict_detection;
          test_case "no false positives" `Quick test_no_conflicts_when_clean;
        ] );
    ]
