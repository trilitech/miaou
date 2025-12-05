open Alcotest

module Palette = Miaou_widgets_display.Palette

let test_default_palette () =
  let sample = Palette.purple_gradient "hi" in
  ignore (Palette.fg_primary "fg") ;
  ignore (Palette.bg_primary "bg") ;
  ignore (Palette.selection_bg "sel") ;
  check bool "contains text" true (String.contains sample 'h')

let test_gradient_positions () =
  let colored =
    Palette.purple_gradient_at Palette.DownRight ~total_visible:10 ~start_pos:3
      "x"
  in
  check bool "non-empty" true (colored <> "") ;
  check bool "contains x" true (String.contains colored 'x')
  ;
  let line = Palette.purple_gradient_line Palette.Right "----" in
  check bool "line colored" true (String.length line >= 4)

let suite =
  [
    test_case "default palette available" `Quick test_default_palette;
    test_case "gradient at position" `Quick test_gradient_positions;
  ]

let () = run "palette" [("palette", suite)]
