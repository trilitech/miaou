open Alcotest
module Pager = Miaou_widgets_display.Pager_widget

let test_notify_render_count () =
  let count = ref 0 in
  let notify_render = Some (fun () -> incr count) in
  let pager = Pager.open_lines ?title:(Some "/test/path") ?notify_render [] in
  Pager.start_streaming pager ;
  (* Each batched append wakes up the renderer exactly once, regardless of
     how many lines it carries, so background producers don't spam the UI
     thread with redundant wake-ups. *)
  Pager.append_lines_batched pager ["{\"a\": 1"; "}"] ;
  check int "one notify_render call per append_lines_batched" 1 !count ;
  Pager.append_lines_batched pager ["more"] ;
  check int "a second batched append notifies again" 2 !count ;
  Pager.flush_pending_if_needed ~force:true pager ;
  check
    int
    "an explicit flush with no pending notifier hook does not notify"
    2
    !count

let test_render_contains_streamed_content () =
  let pager = Pager.open_lines ~title:"stream" [] in
  Pager.start_streaming pager ;
  Pager.append_lines_batched pager ["line one"; "line two"] ;
  Pager.flush_pending_if_needed ~force:true pager ;
  let out = Pager.render ~win:5 pager ~focus:true in
  check
    bool
    "render includes first streamed line"
    true
    (Test_helpers.contains_substring out "line one") ;
  check
    bool
    "render includes second streamed line"
    true
    (Test_helpers.contains_substring out "line two")

let test_stop_streaming_flushes_and_freezes () =
  let pager = Pager.open_lines ~title:"stream" [] in
  Pager.start_streaming pager ;
  Pager.append_lines_batched pager ["before stop"] ;
  Pager.stop_streaming pager ;
  let out = Pager.render ~win:5 pager ~focus:true in
  check
    bool
    "stop_streaming flushes pending lines"
    true
    (Test_helpers.contains_substring out "before stop") ;
  (* After stop_streaming, further batched appends are no longer part of
     the "streaming" lifecycle; the pager stops animating its spinner. *)
  Pager.append_lines_batched pager ["after stop"] ;
  Pager.flush_pending_if_needed ~force:true pager ;
  let out2 = Pager.render ~win:5 pager ~focus:true in
  check
    bool
    "content appended after stop is still eventually rendered"
    true
    (Test_helpers.contains_substring out2 "after stop")

let () =
  run
    "pager_streaming"
    [
      ( "pager_streaming",
        [
          test_case "notify_render count" `Quick test_notify_render_count;
          test_case
            "render contains streamed content"
            `Quick
            test_render_contains_streamed_content;
          test_case
            "stop_streaming flushes and freezes"
            `Quick
            test_stop_streaming_flushes_and_freezes;
        ] );
    ]
