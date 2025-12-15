open Alcotest
module File_pager = Miaou_widgets_display.File_pager
module Fiber_runtime = Miaou_helpers.Fiber_runtime

let with_runtime f =
  Eio_main.run @@ fun env ->
  Eio.Switch.run @@ fun sw ->
  Fiber_runtime.init ~env ~sw ;
  Fun.protect ~finally:(fun () -> Fiber_runtime.shutdown ()) f

let test_close_twice_no_ebadf () =
  with_runtime (fun () ->
      let path = Filename.temp_file "miaou_file_pager_double_close" ".log" in
      Fun.protect
        ~finally:(fun () -> try Sys.remove path with _ -> ())
        (fun () ->
          match File_pager.open_file ~follow:true path with
          | Error msg -> fail msg
          | Ok fp -> (
              try
                File_pager.close fp ;
                File_pager.close fp
              with exn -> failf "close raised %s" (Printexc.to_string exn))))

let () =
  run
    "file_pager_double_close"
    [
      ( "double_close",
        [
          test_case
            "closing twice does not raise"
            `Quick
            test_close_twice_no_ebadf;
        ] );
    ]
