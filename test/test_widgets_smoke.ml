open Alcotest

module W = Miaou_widgets_display.Widgets
module Palette = Miaou_widgets_display.Palette

let test_backends_and_widths () =
  W.set_backend `Terminal ;
  let ansi = W.fg 34 "ok" in
  let vis = W.visible_chars_count ansi in
  check int "visible count" 2 vis ;
  let idx = W.visible_byte_index_of_pos "hello" 3 in
  check int "byte index" 3 idx ;
  W.set_backend `Sdl ;
  let padded = W.pad_right ~len:5 "a" in
  check int "pad len" 5 (W.visible_chars_count padded)

let test_palette_helpers () =
  let line = Palette.purple_gradient_line Palette.Right "line" in
  check bool "line colored" true (String.length line >= 4) ;
  let sel = Palette.selection_bg "sel" in
  check bool "selection" true (String.length sel >= 3)

let () =
  run
    "widgets_smoke"
    [
      ( "widgets_smoke",
        [
          test_case "backends and widths" `Quick test_backends_and_widths;
          test_case "palette helpers" `Quick test_palette_helpers;
        ] );
    ]
