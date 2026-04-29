open Alcotest
module K = Miaou_core.Keymap_config

let parse_ok text =
  match K.parse text with
  | Ok t -> t
  | Error msg -> Alcotest.failf "expected Ok, got Error %s" msg

let test_parse_basic () =
  let t =
    parse_ok
      "page=files     key=ctrl+r   action=reload\n\
       page=*         key=ctrl+q   action=quit\n"
  in
  check int "two rules" 2 (K.rule_count t) ;
  check
    (option string)
    "files reload"
    (Some "reload")
    (K.find t ~page:"files" ~key:"C-r") ;
  check
    (option string)
    "quit globally"
    (Some "quit")
    (K.find t ~page:"editor" ~key:"C-q")

let test_parse_blank_and_comment () =
  let t =
    parse_ok
      "# top comment\n\n  # indented comment\npage=*  key=q  action=quit\n\n"
  in
  check int "one rule" 1 (K.rule_count t) ;
  check (option string) "quit" (Some "quit") (K.find t ~page:"any" ~key:"q")

let test_parse_error_includes_lineno () =
  match K.parse "page=*  key=ctrl+q  action=quit\nbogus line here\n" with
  | Ok _ -> Alcotest.fail "expected error on line 2"
  | Error msg ->
      check
        bool
        "error mentions line 2"
        true
        (Astring.String.is_infix ~affix:"line 2" msg)

let test_parse_empty_action () =
  match K.parse "page=*  key=q  action=\n" with
  | Ok _ -> Alcotest.fail "expected error for empty action"
  | Error _ -> ()

let test_parse_empty_input () =
  let t = parse_ok "" in
  check bool "empty" true (K.is_empty t)

let test_normalize_ctrl_variants () =
  (* All three forms should produce the same canonical key. *)
  let mk k =
    parse_ok (Printf.sprintf "page=*  key=%s  action=quit" k) |> fun t ->
    K.find t ~page:"x" ~key:"C-q"
  in
  check (option string) "ctrl+q" (Some "quit") (mk "ctrl+q") ;
  check (option string) "Ctrl-Q" (Some "quit") (mk "Ctrl-Q") ;
  check (option string) "c-q" (Some "quit") (mk "c-q") ;
  check (option string) "C-q" (Some "quit") (mk "C-q")

let test_normalize_shift_tab () =
  let t = parse_ok "page=*  key=shift+tab  action=back" in
  check
    (option string)
    "Shift-Tab"
    (Some "back")
    (K.find t ~page:"x" ~key:"Shift-Tab")

let test_normalize_named_keys () =
  let t =
    parse_ok
      "page=*  key=enter  action=accept\npage=*  key=ESCAPE  action=cancel"
  in
  check
    (option string)
    "Enter"
    (Some "accept")
    (K.find t ~page:"x" ~key:"Enter") ;
  check
    (option string)
    "Escape"
    (Some "cancel")
    (K.find t ~page:"x" ~key:"Escape")

let test_find_page_specific_wins () =
  let t =
    parse_ok
      "page=files  key=ctrl+r  action=reload-files\n\
       page=*      key=ctrl+r  action=reload-global"
  in
  check
    (option string)
    "files-specific"
    (Some "reload-files")
    (K.find t ~page:"files" ~key:"C-r") ;
  check
    (option string)
    "global fallback"
    (Some "reload-global")
    (K.find t ~page:"editor" ~key:"C-r")

let test_find_page_specific_wins_when_global_is_first () =
  let t =
    parse_ok
      "page=*      key=ctrl+r  action=reload-global\n\
       page=files  key=ctrl+r  action=reload-files"
  in
  check
    (option string)
    "page-specific still wins"
    (Some "reload-files")
    (K.find t ~page:"files" ~key:"C-r") ;
  check
    (option string)
    "global remains fallback"
    (Some "reload-global")
    (K.find t ~page:"editor" ~key:"C-r")

let test_find_miss () =
  let t = parse_ok "page=*  key=q  action=quit" in
  check (option string) "no match" None (K.find t ~page:"x" ~key:"z")

let test_load_missing_file () =
  match K.load ~path:"/nonexistent/path/keymap.conf" () with
  | Ok t -> check bool "empty for missing file" true (K.is_empty t)
  | Error msg -> Alcotest.failf "expected Ok empty, got Error %s" msg

let test_load_parse_error_propagates () =
  let path = Filename.temp_file "miaou_keymap" ".conf" in
  let oc = open_out path in
  output_string oc "this line is broken\n" ;
  close_out oc ;
  let r = K.load ~path () in
  Sys.remove path ;
  match r with Ok _ -> Alcotest.fail "expected parse error" | Error _ -> ()

let test_rules_round_trip () =
  let t =
    parse_ok
      "page=files  key=ctrl+r  action=reload\n\
       page=*      key=ctrl+q  action=quit"
  in
  let rs = K.rules t in
  check int "two rules listed" 2 (List.length rs) ;
  let pp_first, k1, a1 = List.hd rs in
  check (option string) "page=files" (Some "files") pp_first ;
  check string "C-r" "C-r" k1 ;
  check string "reload" "reload" a1 ;
  let pp_snd, k2, a2 = List.nth rs 1 in
  check (option string) "page=* -> None" None pp_snd ;
  check string "C-q" "C-q" k2 ;
  check string "quit" "quit" a2

let () =
  run
    "keymap_config"
    [
      ( "parse",
        [
          test_case "basic" `Quick test_parse_basic;
          test_case
            "blank lines and comments"
            `Quick
            test_parse_blank_and_comment;
          test_case
            "error includes line number"
            `Quick
            test_parse_error_includes_lineno;
          test_case "empty action rejected" `Quick test_parse_empty_action;
          test_case "empty input -> empty" `Quick test_parse_empty_input;
        ] );
      ( "normalize",
        [
          test_case "ctrl variants" `Quick test_normalize_ctrl_variants;
          test_case "shift+tab" `Quick test_normalize_shift_tab;
          test_case "named keys" `Quick test_normalize_named_keys;
        ] );
      ( "find",
        [
          test_case
            "page-specific wins over global"
            `Quick
            test_find_page_specific_wins;
          test_case
            "page-specific wins when global appears first"
            `Quick
            test_find_page_specific_wins_when_global_is_first;
          test_case "no match returns None" `Quick test_find_miss;
        ] );
      ( "load",
        [
          test_case "missing file is empty" `Quick test_load_missing_file;
          test_case
            "parse error propagates"
            `Quick
            test_load_parse_error_propagates;
        ] );
      ("rules", [test_case "round trip" `Quick test_rules_round_trip]);
    ]
