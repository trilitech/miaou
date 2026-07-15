open Alcotest
module TB = Miaou_widgets_input.Textbox_widget

let contains_substring = Test_helpers.contains_substring

let test_editing () =
  let tb = TB.create ~initial:"abc" ~width:10 () in
  let tb = TB.handle_key tb ~key:"Left" in
  let tb = TB.handle_key tb ~key:"Backspace" in
  check bool "delete left" true (String.length (TB.value tb) = 2) ;
  let tb = TB.handle_key tb ~key:"Home" in
  let tb = TB.handle_key tb ~key:"x" in
  check bool "insert" true (String.contains (TB.value tb) 'x') ;
  let tb = TB.handle_key tb ~key:"Delete" in
  check bool "delete forward" true (String.length (TB.value tb) <= 3) ;
  let tb = TB.handle_key tb ~key:"Home" in
  let tb = TB.handle_key tb ~key:"y" in
  check int "cursor advance" 1 (TB.cursor tb) ;
  let tb = TB.handle_key tb ~key:"Esc" in
  check bool "cancelled" true (TB.is_cancelled tb) ;
  let tb = TB.reset_cancelled tb in
  check bool "reset cancel" false (TB.is_cancelled tb) ;
  let tb = TB.set_text_with_cursor tb ~text:"hello" ~cursor:10 in
  check int "clamped cursor" 5 (TB.cursor tb) ;
  let tb = TB.with_width tb 3 in
  check int "width clamp" 4 (TB.width tb)

let test_utf8_editing () =
  let tb = TB.create ~initial:"é界🐱" ~width:20 () in
  let tb = TB.handle_key tb ~key:"Backspace" in
  check string "backspace removes emoji" "é界" (TB.value tb) ;
  let tb = TB.handle_key tb ~key:"Left" in
  let tb = TB.handle_key tb ~key:"Delete" in
  check string "delete removes CJK char" "é" (TB.value tb) ;
  let tb = TB.handle_key tb ~key:"Home" in
  let tb = TB.handle_key tb ~key:"🐱" in
  check string "insert emoji at start" "🐱é" (TB.value tb)

let test_masked_utf8_rendering () =
  let tb = TB.create ~initial:"é界🐱" ~mask:true ~width:20 () in
  let rendered = TB.render tb ~focus:true in
  check
    bool
    "one mask per utf8 character"
    true
    (contains_substring rendered "***_") ;
  check
    bool
    "not one mask per byte"
    false
    (contains_substring rendered "*********_")

let () =
  run
    "textbox_more"
    [
      ( "textbox_more",
        [
          test_case "editing" `Quick test_editing;
          test_case "utf8 editing" `Quick test_utf8_editing;
          test_case "masked utf8 rendering" `Quick test_masked_utf8_rendering;
        ] );
    ]
