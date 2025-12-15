(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)
(* Mock Service_lifecycle implementation for examples and tests. *)

let start ~role:_ ~service:_ = Ok ()

let stop ~role:_ ~service:_ = Ok ()

let status ~role:_ ~service:_ = Ok `Inactive

let restart ~role:_ ~service:_ = Ok ()

let install_unit ~role:_ ~app_bin_dir:_ ~user:_ = Ok ()

let write_dropin_node ~inst:_ ~data_dir:_ ~app_bin_dir:_ = Ok ()

let enable_start ~role:_ ~inst:_ = Ok ()

let enable ~role:_ ~inst:_ = Ok ()

let disable ~role:_ ~inst:_ = Ok ()

let remove_instance_files ~inst:_ ~remove_data:_ = Ok ()

let register () =
  let module SL = Miaou_interfaces.Service_lifecycle in
  SL.register
    (SL.create
       ~start
       ~stop
       ~restart
       ~status
       ~install_unit
       ~write_dropin_node
       ~enable_start
       ~enable
       ~disable
       ~remove_instance_files)
