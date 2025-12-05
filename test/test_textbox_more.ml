open Alcotest

module TB = Miaou_widgets_input.Textbox_widget

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

let () = run "textbox_more" [("textbox_more", [test_case "editing" `Quick test_editing])]
