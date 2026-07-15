(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(* Top-level [miaou] command group. Slice 1 registers only [serve]; future
   slices/commands (if any) would be added to this list without touching
   [Miaou_serve.Serve_cli]'s own scope. *)

let () =
  let group_info = Cmdliner.Cmd.info "miaou" in
  exit
    (Cmdliner.Cmd.eval
       (Cmdliner.Cmd.group group_info [Miaou_serve.Serve_cli.cmd]))
