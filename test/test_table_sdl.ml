open Alcotest

module Table = Miaou_widgets_display.Table_widget

let test_render_table_sdl () =
  let header = ("Name", "Status", "Value") in
  let rows =
    [
      ("Alpha", "ok", "1");
      ("Beta", "warn", "2");
      ("Gamma", "error", "3");
      ("Delta", "ready", "4");
    ]
  in
  let out =
    Table.render_table_sdl ~cols:(Some 80) ~header ~rows ~cursor:1 ~sel_col:0
      ~opts:Table.default_opts
  in
  let lines = String.split_on_char '\n' out in
  check int "line count" 6 (List.length lines) ;
  check bool "has pointer" true (String.contains out '>') ;
  (* Vertical separators use UTF-8 line glyphs; check the multibyte prefix. *)
  check bool "has separator" true (String.contains out (Char.chr 0xE2))

let () = run "table_sdl" [("table_sdl", [test_case "render" `Quick test_render_table_sdl])]
