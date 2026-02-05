(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

(* Demo launcher using the Web driver (xterm.js over WebSocket) *)

let gallery_controller_html = [%blob "static/index.html"]

let gallery_viewer_html = [%blob "static/viewer.html"]

let logo_png = [%blob "../miaou_logo_small.png"]

let () =
  let port =
    match Sys.getenv_opt "MIAOU_WEB_PORT" with
    | Some s -> ( match int_of_string_opt s with Some p -> p | None -> 8080)
    | None -> 8080
  in
  Printf.eprintf "Starting Miaou gallery on http://127.0.0.1:%d\n%!" port ;
  Eio_posix.run @@ fun env ->
  Eio.Switch.run @@ fun sw ->
  Miaou_helpers.Fiber_runtime.init ~env ~sw ;
  Demo_shared.Demo_config.register_mocks () ;
  Demo_shared.Demo_config.ensure_system_capability () ;
  let launcher_name = Demo_shared.Demo_config.launcher_page_name in
  let page : Miaou.Core.Registry.page =
    (module Gallery.Launcher : Miaou.Core.Tui_page.PAGE_SIG)
  in
  Miaou.Core.Registry.register launcher_name page ;
  let controller_pw = Sys.getenv_opt "MIAOU_WEB_PASSWORD" in
  let viewer_pw =
    match Sys.getenv_opt "MIAOU_WEB_VIEWER_PASSWORD" with
    | Some _ as pw -> pw
    | None -> controller_pw
  in
  let auth =
    match (controller_pw, viewer_pw) with
    | None, None -> None
    | _ ->
        Some
          Miaou_driver_web.Web_driver.
            {controller_password = controller_pw; viewer_password = viewer_pw}
  in
  let extra_assets =
    [
      Miaou_driver_web.Web_driver.
        {path = "/logo.png"; content_type = "image/png"; body = logo_png};
    ]
  in
  ignore
    (Miaou_runner_web.Runner_web.run
       ~port
       ?auth
       ~controller_html:gallery_controller_html
       ~viewer_html:gallery_viewer_html
       ~extra_assets
       page)
