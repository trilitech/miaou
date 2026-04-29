(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

type 'a breakpoint = {max_width : int; layout : 'a}

let pick breakpoints ~default ~width =
  let rec walk = function
    | [] -> default
    | bp :: rest -> if width <= bp.max_width then bp.layout else walk rest
  in
  walk breakpoints

let () =
  Miaou_registry.register ~name:"responsive" ~mli:[%blob "responsive.mli"] ()
