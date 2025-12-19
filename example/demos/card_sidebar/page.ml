(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

module Card = Miaou_widgets_layout.Card_widget
module Sidebar = Miaou_widgets_layout.Sidebar_widget

module Inner = struct
  let tutorial_title = "Card & Sidebar"

  let tutorial_markdown = [%blob "README.md"]

  type state = {next_page : string option; sidebar_open : bool}

  type msg = unit

  let init () = {next_page = None; sidebar_open = true}

  let update s _ = s

  let view s ~focus:_ ~size =
    let module W = Miaou_widgets_display.Widgets in
    let cols = max 50 size.LTerm_geom.cols in
    let card =
      Card.create
        ~title:"Card title"
        ~footer:"Footer"
        ~accent:81
        ~body:"Body text"
        ()
      |> fun c -> Card.render c ~cols
    in
    let sidebar =
      Sidebar.create
        ~sidebar:"Navigation\n- Item 1\n- Item 2"
        ~main:"Main content\nThis is the main panel."
        ~sidebar_open:s.sidebar_open
        ()
      |> fun layout -> Sidebar.render layout ~cols
    in
    let hint =
      if s.sidebar_open then "Tab: collapse sidebar" else "Tab: expand sidebar"
    in
    let hint =
      W.dim (Printf.sprintf "%s • t opens tutorial • Esc returns" hint)
    in
    String.concat "\n\n" ["Card & Sidebar demo"; card; sidebar; hint]

  let go_back s =
    {s with next_page = Some Demo_shared.Demo_config.launcher_page_name}

  let handle_key s key_str ~size:_ =
    match Miaou.Core.Keys.of_string key_str with
    | Some (Miaou.Core.Keys.Char "Esc") | Some (Miaou.Core.Keys.Char "Escape")
      ->
        go_back s
    | Some Miaou.Core.Keys.Tab
    | Some (Miaou.Core.Keys.Char "Tab")
    | Some (Miaou.Core.Keys.Char "NextPage") ->
        {s with sidebar_open = not s.sidebar_open}
    | _ -> s

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
end

include Demo_shared.Demo_page.Make (Inner)
