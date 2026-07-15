open Alcotest
module W = Miaou_widgets_display.Widgets
module Palette = Miaou_widgets_display.Palette

let test_ansi_helpers () =
  let s = W.fg 34 "ok" in
  check bool "fg wraps with escape" true (String.length s > String.length "ok") ;
  check
    bool
    "fg contains payload"
    true
    (Miaou_helpers.Helpers.visible_chars_count s = 2) ;
  let b = W.bold "x" in
  check string "bold wraps payload" "\027[1mx\027[0m" b ;
  let d = W.dim "y" in
  check string "dim wraps payload" "\027[2my\027[0m" d ;
  let g = W.green "z" in
  check string "green wraps payload" "\027[32mz\027[0m" g

let test_visible_width_helpers () =
  let ansi = W.fg 34 "hello" in
  let vis = W.visible_chars_count ansi in
  check int "visible count ignores escapes" 5 vis ;
  let idx = W.visible_byte_index_of_pos "hello" 3 in
  check int "byte index matches plain ascii position" 3 idx

let test_pad_visible () =
  let padded = W.pad_visible "ab" 5 in
  check string "pad_visible pads with spaces to width" "ab   " padded ;
  check
    int
    "pad_visible result has requested visible width"
    5
    (W.visible_chars_count padded) ;
  let truncated = W.pad_visible "abcdef" 4 in
  check string "pad_visible truncates and marks ellipsis" "abc…" truncated

let test_wrap_text () =
  let lines = W.wrap_text ~width:5 "hello world" in
  check
    bool
    "wrap_text splits long text into multiple lines"
    true
    (List.length lines >= 2) ;
  List.iter
    (fun line ->
      check
        bool
        "wrap_text respects width bound"
        true
        (W.visible_chars_count line <= 5))
    lines

let test_backend_switch () =
  W.set_backend `Terminal ;
  check bool "get_backend reflects Terminal" true (W.get_backend () = `Terminal) ;
  W.set_backend `Sdl ;
  check bool "get_backend reflects Sdl" true (W.get_backend () = `Sdl) ;
  (* Sdl backend always prefers ascii glyphs regardless of environment. *)
  check string "glyph_up ascii under Sdl" "^" (W.glyph_up ~backend:`Sdl ()) ;
  check string "glyph_down ascii under Sdl" "v" (W.glyph_down ~backend:`Sdl ()) ;
  check
    string
    "glyph_bullet ascii under Sdl"
    "*"
    (W.glyph_bullet ~backend:`Sdl ()) ;
  W.set_backend `Terminal

let test_json_pretty () =
  let raw = {|{"a":1}|} in
  let pretty = W.json_pretty raw in
  check
    bool
    "json_pretty expands compact json"
    true
    (String.length pretty >= String.length raw) ;
  let invalid = "not json" in
  check
    string
    "json_pretty falls back to raw on parse failure"
    invalid
    (W.json_pretty invalid)

let test_hr () =
  let line = W.hr ~width:6 () in
  check int "hr produces requested width" 6 (String.length line) ;
  check
    bool
    "hr default char is dash"
    true
    (String.for_all (fun c -> c = '-') line)

let test_palette_helpers () =
  (* Default palette is the identity transform: purple_gradient_line and
     selection_bg must return the input unchanged, and must not raise even
     without an explicit palette registration. *)
  let line = Palette.purple_gradient_line Palette.Right "line" in
  check string "default palette purple_gradient_line is identity" "line" line ;
  let sel = Palette.selection_bg "sel" in
  check string "default palette selection_bg is identity" "sel" sel ;
  let fg = Palette.fg_primary "primary" in
  check string "default palette fg_primary is identity" "primary" fg

let () =
  run
    "widgets_smoke"
    [
      ( "widgets_smoke",
        [
          test_case "ansi helpers" `Quick test_ansi_helpers;
          test_case "visible width helpers" `Quick test_visible_width_helpers;
          test_case "pad_visible" `Quick test_pad_visible;
          test_case "wrap_text" `Quick test_wrap_text;
          test_case "backend switch" `Quick test_backend_switch;
          test_case "json_pretty" `Quick test_json_pretty;
          test_case "hr" `Quick test_hr;
          test_case "palette helpers" `Quick test_palette_helpers;
        ] );
    ]
