let () =
  let open Miaou_widgets_display.Pager_widget in
  let pager = open_lines ?title:(Some "/test/path") [] in
  set_notify_render (Some (fun () -> print_endline "NOTIFY_RENDER_CALLED")) ;
  start_streaming pager ;
  append_lines_batched pager ["{\"a\": 1"; "}"] ;
  let out = render ~win:5 pager ~focus:true in
  Printf.printf "Render output:\n%s\n" out ;
  stop_streaming pager ;
  flush_pending_if_needed ~force:true pager ;
  let out2 = render ~win:5 pager ~focus:true in
  Printf.printf "After stop render output:\n%s\n" out2
