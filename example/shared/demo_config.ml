(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

let launcher_page_name = "miaou.demo.launcher"

let register_mocks () =
  Mock_system.register () ;
  Mock_service_lifecycle.register () ;
  Mock_logger.register () ;
  Mock_palette.register () ;
  if Sys.getenv_opt "MIAOU_DEBUG" = Some "1" then
    Printf.printf "miaou example: registered mocks\n"

let ensure_system_capability () =
  match Miaou_interfaces.System.get () with
  | Some _ -> ()
  | None -> failwith "capability missing: System (demo)"
