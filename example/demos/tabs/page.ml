(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

module Inner = struct
  let tutorial_title = "Tabs Navigation"

  let tutorial_markdown = [%blob "README.md"]

  module Tabs = Miaou_widgets_navigation.Tabs_widget

  type state = {tabs : Tabs.t; note : string; next_page : string option}

  type msg = unit

  let init () =
    let tabs =
      Tabs.make
        [
          Tabs.tab ~id:"dashboard" ~label:"Dashboard";
          Tabs.tab ~id:"logs" ~label:"Logs";
          Tabs.tab ~id:"settings" ~label:"Settings";
        ]
    in
    {
      tabs;
      note =
        "Use ←/→/Home/End, Enter to confirm, Esc to return, t opens tutorial";
      next_page = None;
    }

  let update s (_ : msg) = s

  let view s ~focus:_ ~size:_ =
    let module W = Miaou_widgets_display.Widgets in
    let current_label =
      match Tabs.current s.tabs with
      | None -> W.dim "(no tabs)"
      | Some t -> Printf.sprintf "Selected: %s" (Tabs.label t)
    in
    let header = W.titleize "Tabs navigation" in
    let rendered = Tabs.render s.tabs ~focus:true in
    String.concat "\n\n" [header; rendered; W.dim s.note; current_label]

  let go_back s =
    {s with next_page = Some Demo_shared.Demo_config.launcher_page_name}

  let handle_key s key_str ~size:_ =
    match Miaou.Core.Keys.of_string key_str with
    | Some (Miaou.Core.Keys.Char "Esc") | Some (Miaou.Core.Keys.Char "Escape")
      ->
        go_back s
    | Some Miaou.Core.Keys.Enter ->
        let msg =
          match Tabs.current s.tabs with
          | None -> "No selection"
          | Some t -> Printf.sprintf "Confirmed %s" (Tabs.label t)
        in
        {s with note = msg}
    | _ ->
        let tabs = Tabs.handle_key s.tabs ~key:key_str in
        {s with tabs}

  let move s delta =
    let dir = if delta < 0 then `Left else `Right in
    {s with tabs = Tabs.move s.tabs dir}

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
end

include Demo_shared.Demo_page.Make (Inner)
