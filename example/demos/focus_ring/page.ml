(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

module Inner = struct
  let tutorial_title = "Focus Ring"

  let tutorial_markdown = [%blob "README.md"]

  module FR = Miaou_internals.Focus_ring
  module W = Miaou_widgets_display.Widgets
  module Flex = Miaou_widgets_layout.Flex_layout

  let sidebar_slots = ["search"; "filter"; "tree"]

  let main_slots = ["editor"; "preview"]

  type state = {focus : FR.scope; next_page : string option}

  type msg = unit

  let init () =
    let parent = FR.create ["sidebar"; "main"] in
    let sidebar = FR.create sidebar_slots in
    let main = FR.create main_slots in
    let focus =
      FR.scope ~parent ~children:[("sidebar", sidebar); ("main", main)]
    in
    {focus; next_page = None}

  let update s _ = s

  let render_slot ring slot_id label ~size:_ =
    let focused = FR.is_focused ring slot_id in
    let marker = if focused then "> " else "  " in
    let text = marker ^ label in
    if focused then W.green (W.bold text) else text

  let render_panel ring title slots labels ~size =
    let is_active_panel = List.exists (fun id -> FR.is_focused ring id) slots in
    let header = if is_active_panel then W.bold title else W.dim title in
    let items =
      List.map2 (fun id label -> render_slot ring id label ~size) slots labels
    in
    let hint =
      W.dim (Printf.sprintf "%dx%d" size.LTerm_geom.cols size.LTerm_geom.rows)
    in
    String.concat "\n" ([header; ""] @ items @ [""; hint])

  let view s ~focus:_ ~size =
    let header = W.titleize "Focus Ring (Esc returns, t opens tutorial)" in
    let ring = FR.active s.focus in
    let scope_info =
      match FR.active_child_id s.focus with
      | Some id -> W.green (Printf.sprintf "Scope: %s" id)
      | None -> W.dim "Scope: parent (Enter to drill down)"
    in
    let panel_h = max 8 (size.LTerm_geom.rows - 6) in
    let panel_size = {LTerm_geom.cols = size.LTerm_geom.cols; rows = panel_h} in
    let sidebar_child =
      {
        Flex.render =
          render_panel ring "Sidebar" sidebar_slots ["Search"; "Filter"; "Tree"];
        basis = Flex.Px 25;
        cross = None;
      }
    in
    let main_child =
      {
        Flex.render =
          render_panel ring "Main Panel" main_slots ["Editor"; "Preview"];
        basis = Flex.Fill;
        cross = None;
      }
    in
    let panels =
      Flex.create
        ~direction:Flex.Row
        ~gap:{h = 3; v = 0}
        ~padding:{left = 2; right = 2; top = 0; bottom = 0}
        [sidebar_child; main_child]
    in
    let panel_block = Flex.render panels ~size:panel_size in
    let controls =
      W.dim "Tab: cycle • Enter: enter scope • Esc: exit scope / return"
    in
    String.concat "\n" [header; scope_info; ""; panel_block; ""; controls]

  let go_back s =
    {s with next_page = Some Demo_shared.Demo_config.launcher_page_name}

  let handle_key s key_str ~size:_ =
    let focus, status = FR.handle_scope_key s.focus ~key:key_str in
    match status with
    | `Handled -> {s with focus}
    | `Bubble -> (
        match key_str with "Esc" | "Escape" -> go_back s | _ -> {s with focus})

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
