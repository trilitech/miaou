(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

let run ?(enable_mouse = true) ?(port = 8080) ?auth ?controller_html
    ?viewer_html ?(extra_assets = []) page =
  let term_backend =
    {
      Miaou_runner_common.Tui_driver_common.available =
        Miaou_driver_term.Lambda_term_driver.available;
      run = Miaou_driver_term.Lambda_term_driver.run;
    }
  in
  let sdl_backend =
    {
      Miaou_runner_common.Tui_driver_common.available = false;
      run = (fun _ -> `Quit);
    }
  in
  let matrix_config =
    if enable_mouse then None
    else
      Some
        (Miaou_driver_matrix.Matrix_config.load ()
        |> Miaou_driver_matrix.Matrix_config.with_mouse_disabled)
  in
  let matrix_backend =
    {
      Miaou_runner_common.Tui_driver_common.available =
        Miaou_driver_matrix.Matrix_driver.available;
      run = Miaou_driver_matrix.Matrix_driver.run ~config:matrix_config;
    }
  in
  let web_backend =
    {
      Miaou_runner_common.Tui_driver_common.available =
        Miaou_driver_web.Web_driver.available;
      run =
        Miaou_driver_web.Web_driver.run
          ~port
          ?auth
          ?controller_html
          ?viewer_html
          ~extra_assets;
    }
  in
  Miaou_runner_common.Tui_driver_common.run
    ~term_backend
    ~sdl_backend
    ~matrix_backend
    ~web_backend
    page
