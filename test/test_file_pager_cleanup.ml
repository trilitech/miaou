open Alcotest
module File_pager = Miaou_widgets_display.File_pager
module Fiber_runtime = Miaou_helpers.Fiber_runtime
module Pager = Miaou_widgets_display.Pager_widget

let with_runtime f =
  Eio_main.run @@ fun env ->
  Eio.Switch.run @@ fun sw ->
  Fiber_runtime.init ~env ~sw ;
  Fun.protect ~finally:(fun () -> Fiber_runtime.shutdown ()) f

let test_tail_cancels_on_page_switch_release () =
  with_runtime (fun () ->
      let tmp = Filename.temp_file "miaou_file_pager" ".log" in
      Fun.protect
        ~finally:(fun () -> try Sys.remove tmp with _ -> ())
        (fun () ->
          let fp_ref = ref None in
          Fiber_runtime.with_page_switch (fun _env _page_sw ->
              match File_pager.open_file ~follow:true tmp with
              | Ok fp -> fp_ref := Some fp
              | Error msg -> Alcotest.fail msg) ;
          match !fp_ref with
          | None -> Alcotest.fail "pager was not opened"
          | Some fp ->
              let pager = File_pager.pager fp in
              check
                bool
                "tail fiber cancelled when page switch closes"
                false
                pager.Pager.streaming))

let () =
  run
    "file_pager_cleanup"
    [
      ( "cleanup",
        [
          test_case
            "tail cancels on page switch release"
            `Quick
            test_tail_cancels_on_page_switch_release;
        ] );
    ]
