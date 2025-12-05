open Alcotest

let test_tokenize () =
  let input = "\027[31mred\027[0m✓" in
  let wrapped = Miaou_internals.Modal_utils.wrap_content_to_width input 20 in
  check string "round trips" input wrapped

let test_wrap_line () =
  let input = "abcd efgh" in
  let wrapped = Miaou_internals.Modal_utils.wrap_content_to_width input 5 in
  check string "wraps at 5" "abcd\nefgh" wrapped

let test_wrap_words () =
  let input = "hello wide_world" in
  let wrapped = Miaou_internals.Modal_utils.wrap_content_to_width_words input 6 in
  check bool "word wrap keeps tokens" true (String.contains wrapped 'h' && String.contains wrapped 'w')

let test_markdown () =
  let md = "# Title\n- item\n`code`\n[link](http://example.com)" in
  let ansi = Miaou_internals.Modal_utils.markdown_to_ansi md in
  let centered = Miaou_internals.Modal_utils.center_content_to_width ansi 20 in
  check bool "markdown keeps text" true (String.contains centered 'T')

let suite =
  [
    test_case "tokenize ansi/utf8" `Quick test_tokenize;
    test_case "wrap line" `Quick test_wrap_line;
    test_case "wrap words" `Quick test_wrap_words;
    test_case "markdown to ansi and center" `Quick test_markdown;
  ]

let () = run "modal_utils" [("modal_utils", suite)]
