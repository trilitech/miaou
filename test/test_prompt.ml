open Alcotest
module P = Miaou_core.Prompt

let test_confirm_outcome_commit () =
  check bool "commit -> true" true (P.confirm_outcome `Commit)

let test_confirm_outcome_cancel () =
  check bool "cancel -> false" false (P.confirm_outcome `Cancel)

let test_input_result_commit () =
  check
    (option string)
    "commit returns Some text"
    (Some "hello")
    (P.input_result `Commit ~text:"hello")

let test_input_result_cancel () =
  check
    (option string)
    "cancel returns None even with text"
    None
    (P.input_result `Cancel ~text:"hello")

let test_input_result_commit_empty () =
  check
    (option string)
    "commit with empty text still returns Some \"\""
    (Some "")
    (P.input_result `Commit ~text:"")

let test_select_result_commit_some () =
  check
    (option int)
    "commit forwards Some n"
    (Some 7)
    (P.select_result `Commit ~selected:(Some 7))

let test_select_result_commit_none () =
  check
    (option int)
    "commit on empty list returns None"
    None
    (P.select_result `Commit ~selected:None)

let test_select_result_cancel_some () =
  check
    (option int)
    "cancel discards selection"
    None
    (P.select_result `Cancel ~selected:(Some 7))

let () =
  run
    "prompt"
    [
      ( "confirm_outcome",
        [
          test_case "commit" `Quick test_confirm_outcome_commit;
          test_case "cancel" `Quick test_confirm_outcome_cancel;
        ] );
      ( "input_result",
        [
          test_case "commit returns Some text" `Quick test_input_result_commit;
          test_case "cancel returns None" `Quick test_input_result_cancel;
          test_case
            "commit with empty text"
            `Quick
            test_input_result_commit_empty;
        ] );
      ( "select_result",
        [
          test_case "commit Some n" `Quick test_select_result_commit_some;
          test_case
            "commit None (empty list)"
            `Quick
            test_select_result_commit_none;
          test_case "cancel discards" `Quick test_select_result_cancel_some;
        ] );
    ]
