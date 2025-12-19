(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

let () =
  Eio_main.run @@ fun env ->
  Eio.Switch.run @@ fun sw ->
  Miaou_helpers.Fiber_runtime.init ~env ~sw ;
  Demo_shared.Demo_config.register_mocks () ;
  Demo_shared.Demo_config.ensure_system_capability () ;
  let launcher_name = Demo_shared.Demo_config.launcher_page_name in
  let page : Miaou.Core.Registry.page =
    (module Gallery.Launcher : Miaou.Core.Tui_page.PAGE_SIG)
  in
  Miaou.Core.Registry.register launcher_name page ;
  ignore (Miaou_runner_native.Runner_native.run page)
