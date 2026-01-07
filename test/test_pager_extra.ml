open Alcotest
module Pager = Miaou_widgets_display.Pager_widget

let test_json_streamer () =
  let st = Pager.json_streamer_create () in
  let lines1 = Pager.json_streamer_feed st "{\"a\":1," in
  let lines2 = Pager.json_streamer_feed st "\"b\":true}" in
  let combined = lines1 @ lines2 in
  check
    bool
    "produces colored output"
    true
    (List.exists (fun l -> String.contains l 'a') combined)

let test_pending_flush () =
  let p = Pager.open_lines ~title:"t" [] in
  Pager.start_streaming p ;
  Pager.append_lines_batched p ["line1"; "line2"] ;
  Pager.flush_pending_if_needed ~force:true p ;
  Pager.stop_streaming p ;
  let rendered = Pager.render ~win:5 p ~focus:true in
  check bool "rendered lines present" true (String.contains rendered 'l')

let test_handle_keys () =
  let p = Pager.open_lines ~title:"nav" ["a"; "b"; "foo"; "bar"; "baz"] in
  let p, _ = Pager.handle_key p ~key:"Down" in
  let p, _ = Pager.handle_key p ~key:"Page_down" in
  let p, _ = Pager.handle_key p ~key:"g" in
  let p, _ = Pager.handle_key p ~key:"/" in
  p.input_buffer <- "foo" ;
  let p, _ = Pager.handle_key p ~key:"Enter" in
  let p, _ = Pager.handle_key p ~key:"n" in
  let p, _ = Pager.handle_key p ~key:"p" in
  let p, consumed_follow = Pager.handle_key p ~key:"f" in
  let p, consumed = Pager.handle_key p ~key:"Esc" in
  let rendered = Pager.render ~win:3 p ~focus:false in
  check bool "follow unchanged when not streaming" false consumed_follow ;
  check bool "follow remains off when not streaming" false p.follow ;
  check bool "escape consumed" false consumed ;
  check bool "search applied" true (String.contains rendered 'f')

let test_wrap () =
  let p = Pager.open_lines ~title:"wrap" ["0123456789 abcdefghij"] in
  p.wrap <- true ;
  let rendered = Pager.render ~cols:12 ~win:4 p ~focus:false in
  check bool "first chunk present" true (String.contains rendered '0') ;
  check bool "wrapped chunk present" true (String.contains rendered 'a')

let test_search_input_mode () =
  let p = Pager.open_lines ~title:"search" ["foo"; "bar"; "baz"] in
  (* Enter search mode *)
  let p, consumed = Pager.handle_key p ~key:"/" in
  check bool "slash consumed" true consumed ;
  check bool "input mode is search" true (p.input_mode = `Search_edit) ;
  check string "input buffer empty" "" p.input_buffer ;
  (* Type some characters *)
  let p, _ = Pager.handle_key p ~key:"f" in
  let p, _ = Pager.handle_key p ~key:"o" in
  let p, _ = Pager.handle_key p ~key:"o" in
  check string "input buffer has foo" "foo" p.input_buffer ;
  check int "cursor at end" 3 p.input_pos ;
  (* Backspace *)
  let p, _ = Pager.handle_key p ~key:"Backspace" in
  check string "after backspace" "fo" p.input_buffer ;
  check int "cursor moved back" 2 p.input_pos ;
  (* Left arrow *)
  let p, _ = Pager.handle_key p ~key:"Left" in
  check int "cursor moved left" 1 p.input_pos ;
  (* Type 'x' in middle *)
  let p, _ = Pager.handle_key p ~key:"x" in
  check string "inserted x" "fxo" p.input_buffer ;
  check int "cursor after x" 2 p.input_pos ;
  (* Right arrow *)
  let p, _ = Pager.handle_key p ~key:"Right" in
  check int "cursor moved right" 3 p.input_pos ;
  (* Escape to cancel *)
  let p, _ = Pager.handle_key p ~key:"Esc" in
  check bool "exited search mode" true (p.input_mode = `None) ;
  (* Search prompt should be shown in render when in search mode *)
  let p, _ = Pager.handle_key p ~key:"/" in
  let rendered = Pager.render ~win:5 p ~focus:true in
  check bool "search prompt shown" true (String.contains rendered 'S') ;
  let has_search_prompt =
    try
      ignore (Str.search_forward (Str.regexp_string "Search:") rendered 0) ;
      true
    with Not_found -> false
  in
  check bool "search prompt has 'Search:'" true has_search_prompt

let test_search_execute () =
  let win = 3 in
  let p =
    Pager.open_lines ~title:"search" ["apple"; "banana"; "cherry"; "date"]
  in
  (* Enter search mode and type query *)
  let p, _ = Pager.handle_key p ~win ~key:"/" in
  let p, _ = Pager.handle_key p ~win ~key:"a" in
  let p, _ = Pager.handle_key p ~win ~key:"n" in
  (* Execute search with Enter *)
  let p, _ = Pager.handle_key p ~win ~key:"Enter" in
  check bool "search mode exited" true (p.input_mode = `None) ;
  check (option string) "search query set" (Some "an") p.search ;
  (* Next match *)
  let p, _ = Pager.handle_key p ~win ~key:"n" in
  (* Should jump to next line with "an" *)
  check bool "offset changed" true (p.offset > 0)

let test_follow_mode_behavior () =
  let win = 3 in
  let p =
    Pager.open_lines
      ~title:"follow"
      ["line1"; "line2"; "line3"; "line4"; "line5"]
  in
  Pager.start_streaming p ;
  (* Enable follow mode *)
  let p, _ = Pager.handle_key p ~win ~key:"f" in
  check bool "follow enabled" true p.follow ;
  check int "jumped to bottom" (List.length p.lines - win) p.offset ;
  (* Verify render shows [follow] indicator *)
  let rendered = Pager.render ~win:3 p ~focus:true in
  check bool "follow indicator shown" true (String.contains rendered '[') ;
  let has_follow_label =
    try
      ignore (Str.search_forward (Str.regexp_string "[follow]") rendered 0) ;
      true
    with Not_found -> false
  in
  check bool "follow text present" true has_follow_label ;
  (* Scrolling should disable follow *)
  let p, _ = Pager.handle_key p ~win ~key:"Up" in
  check bool "follow disabled after scroll" false p.follow

let test_follow_tracks_appends () =
  let win = 3 in
  let p = Pager.open_lines ~title:"follow" ["l1"; "l2"] in
  Pager.start_streaming p ;
  let p, _ = Pager.handle_key p ~win ~key:"f" in
  check bool "follow enabled" true p.follow ;
  Pager.append_lines_batched p ["l3"] ;
  Pager.flush_pending_if_needed ~force:true p ;
  check int "offset stays at bottom" (List.length p.lines - win) p.offset ;
  let rendered = Pager.render ~win p ~focus:true in
  check bool "latest line visible" true (String.contains rendered '3')

let test_static_pager_hides_follow () =
  let p =
    Pager.open_lines ~title:"static" ["line1"; "line2"; "line3"; "line4"]
  in
  let rendered = Pager.render ~win:4 p ~focus:true in
  let has_follow =
    try
      ignore (Str.search_forward (Str.regexp_string "follow") rendered 0) ;
      true
    with Not_found -> false
  in
  check bool "follow hint absent for static pager" false has_follow ;
  let p', consumed = Pager.handle_key p ~key:"f" in
  check bool "follow key ignored for static pager" false consumed ;
  check bool "follow flag remains off" false p'.Pager.follow

let suite =
  [
    test_case "json streamer feed" `Quick test_json_streamer;
    test_case "pending flush renders" `Quick test_pending_flush;
    test_case "handle keys" `Quick test_handle_keys;
    test_case "wrap pager" `Quick test_wrap;
    test_case "search input mode" `Quick test_search_input_mode;
    test_case "search execute" `Quick test_search_execute;
    test_case "follow mode behavior" `Quick test_follow_mode_behavior;
    test_case "follow tracks appends" `Quick test_follow_tracks_appends;
    test_case "static pager hides follow" `Quick test_static_pager_hides_follow;
  ]

let () = run "pager_extra" [("pager_extra", suite)]
