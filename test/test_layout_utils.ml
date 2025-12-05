open Alcotest

module List_nav = Miaou_widgets_layout.List_nav
module Pane_layout = Miaou_widgets_layout.Pane_layout

let test_list_nav () =
  check int "move down" 2 (List_nav.move_cursor ~total:5 ~cursor:1 ~delta:1) ;
  check int "clamp upper" 4 (List_nav.move_cursor ~total:5 ~cursor:4 ~delta:5) ;
  check int "page up" 1 (List_nav.page_move ~total:10 ~cursor:5 ~page_size:4 ~dir:`Up)

let test_pane_layout () =
  let layout =
    Pane_layout.create ~left:"left" ~right:"right-side" ~left_ratio:0.5 ()
  in
  let rendered = Pane_layout.render layout 12 in
  let lines = String.split_on_char '\n' rendered in
  List.iter
    (fun l ->
      let w = Miaou_helpers.Helpers.visible_chars_count l in
      check int "line width" 12 w)
    lines ;
  check bool "contains left text" true (String.contains rendered 'l') ;
  check bool "contains right text" true (String.exists (( = ) 'r') rendered)

let suite =
  [
    test_case "list navigation helpers" `Quick test_list_nav;
    test_case "pane layout rendering" `Quick test_pane_layout;
  ]

let () = run "layout_utils" [("layout_utils", suite)]
