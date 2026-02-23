open Alcotest
module W = Miaou_widgets_display.Widgets
module Palette_sdl = Miaou_widgets_display.Palette_sdl

let test_ascii_preference () =
  Unix.putenv "MIAOU_TUI_UNICODE_BORDERS" "off" ;
  Unix.putenv "MIAOU_TUI_UNICODE_BORDERS" "on" ;
  let unicode = W.prefer_ascii () in
  Unix.putenv "MIAOU_TUI_UNICODE_BORDERS" "auto" ;
  check bool "prefer unicode false" false unicode ;
  ignore (W.prefer_ascii ())

let test_json_helpers () =
  let raw = "{\"a\":1,\"b\":true}" in
  let pretty = W.json_pretty raw in
  check bool "pretty differs" true (pretty <> raw) ;
  let ansi = W.json_pretty_ansi raw in
  check bool "ansi colored" true (String.length ansi >= String.length raw)

let test_highlight () =
  let line = "hello world" in
  let hl = W.highlight_matches ~is_regex:false ~query:(Some "lo") line in
  check bool "highlight applied" true (String.length hl > String.length line)

let test_palette_sdl () =
  let _ = Palette_sdl.fg_primary "x" in
  let _ = Palette_sdl.selection_bg "y" in
  let _ =
    Palette_sdl.purple_gradient_line Miaou_widgets_display.Palette.Up "z"
  in
  let _ = Palette_sdl.fg_muted "m" in
  check bool "palette sdl ok" true true

let test_palette_adapter () =
  let module P = Miaou_interfaces.Palette in
  let mk tag = fun s -> tag ^ ":" ^ s in
  let previous = P.get () in
  let custom =
    {
      P.fg_primary = mk "fgp";
      fg_secondary = mk "fgs";
      fg_muted = mk "fgm";
      bg_primary = mk "bgp";
      fg_stealth = mk "fgst";
      bg_stealth = mk "bgst";
      fg_slate = mk "fgsl";
      bg_slate = mk "bgsl";
      fg_steel = mk "fgstl";
      bg_steel = mk "bgstl";
      fg_white = mk "fgw";
      bg_white = mk "bgw";
      purple_gradient = mk "grad";
      purple_gradient_at =
        (fun dir ~total_visible ~start_pos s ->
          mk
            "grad_at"
            (Printf.sprintf
               "%d:%d:%s"
               total_visible
               start_pos
               (match dir with Up -> "u" | Right -> "r" | DownRight -> "dr")
            ^ ":" ^ s));
      purple_gradient_line =
        (fun dir s ->
          let dir_s =
            match dir with Up -> "u" | Right -> "r" | DownRight -> "dr"
          in
          mk "grad_line" (dir_s ^ ":" ^ s));
      fg_success = mk "fgsuc";
      fg_error = mk "fger";
      selection_bg = mk "selbg";
      selection_fg = mk "selfg";
      fixed_region_bg = mk "fix";
      header_bg = mk "hdr";
    }
  in
  P.set custom ;
  let module WP = Miaou_widgets_display.Palette in
  check string "fg_primary" "fgp:demo" (WP.fg_primary "demo") ;
  ignore (WP.bg_primary "x") ;
  ignore (WP.fg_secondary "x") ;
  ignore (WP.fg_stealth "x") ;
  ignore (WP.bg_stealth "x") ;
  ignore (WP.fg_slate "x") ;
  ignore (WP.bg_slate "x") ;
  ignore (WP.fg_steel "x") ;
  ignore (WP.bg_steel "x") ;
  ignore (WP.fg_white "x") ;
  ignore (WP.bg_white "x") ;
  ignore (WP.fg_muted "y") ;
  ignore (WP.fg_success "ok") ;
  ignore (WP.fg_error "err") ;
  ignore (WP.purple_gradient "g") ;
  ignore (WP.purple_gradient_at Up ~total_visible:10 ~start_pos:2 "g") ;
  ignore (WP.purple_gradient_line DownRight "line") ;
  ignore (WP.selection_bg "s") ;
  ignore (WP.selection_fg "s") ;
  ignore (WP.fixed_region_bg "f") ;
  ignore (WP.header_bg "h") ;
  Option.iter P.set previous

let test_misc_helpers () =
  let hr = W.hr ~width:5 () in
  check int "hr width" 5 (String.length hr) ;
  ignore (W.glyph_up ()) ;
  ignore (W.glyph_down ()) ;
  ignore (W.glyph_bullet ()) ;
  let idx = W.visible_byte_index_of_pos "\027[31mred\027[0m" 1 in
  check bool "visible index" true (idx > 0) ;
  let hl =
    W.highlight_matches ~is_regex:true ~query:(Some "r.e") "\027[31mred\027[0m"
  in
  check bool "highlight regex" true (String.length hl >= 3)

let test_wrap_and_pad () =
  let wrapped = W.wrap_text ~width:5 "abc defgh ijk" in
  check (list string) "wrap splits" ["abc"; "defgh"; "ijk"] wrapped ;
  let padded = W.pad_visible "hi" 4 in
  check string "pad adds spaces" "hi  " padded ;
  let truncated = W.pad_visible "123456" 4 in
  check string "truncate with ellipsis" "123…" truncated

let test_osc8_hyperlink () =
  let module H = Miaou_helpers.Helpers in
  (* hyperlink wraps display text in OSC 8 sequences *)
  let link = W.hyperlink ~url:"https://example.com" "click" in
  (* Only "click" (5 chars) should be visible *)
  check int "hyperlink visible width" 5 (H.visible_chars_count link) ;
  (* The raw string contains the URL in OSC sequences *)
  check bool "contains url" true (String.length link > 5) ;
  (* Combine with ANSI styling inside *)
  let styled_link = W.hyperlink ~url:"https://x.com" (W.bold "bold") in
  check
    int
    "styled hyperlink visible width"
    4
    (H.visible_chars_count styled_link) ;
  (* visible_byte_index_of_pos should skip OSC sequences *)
  let plain = W.hyperlink ~url:"https://a.b" "abcdef" in
  let idx = H.visible_byte_index_of_pos plain 3 in
  let remaining = String.sub plain idx (String.length plain - idx) in
  (* After skipping 3 visible chars, next visible char should be 'd' *)
  check bool "byte index skips osc" true (String.length remaining > 0) ;
  let remaining_visible = H.visible_chars_count remaining in
  check int "remaining visible" 3 remaining_visible

let test_osc_sequence_skipping () =
  let module H = Miaou_helpers.Helpers in
  (* is_osc_start detects ESC ] *)
  check bool "osc start" true (H.is_osc_start "\027]8;;url\027\\" 0) ;
  check bool "not osc start" false (H.is_osc_start "\027[31m" 0) ;
  (* skip_osc_until_st finds ESC \ *)
  let s = "8;;https://example.com\027\\rest" in
  let j = H.skip_osc_until_st s 0 in
  check string "after st" "rest" (String.sub s j (String.length s - j)) ;
  (* Mixed CSI + OSC sequences *)
  let mixed =
    "\027[31m" ^ "red" ^ "\027[0m" ^ " " ^ W.hyperlink ~url:"https://x" "link"
  in
  check int "mixed csi+osc visible" 8 (H.visible_chars_count mixed)

let () =
  run
    "widgets_helpers"
    [
      ( "widgets_helpers",
        [
          test_case "ascii preference" `Quick test_ascii_preference;
          test_case "json helpers" `Quick test_json_helpers;
          test_case "highlight" `Quick test_highlight;
          test_case "palette sdl" `Quick test_palette_sdl;
          test_case "palette adapter" `Quick test_palette_adapter;
          test_case "misc helpers" `Quick test_misc_helpers;
          test_case "wrap+pad helpers" `Quick test_wrap_and_pad;
          test_case "osc8 hyperlink" `Quick test_osc8_hyperlink;
          test_case "osc sequence skipping" `Quick test_osc_sequence_skipping;
        ] );
    ]
