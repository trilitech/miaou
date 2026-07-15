open Alcotest
module Mouse = Miaou_helpers.Mouse

let mouse_event_testable =
  let pp fmt (ev : Mouse.mouse_event) =
    Format.fprintf fmt "{row=%d; col=%d}" ev.row ev.col
  in
  let equal (a : Mouse.mouse_event) (b : Mouse.mouse_event) =
    a.row = b.row && a.col = b.col
  in
  Alcotest.testable pp equal

let test_parse_click_valid_forms () =
  check
    (option mouse_event_testable)
    "Mouse:row:col"
    (Some {Mouse.row = 5; col = 10})
    (Mouse.parse_click "Mouse:5:10") ;
  check
    (option mouse_event_testable)
    "DoubleClick:row:col"
    (Some {Mouse.row = 3; col = 7})
    (Mouse.parse_click "DoubleClick:3:7") ;
  check
    (option mouse_event_testable)
    "TripleClick:row:col"
    (Some {Mouse.row = 1; col = 1})
    (Mouse.parse_click "TripleClick:1:1") ;
  check
    (option mouse_event_testable)
    "MouseDrag:row:col"
    (Some {Mouse.row = 20; col = 40})
    (Mouse.parse_click "MouseDrag:20:40")

let test_parse_click_rejects_malformed () =
  let malformed =
    [
      "Mouse:";
      (* nothing after the prefix *)
      "Mouse:5";
      (* missing column *)
      "Mouse:5:10:extra";
      (* too many components *)
      "Mouse:a:b";
      (* non-numeric *)
      "Mouse::10";
      (* empty row *)
      "Mouse:5:";
      (* empty col *)
      "";
      (* empty string *)
      "WheelUp";
      (* not a click event at all *)
      "mouse:5:10";
      (* wrong case, prefix must match exactly *)
    ]
  in
  List.iter
    (fun key ->
      check
        (option mouse_event_testable)
        (Printf.sprintf "rejects %S" key)
        None
        (Mouse.parse_click key))
    malformed

let test_parse_click_accepts_negative_coordinates () =
  (* Negative coordinates are unusual but syntactically valid integers;
     parsing must not reject them (callers are responsible for range
     validation against the actual terminal size). *)
  check
    (option mouse_event_testable)
    "negative coordinates parse"
    (Some {Mouse.row = -1; col = -2})
    (Mouse.parse_click "Mouse:-1:-2")

let test_is_click_predicates () =
  check bool "is_click true" true (Mouse.is_click "Mouse:1:2") ;
  check bool "is_click false on bare prefix" false (Mouse.is_click "Mouse:") ;
  check bool "is_click false on unrelated key" false (Mouse.is_click "Enter") ;
  check
    bool
    "is_double_click true"
    true
    (Mouse.is_double_click "DoubleClick:1:2") ;
  check
    bool
    "is_triple_click true"
    true
    (Mouse.is_triple_click "TripleClick:1:2") ;
  check bool "is_drag true" true (Mouse.is_drag "MouseDrag:1:2") ;
  check bool "is_drag false for plain click" false (Mouse.is_drag "Mouse:1:2")

let test_wheel_predicates () =
  check bool "is_wheel_up" true (Mouse.is_wheel_up "WheelUp") ;
  check bool "is_wheel_down" true (Mouse.is_wheel_down "WheelDown") ;
  check bool "is_wheel true for up" true (Mouse.is_wheel "WheelUp") ;
  check bool "is_wheel true for down" true (Mouse.is_wheel "WheelDown") ;
  check bool "is_wheel false for click" false (Mouse.is_wheel "Mouse:1:2") ;
  check
    bool
    "wheel_scroll_lines is a positive default"
    true
    (Mouse.wheel_scroll_lines > 0)

let test_is_mouse_event_covers_all_kinds () =
  List.iter
    (fun key ->
      check
        bool
        (Printf.sprintf "%S is a mouse event" key)
        true
        (Mouse.is_mouse_event key))
    [
      "Mouse:1:2";
      "DoubleClick:1:2";
      "TripleClick:1:2";
      "MouseDrag:1:2";
      "WheelUp";
      "WheelDown";
    ] ;
  check
    bool
    "plain key is not a mouse event"
    false
    (Mouse.is_mouse_event "Enter")

let test_translate_key_click () =
  check
    string
    "translate_key shifts a plain click"
    "Mouse:3:5"
    (Mouse.translate_key ~row_offset:5 ~col_offset:10 "Mouse:8:15")

let test_translate_key_preserves_variant_prefix () =
  check
    string
    "translate_key preserves DoubleClick prefix"
    "DoubleClick:1:2"
    (Mouse.translate_key ~row_offset:1 ~col_offset:1 "DoubleClick:2:3") ;
  check
    string
    "translate_key preserves MouseDrag prefix"
    "MouseDrag:0:0"
    (Mouse.translate_key ~row_offset:5 ~col_offset:5 "MouseDrag:5:5")

let test_translate_key_passthrough_for_non_click () =
  check
    string
    "wheel events pass through unchanged"
    "WheelUp"
    (Mouse.translate_key ~row_offset:3 ~col_offset:3 "WheelUp") ;
  check
    string
    "non-mouse keys pass through unchanged"
    "Enter"
    (Mouse.translate_key ~row_offset:3 ~col_offset:3 "Enter") ;
  check
    string
    "malformed mouse-looking keys pass through unchanged"
    "Mouse:x:y"
    (Mouse.translate_key ~row_offset:3 ~col_offset:3 "Mouse:x:y")

let () =
  run
    "mouse"
    [
      ( "parse_click",
        [
          test_case "valid forms" `Quick test_parse_click_valid_forms;
          test_case
            "rejects malformed input"
            `Quick
            test_parse_click_rejects_malformed;
          test_case
            "accepts negative coordinates"
            `Quick
            test_parse_click_accepts_negative_coordinates;
        ] );
      ( "predicates",
        [
          test_case
            "is_click / is_double_click / is_triple_click / is_drag"
            `Quick
            test_is_click_predicates;
          test_case "wheel predicates" `Quick test_wheel_predicates;
          test_case
            "is_mouse_event covers all kinds"
            `Quick
            test_is_mouse_event_covers_all_kinds;
        ] );
      ( "translate_key",
        [
          test_case "shifts click coordinates" `Quick test_translate_key_click;
          test_case
            "preserves variant prefix"
            `Quick
            test_translate_key_preserves_variant_prefix;
          test_case
            "passthrough for non-click keys"
            `Quick
            test_translate_key_passthrough_for_non_click;
        ] );
    ]
