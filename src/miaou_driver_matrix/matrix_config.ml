(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

type t = {
  fps_cap : int;
  frame_time_ms : float;
  tps_cap : int;
  tick_time_ms : float;
  debug : bool;
  enable_mouse : bool;
}

let time_of_rate rate =
  let rate = max 1 (min 120 rate) in
  1000.0 /. float_of_int rate

let default =
  let fps_cap = 60 in
  let tps_cap = 30 in
  {
    fps_cap;
    frame_time_ms = time_of_rate fps_cap;
    tps_cap;
    tick_time_ms = time_of_rate tps_cap;
    debug = false;
    enable_mouse = true;
  }

let load () =
  let fps_cap =
    match Sys.getenv_opt "MIAOU_MATRIX_FPS" with
    | Some s -> (
        match int_of_string_opt s with
        | Some n when n >= 1 && n <= 120 -> n
        | _ -> 60)
    | None -> 60
  in
  let tps_cap =
    match Sys.getenv_opt "MIAOU_MATRIX_TPS" with
    | Some s -> (
        match int_of_string_opt s with
        | Some n when n >= 1 && n <= 120 -> n
        | _ -> 30)
    | None -> 30
  in
  let debug =
    match Sys.getenv_opt "MIAOU_MATRIX_DEBUG" with
    | Some ("1" | "true" | "TRUE" | "yes" | "YES") -> true
    | _ -> false
  in
  let enable_mouse =
    match Sys.getenv_opt "MIAOU_ENABLE_MOUSE" with
    | Some ("0" | "false" | "FALSE" | "no" | "NO") -> false
    | _ -> true
  in
  {
    fps_cap;
    frame_time_ms = time_of_rate fps_cap;
    tps_cap;
    tick_time_ms = time_of_rate tps_cap;
    debug;
    enable_mouse;
  }

let with_mouse_disabled config = {config with enable_mouse = false}
