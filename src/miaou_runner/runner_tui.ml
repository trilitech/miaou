(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(* Copyright (c) 2026 Mathias Bourgoin <mathias.bourgoin@atacama.tech>       *)
(*                                                                           *)
(*****************************************************************************)

let run ?(enable_mouse = true) ?(handle_sigint = true)
    ?(on_frame : (rows:int -> cols:int -> string -> unit) option) page =
  match Sys.getenv_opt "MIAOU_DRIVER" with
  | Some "headless" -> Headless_json_runner.run ?on_frame page
  | _ ->
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
        let base = Miaou_driver_matrix.Matrix_config.load () in
        let config =
          if enable_mouse then base
          else Miaou_driver_matrix.Matrix_config.with_mouse_disabled base
        in
        Some {config with handle_sigint}
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
          Miaou_runner_common.Tui_driver_common.available = false;
          run = (fun _ -> `Quit);
        }
      in
      Miaou_runner_common.Tui_driver_common.run
        ~term_backend
        ~sdl_backend
        ~matrix_backend
        ~web_backend
        page
