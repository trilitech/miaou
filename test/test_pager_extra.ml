open Alcotest

module Pager = Miaou_widgets_display.Pager_widget

let test_json_streamer () =
  let st = Pager.json_streamer_create () in
  let lines1 = Pager.json_streamer_feed st "{\"a\":1," in
  let lines2 = Pager.json_streamer_feed st "\"b\":true}" in
  let combined = lines1 @ lines2 in
  check bool "produces colored output" true (List.exists (fun l -> String.contains l 'a') combined)

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
  let p, _ = Pager.handle_key p ~key:"f" in
  let p, consumed = Pager.handle_key p ~key:"Esc" in
  let rendered = Pager.render ~win:3 p ~focus:false in
  check bool "follow toggled" true p.follow ;
  check bool "escape consumed" false consumed ;
  check bool "search applied" true (String.contains rendered 'f')

let suite =
  [
    test_case "json streamer feed" `Quick test_json_streamer;
    test_case "pending flush renders" `Quick test_pending_flush;
    test_case "handle keys" `Quick test_handle_keys;
  ]

let () = run "pager_extra" [("pager_extra", suite)]
