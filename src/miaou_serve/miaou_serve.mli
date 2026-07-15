(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(** Library entry point — re-exports {!Serve_run} (the [run] function and
    [Bind_refused] exception) plus the library's other public modules.
    See {!Serve_run} for the full entry-contract documentation (binding
    design decisions). *)

include module type of Serve_run

module Serve_token = Serve_token
module Serve_policy = Serve_policy
module Serve_config = Serve_config
module Serve_cli = Serve_cli
