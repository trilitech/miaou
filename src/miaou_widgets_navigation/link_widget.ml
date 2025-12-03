(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)
type target = Internal of string | External of string

type t = {label : string; target : target; on_navigate : target -> unit}

let create ~label ~target ~on_navigate = {label; target; on_navigate}

let render t ~focus =
  let open Miaou_widgets_display.Widgets in
  let base = t.label in
  let base = blue base in
  if focus then Miaou_widgets_display.Widgets.bold base else base

let handle_key t ~key =
  match key with
  | "Enter" | " " ->
      t.on_navigate t.target ;
      (t, true)
  | _ -> (t, false)
