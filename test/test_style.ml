(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

(** Tests for the miaou_style module *)

let test_style_empty () =
  let s = Miaou_style.Style.empty in
  Alcotest.(check (option int))
    "fg is None"
    None
    (match s.fg with Some (Fixed c) -> Some c | _ -> None) ;
  Alcotest.(check (option bool)) "bold is None" None s.bold

let test_style_make () =
  let s = Miaou_style.Style.make ~fg:(Fixed 75) ~bold:true () in
  Alcotest.(check (option int))
    "fg is 75"
    (Some 75)
    (match s.fg with Some (Fixed c) -> Some c | _ -> None) ;
  Alcotest.(check (option bool)) "bold is true" (Some true) s.bold ;
  Alcotest.(check (option bool)) "dim is None" None s.dim

let test_style_patch () =
  let base = Miaou_style.Style.make ~fg:(Fixed 10) ~bold:true () in
  let overlay = Miaou_style.Style.make ~fg:(Fixed 20) () in
  let result = Miaou_style.Style.patch ~base ~overlay in
  Alcotest.(check (option int))
    "fg is 20 (overlay wins)"
    (Some 20)
    (match result.fg with Some (Fixed c) -> Some c | _ -> None) ;
  Alcotest.(check (option bool))
    "bold is true (from base)"
    (Some true)
    result.bold

let test_selector_parse () =
  let sel = Miaou_style.Selector.parse "table:focus" in
  Alcotest.(check bool) "parse succeeds" true (Option.is_some sel) ;
  let sel = Option.get sel in
  Alcotest.(check string)
    "to_string roundtrip"
    "table:focus"
    (Miaou_style.Selector.to_string sel)

let test_selector_parse_complex () =
  let sel = Miaou_style.Selector.parse "flex_layout > :nth-child(even)" in
  Alcotest.(check bool) "parse succeeds" true (Option.is_some sel) ;
  let sel = Option.get sel in
  let s = Miaou_style.Selector.to_string sel in
  Alcotest.(check bool) "contains flex_layout" true (String.length s > 0)

let test_selector_matches () =
  let sel = Miaou_style.Selector.parse_exn "button:focus" in
  let ctx_focused =
    {
      Miaou_style.Selector.empty_context with
      widget_name = "button";
      focused = true;
    }
  in
  let ctx_unfocused =
    {
      Miaou_style.Selector.empty_context with
      widget_name = "button";
      focused = false;
    }
  in
  Alcotest.(check bool)
    "matches focused"
    true
    (Miaou_style.Selector.matches sel ctx_focused) ;
  Alcotest.(check bool)
    "doesn't match unfocused"
    false
    (Miaou_style.Selector.matches sel ctx_unfocused)

let test_theme_default () =
  let theme = Miaou_style.Theme.default in
  Alcotest.(check string) "default name" "default" theme.name ;
  Alcotest.(check bool)
    "primary fg is set"
    true
    (Option.is_some theme.primary.fg)

let test_theme_json_roundtrip () =
  let theme = Miaou_style.Theme.default in
  let json = Miaou_style.Theme.to_yojson theme in
  match Miaou_style.Theme.of_yojson json with
  | Ok theme' -> Alcotest.(check string) "name preserved" theme.name theme'.name
  | Error e -> Alcotest.fail ("Roundtrip failed: " ^ e)

let test_style_context_default () =
  (* Without any handler, should return defaults *)
  let theme = Miaou_style.Style_context.current_theme () in
  Alcotest.(check string) "default theme" "default" theme.name

let test_style_context_with_theme () =
  let custom_theme = {Miaou_style.Theme.default with name = "custom"} in
  Miaou_style.Style_context.with_theme custom_theme (fun () ->
      let theme = Miaou_style.Style_context.current_theme () in
      Alcotest.(check string) "custom theme" "custom" theme.name)

let test_border_chars () =
  let chars = Miaou_style.Border.chars_of_style Miaou_style.Border.Rounded in
  Alcotest.(check string) "rounded top-left" "╭" chars.tl ;
  Alcotest.(check string) "rounded horizontal" "─" chars.h

let () =
  Alcotest.run
    "Style"
    [
      ( "Style",
        [
          Alcotest.test_case "empty" `Quick test_style_empty;
          Alcotest.test_case "make" `Quick test_style_make;
          Alcotest.test_case "patch" `Quick test_style_patch;
        ] );
      ( "Selector",
        [
          Alcotest.test_case "parse simple" `Quick test_selector_parse;
          Alcotest.test_case "parse complex" `Quick test_selector_parse_complex;
          Alcotest.test_case "matches" `Quick test_selector_matches;
        ] );
      ( "Theme",
        [
          Alcotest.test_case "default" `Quick test_theme_default;
          Alcotest.test_case "json roundtrip" `Quick test_theme_json_roundtrip;
        ] );
      ( "Style_context",
        [
          Alcotest.test_case "default" `Quick test_style_context_default;
          Alcotest.test_case "with_theme" `Quick test_style_context_with_theme;
        ] );
      ("Border", [Alcotest.test_case "chars" `Quick test_border_chars]);
    ]
