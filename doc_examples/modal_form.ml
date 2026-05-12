(******************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(******************************************************************************)

module Prompt = Miaou_core.Prompt

(* docs:start:prompt-results *)
let confirmed_delete outcome = Prompt.confirm_outcome outcome

let submitted_name outcome ~text = Prompt.input_result outcome ~text

let selected_backend outcome ~selected = Prompt.select_result outcome ~selected
(* docs:end:prompt-results *)

let sample_results () =
  ( confirmed_delete `Commit,
    submitted_name `Commit ~text:"mainnet-node",
    selected_backend `Commit ~selected:(Some "matrix") )
