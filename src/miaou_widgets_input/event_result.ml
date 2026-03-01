(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(* Copyright (c) 2026 Mathias Bourgoin <mathias.bourgoin@atacama.tech>       *)
(*                                                                           *)
(*****************************************************************************)

type t = [`Handled | `Bubble]

let handled = `Handled

let bubble = `Bubble

let to_bool = function `Handled -> true | `Bubble -> false

[@@@enforce_exempt] (* non-widget module *)
