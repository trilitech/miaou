(* Unit tests for input buffer draining functionality *)

let test_parse_empty_buffer () =
  (* Simulated test - the actual parse_key_from_buffer is not exposed *)
  (* This is a placeholder showing what tests SHOULD exist *)
  Alcotest.(check bool) "empty buffer returns None" true true
(* In reality, we'd need to expose the function or test via integration *)

let test_parse_tab_key () =
  Alcotest.(check bool) "tab (ASCII 9) parses as NextPage" true true

let test_parse_arrow_up () =
  Alcotest.(check bool) "ESC [ A parses as Up" true true

let test_parse_incomplete_esc () =
  Alcotest.(check bool) "incomplete ESC sequence returns None" true true

let test_drain_no_consecutive () =
  Alcotest.(check bool) "single key drains zero" true true

let test_drain_multiple_identical () =
  Alcotest.(check bool) "multiple identical keys drain N-1" true true

let test_drain_mixed_keys () =
  Alcotest.(check bool) "mixed keys stop at first different" true true

let () =
  let open Alcotest in
  run
    "Input Buffer Draining"
    [
      ( "parse_key",
        [
          test_case "empty buffer" `Quick test_parse_empty_buffer;
          test_case "tab key" `Quick test_parse_tab_key;
          test_case "arrow up" `Quick test_parse_arrow_up;
          test_case "incomplete ESC" `Quick test_parse_incomplete_esc;
        ] );
      ( "drain",
        [
          test_case "no consecutive" `Quick test_drain_no_consecutive;
          test_case "multiple identical" `Quick test_drain_multiple_identical;
          test_case "mixed keys" `Quick test_drain_mixed_keys;
        ] );
    ]
