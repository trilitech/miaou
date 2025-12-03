(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)
type t = {label : string; on_click : unit -> unit}

let create ~label ~on_click = {label; on_click}

let render t ~focus =
  let open Miaou_widgets_display.Widgets in
  let base = "[ " ^ t.label ^ " ]" in
  if focus then bg 24 (fg 15 (bold base)) else base

let handle_key t ~key =
  match key with
  | "Enter" | " " ->
      t.on_click () ;
      (t, true)
  | _ -> (t, false)
