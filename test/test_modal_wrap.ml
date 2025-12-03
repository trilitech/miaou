open Alcotest

let test_wrap_simple () =
  let open Miaou_internals.Modal_utils in
  let s = "This is a long line with unicode: π λ 字 and more text" in
  let wrapped = wrap_content_to_width s 20 in
  let lines = String.split_on_char '\n' wrapped in
  List.iter
    (fun l ->
      let v = Miaou_widgets_display.Widgets.visible_chars_count l in
      check bool "width" true (v <= 20))
    lines

let test_wrap_ansi () =
  let open Miaou_internals.Modal_utils in
  let red = "\027[31m" in
  let reset = "\027[0m" in
  let s = red ^ "This is colored text that should wrap correctly" ^ reset in
  let wrapped = wrap_content_to_width s 10 in
  let lines = String.split_on_char '\n' wrapped in
  List.iter
    (fun l ->
      let v = Miaou_widgets_display.Widgets.visible_chars_count l in
      check bool "width" true (v <= 10))
    lines

let test_wrap_prefers_spaces () =
  let open Miaou_internals.Modal_utils in
  let s = "Alpha beta gamma delta" in
  let wrapped = wrap_content_to_width s 11 in
  check string "word wrap" "Alpha beta\ngamma delta" wrapped

let test_wrap_long_word () =
  let open Miaou_internals.Modal_utils in
  let s = "Supercalifragilistic" in
  let wrapped = wrap_content_to_width s 5 in
  let lines = String.split_on_char '\n' wrapped in
  List.iter
    (fun l ->
      let v = Miaou_widgets_display.Widgets.visible_chars_count l in
      check bool "width" true (v <= 5))
    lines ;
  let rejoined = String.concat "" lines in
  check string "content preserved" s rejoined

let () =
  run
    "modal_wrap"
    [
      ( "wrap",
        [
          test_case "simple" `Quick (fun _ -> test_wrap_simple ());
          test_case "ansi" `Quick (fun _ -> test_wrap_ansi ());
          test_case "prefers-spaces" `Quick (fun _ ->
              test_wrap_prefers_spaces ());
          test_case "long-word" `Quick (fun _ -> test_wrap_long_word ());
        ] );
    ]
