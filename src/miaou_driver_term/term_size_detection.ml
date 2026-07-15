(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                            *)
(******************************************************************************)

(** Size detection for lambda-term driver - wrapper around Terminal_raw.
    Returns LTerm_geom.size for compatibility with existing code. Operates
    on the caller-supplied session handle rather than a module-level handle
    of its own. *)

module Raw = Miaou_driver_common.Terminal_raw

let invalidate_cache t = Raw.invalidate_size_cache t

let detect_size t =
  let rows, cols = Raw.size t in
  {LTerm_geom.rows; cols}
