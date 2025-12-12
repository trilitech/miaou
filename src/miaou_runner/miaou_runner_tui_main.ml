let () =
  Eio_main.run @@ fun env ->
  Eio.Switch.run @@ fun sw ->
  Miaou_helpers.Fiber_runtime.init ~env ~sw ;
  let module Cli = Miaou_runner_common.Runner_cli in
  let page_name = Cli.pick_page ~argv:Sys.argv in
  let page = Cli.find_page page_name in
  match Miaou_runner_tui.Runner_tui.run page with `Quit | `SwitchTo _ -> ()
