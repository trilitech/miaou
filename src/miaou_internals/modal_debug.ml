(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

let debug_enabled =
  lazy
    (let get_env var =
       match Miaou_interfaces.System.get () with
       | Some sys -> sys.get_env_var var
       | None -> Sys.getenv_opt var
     in
     match get_env "MIAOU_TUI_DEBUG_MODAL" with
     | Some ("1" | "true" | "TRUE" | "yes" | "YES") -> true
     | _ -> false)

let dprintf fmt =
  if Lazy.force debug_enabled then Printf.eprintf fmt
  else Printf.ifprintf stdout fmt
