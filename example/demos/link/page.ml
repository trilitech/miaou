(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

let _tutorial_markdown = [%blob "README.md"]

module Link = Miaou_widgets_navigation.Link_widget

type state = {
  link : Link.t;
  target : Link.target;
  message : string;
  next_page : string option;
}

type msg = unit

let init () =
  let target = Link.Internal "docs" in
  let link =
    Link.create ~label:"Open internal page" ~target ~on_navigate:(fun _ -> ())
  in
  {
    link;
    target;
    message = "Press Enter or Space to activate";
    next_page = None;
  }

let update s (_ : msg) = s

let view s ~focus:_ ~size:_ =
  let module W = Miaou_widgets_display.Widgets in
  let header = W.titleize "Link widget" in
  let body = Link.render s.link ~focus:true in
  String.concat "\n\n" [header; body; W.dim s.message]

let go_back s = {s with next_page = Some Demo_shared.Demo_config.launcher_page_name}

let handle_key s key_str ~size:_ =
  match Miaou.Core.Keys.of_string key_str with
  | Some (Miaou.Core.Keys.Char "Esc") | Some (Miaou.Core.Keys.Char "Escape") ->
      go_back s
  | Some k ->
      let key = Miaou.Core.Keys.to_string k in
      let link, acted = Link.handle_key s.link ~key in
      let message =
        if acted then
          match s.target with
          | Link.Internal id -> Printf.sprintf "Navigated to %s" id
          | Link.External url -> Printf.sprintf "Would open %s" url
        else s.message
      in
      {s with link; message}
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
