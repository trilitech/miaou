let () =
  Eio_main.run @@ fun env ->
  Eio.Switch.run @@ fun sw ->
  Miaou_helpers.Fiber_runtime.init ~env ~sw ;
  let module Cli = Miaou_runner_common.Runner_cli in
  let opts = Cli.parse ~argv:Sys.argv in
  let page = Cli.find_page opts.page_name in
  if opts.cli_output then
    print_endline
      (Cli.render_cli ~rows:opts.rows ~cols:opts.cols ~ticks:opts.ticks page)
  else
    match Miaou_runner_tui.Runner_tui.run page with
    | `Quit | `Back | `SwitchTo _ -> ()
