(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

let _tutorial_markdown = [%blob "README.md"]

module Vtextbox = Miaou_widgets_input.Validated_textbox_widget

type state = {box : int Vtextbox.t; next_page : string option}

type msg = unit

let validate_int s =
  match int_of_string_opt s with
  | Some v when v >= 0 -> Vtextbox.Valid v
  | _ -> Vtextbox.Invalid "Enter a non-negative integer"

let init () =
  let box =
    Vtextbox.create
      ~title:"Instances"
      ~placeholder:(Some "e.g. 3")
      ~validator:validate_int
      ()
  in
  {box; next_page = None}

let update s (_ : msg) = s

let view s ~focus:_ ~size:_ =
  let module W = Miaou_widgets_display.Widgets in
  let header = W.titleize "Validated textbox" in
  let body = Vtextbox.render s.box ~focus:true in
  let status =
    match Vtextbox.validation_result s.box with
    | Vtextbox.Valid v -> W.green (Printf.sprintf "Valid: %d" v)
    | Vtextbox.Invalid msg -> W.red ("Error: " ^ msg)
  in
  String.concat "\n\n" [header; body; status]

let go_back s = {s with next_page = Some Demo_shared.Demo_config.launcher_page_name}

let handle_key s key_str ~size:_ =
  match Miaou.Core.Keys.of_string key_str with
  | Some (Miaou.Core.Keys.Char "Esc") | Some (Miaou.Core.Keys.Char "Escape") ->
      go_back s
  | Some k ->
      let key = Miaou.Core.Keys.to_string k in
      {s with box = Vtextbox.handle_key s.box ~key}
  | None -> s

let move s _ = s
let refresh s = s
let enter s = s
let service_select s _ = s
let service_cycle s _ = s
let handle_modal_key s _ ~size:_ = s
let next_page s = s.next_page
let keymap (_ : state) = []
let handled_keys () = []
let back s = go_back s
let has_modal _ = false
