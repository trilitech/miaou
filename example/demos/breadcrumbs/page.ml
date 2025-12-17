(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

let _tutorial_markdown = [%blob "README.md"]

module Breadcrumbs = Miaou_widgets_navigation.Breadcrumbs_widget

type state = {
  trail : Breadcrumbs.t;
  info : string;
  bubbled : int;
  next_page : string option;
}

type msg = unit

let init () =
  let trail =
    Breadcrumbs.make
      [
        Breadcrumbs.crumb ~id:"root" ~label:"Root" ();
        Breadcrumbs.crumb ~id:"cluster" ~label:"Cluster" ();
        Breadcrumbs.crumb
          ~id:"node"
          ~label:"Node-01"
          ~on_enter:(fun () -> ())
          ();
      ]
  in
  {
    trail;
    info = "Use ←/→/Home/End to move, Enter to activate, Esc to return";
    bubbled = 0;
    next_page = None;
  }

let update s (_ : msg) = s

let view s ~focus:_ ~size:_ =
  let module W = Miaou_widgets_display.Widgets in
  let header = W.titleize "Breadcrumbs" in
  let trail = Breadcrumbs.render s.trail ~focus:true in
  let bubble_info =
    W.dim
      (Printf.sprintf "Bubbled keys handled by page: %d (press x)" s.bubbled)
  in
  String.concat "\n\n" [header; trail; W.dim s.info; bubble_info]

let go_back s = {s with next_page = Some Demo_shared.Demo_config.launcher_page_name}

let handle_key s key_str ~size:_ =
  match Miaou.Core.Keys.of_string key_str with
  | Some (Miaou.Core.Keys.Char "Esc") | Some (Miaou.Core.Keys.Char "Escape") ->
      go_back s
  | _ ->
      let trail, handled =
        Breadcrumbs.handle_event ~bubble_unhandled:true s.trail ~key:key_str
      in
      let info =
        match handled with
        | `Handled ->
            let current =
              Breadcrumbs.current trail |> Option.map Breadcrumbs.id
              |> Option.value ~default:"(none)"
            in
            "Selected " ^ current
        | `Bubble when String.equal key_str "x" ->
            Printf.sprintf "Page handled bubbled key: %s" key_str
        | `Bubble -> s.info
      in
      let bubbled =
        match handled with
        | `Bubble when String.equal key_str "x" -> s.bubbled + 1
        | _ -> s.bubbled
      in
      {s with trail; info; bubbled}

let move s delta =
  let dir = if delta < 0 then `Left else `Right in
  {s with trail = Breadcrumbs.move s.trail dir}

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
