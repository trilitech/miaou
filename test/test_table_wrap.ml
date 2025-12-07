open Alcotest
module Table = Miaou_widgets_display.Table_widget

let test_wrap_row () =
  let header = ("Name", "Desc", "Status") in
  let rows = [("Row1", "This is a long description", "ok")] in
  let out =
    Table.render_table_80_with_opts ~wrap:true ~cols:(Some 30) ~header ~rows ~cursor:0
      ~sel_col:0 ~opts:Table.default_opts ()
  in
  check bool "wrapped across lines"
    true
    (String.exists (fun c -> c = '\n') out
    && String.contains out '\n')

let () = run "table_wrap" [("wrap", [test_case "wrap row" `Quick test_wrap_row])]
