open Alcotest
module TA = Miaou_widgets_input.Textarea_widget

let key t k = TA.handle_key t ~key:k

let type_chars t s =
  String.fold_left (fun acc c -> key acc (String.make 1 c)) t s

let test_initial_state () =
  let t = TA.create () in
  check bool "no undo on fresh textarea" false (TA.can_undo t) ;
  check bool "no redo on fresh textarea" false (TA.can_redo t)

let test_undo_reverts_typing () =
  let t = TA.create () in
  let t = type_chars t "hello" in
  check string "typed hello" "hello" (TA.get_text t) ;
  check bool "can undo after typing" true (TA.can_undo t) ;
  let t = key t "C-z" in
  check string "undo coalesces the burst back to empty" "" (TA.get_text t) ;
  check bool "can redo after undo" true (TA.can_redo t)

let test_redo_reapplies () =
  let t = TA.create () in
  let t = type_chars t "abc" in
  let t = key t "C-z" in
  check string "after undo" "" (TA.get_text t) ;
  let t = key t "C-y" in
  check string "redo restores" "abc" (TA.get_text t)

let test_burst_then_other_edit_separate_steps () =
  (* Type "abc", press Alt-Enter (newline), type "def".
     One undo reverts "def", another reverts the newline (back to "abc"). *)
  let t = TA.create () in
  let t = type_chars t "abc" in
  let t = key t "A-Enter" in
  let t = type_chars t "def" in
  check string "two-line content" "abc\ndef" (TA.get_text t) ;
  let t = key t "C-z" in
  check string "first undo strips def" "abc\n" (TA.get_text t) ;
  let t = key t "C-z" in
  check string "second undo strips newline" "abc" (TA.get_text t) ;
  let t = key t "C-z" in
  check string "third undo strips abc burst" "" (TA.get_text t)

let test_backspace_separate_step () =
  let t = TA.create () in
  let t = type_chars t "ab" in
  let t = key t "Backspace" in
  check string "after backspace" "a" (TA.get_text t) ;
  let t = key t "C-z" in
  check string "undo restores backspace" "ab" (TA.get_text t)

let test_new_edit_clears_redo () =
  let t = TA.create () in
  let t = type_chars t "abc" in
  let t = key t "C-z" in
  check bool "redo available after undo" true (TA.can_redo t) ;
  let t = type_chars t "x" in
  check bool "redo cleared after a new edit" false (TA.can_redo t)

let test_undo_no_op_when_empty () =
  let t = TA.create () in
  let t' = TA.undo t in
  check string "undo no-op text unchanged" (TA.get_text t) (TA.get_text t') ;
  check bool "can_undo still false" false (TA.can_undo t')

let () =
  run
    "textarea_undo"
    [
      ( "history",
        [
          test_case "initial state" `Quick test_initial_state;
          test_case "undo reverts typing burst" `Quick test_undo_reverts_typing;
          test_case "redo re-applies undo" `Quick test_redo_reapplies;
          test_case
            "burst + other edit yields separate undo steps"
            `Quick
            test_burst_then_other_edit_separate_steps;
          test_case
            "backspace is its own step"
            `Quick
            test_backspace_separate_step;
          test_case "new edit clears redo" `Quick test_new_edit_clears_redo;
          test_case
            "undo no-op when stack empty"
            `Quick
            test_undo_no_op_when_empty;
        ] );
    ]
