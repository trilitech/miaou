(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

module Inner = struct
  let tutorial_title = "Inline Select"

  let tutorial_markdown = [%blob "README.md"]

  module Sel = Miaou_widgets_input.Select_widget
  module W = Miaou_widgets_display.Widgets

  let items =
    [
      "Espresso";
      "Cappuccino";
      "Latte";
      "Americano";
      "Macchiato";
      "Flat white";
      "Cortado";
    ]

  let make_selector () =
    Sel.open_centered
      ~cursor:0
      ~title:"Pick a coffee"
      ~items
      ~to_string:(fun x -> x)
      ()

  type state = {
    selector : string Sel.t;
    chosen : string option;
    next_page : string option;
  }

  type msg = unit

  let init () = {selector = make_selector (); chosen = None; next_page = None}

  let update s _ = s

  let view s ~focus ~size =
    let header = W.titleize "Inline Select Demo" in
    let hint =
      W.themed_muted
        "Use Up/Down (j/k), Enter to choose, r resets, Esc returns, t for \
         tutorial."
    in
    let selector_view = Sel.render_with_size s.selector ~focus ~size in
    let chosen_line =
      match s.chosen with
      | None -> W.themed_muted "(no choice yet)"
      | Some v ->
          W.themed_text "You chose: " ^ W.themed_emphasis ("\"" ^ v ^ "\"")
    in
    String.concat "\n" [header; hint; ""; selector_view; ""; chosen_line]

  let go_back s =
    {s with next_page = Some Demo_shared.Demo_config.launcher_page_name}

  let handle_key s key_str ~size =
    match key_str with
    | "Esc" | "Escape" -> go_back s
    | "Enter" ->
        let chosen = Sel.get_selection s.selector in
        {s with chosen}
    | "r" | "R" -> {s with selector = make_selector (); chosen = None}
    | _ ->
        let selector = Sel.handle_key_with_size s.selector ~key:key_str ~size in
        {s with selector}

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

include Demo_shared.Demo_page.MakeSimple (Inner)
