(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

module Pager = Miaou_widgets_display.Pager_widget
module Direct_page = Miaou.Core.Direct_page
module W = Miaou_widgets_display.Widgets

let tutorial_markdown = [%blob "README.md"]

let content_lines =
  [
    "";
    W.bold "Traditional PAGE_SIG (20+ lines):";
    "";
    W.dim "  module Counter : PAGE_SIG = struct";
    W.dim "    type state = int";
    W.dim "    type msg = unit";
    W.dim "    type pstate = state Navigation.t";
    W.dim "    type key_binding = state Tui_page.key_binding_desc";
    W.dim "    let init () = Navigation.make 0";
    W.dim "    let update ps _ = ps";
    W.dim "    let view ps ~focus:_ ~size:_ = string_of_int ps.s";
    W.dim "    let handle_key ps key ~size:_ = ...";
    W.dim "    let handle_modal_key ps _ ~size:_ = ps";
    W.dim "    let move ps _ = ps";
    W.dim "    let refresh ps = ps";
    W.dim "    let service_select ps _ = ps";
    W.dim "    let service_cycle ps _ = ps";
    W.dim "    let back ps = Navigation.back ps";
    W.dim "    let keymap _ = []";
    W.dim "    let handled_keys () = []";
    W.dim "    let has_modal _ = false";
    W.dim "  end";
    "";
    String.make 60 '-';
    "";
    W.bold "Direct_page needs only 3 functions:";
    "";
    W.green "  module Counter = Direct_page.Make (With_defaults (struct";
    W.green "    type state = int";
    W.green "    let init () = 0";
    W.green "    let view n ~focus:_ ~size:_ = string_of_int n";
    W.green "    let on_key n key ~size:_ = match key with";
    W.green "      | \"Up\" -> n + 1";
    W.green "      | \"q\"  -> Direct_page.quit () ; n";
    W.green "      | _    -> n";
    W.green "  end))";
    "";
    String.make 60 '-';
    "";
    W.bold "Navigation effects";
    "";
    "  Call these from on_key, on_modal_key, or refresh:";
    "";
    W.green "  Direct_page.navigate \"page_name\"";
    W.green "  Direct_page.go_back ()";
    W.green "  Direct_page.quit ()";
    "";
    "  Effects are composable -- call them from helper functions";
    "  without threading return types:";
    "";
    W.green "  let confirm_and_go state =";
    W.green "    if state.confirmed then Direct_page.navigate \"next\" ;";
    W.green "    state";
    "";
    String.make 60 '-';
    "";
    W.bold "Optional overrides";
    "";
    "  Use " ^ W.green "include With_defaults(...)" ^ " then redefine:";
    "";
    "  " ^ W.dim "keymap" ^ "        - Key/help pairs for the help overlay";
    "  " ^ W.dim "refresh"
    ^ "       - Called on each tick for background updates";
    "  " ^ W.dim "has_modal" ^ "     - Whether a modal is currently active";
    "  " ^ W.dim "on_modal_key" ^ "  - Handle keys when a modal is active";
    "";
    String.make 60 '-';
    "";
    W.dim "  Up/Down: Scroll  |  /: Search  |  n/p: Next/prev match";
    W.dim "  t: Tutorial      |  Esc: Back";
  ]

module S = struct
  type t = {pager : Pager.t}
end

include Direct_page.Make (struct
  open S

  include Direct_page.With_defaults (struct
    type state = S.t

    let init () =
      {pager = Pager.open_lines ~title:"Direct Page Demo" content_lines}

    let view s ~focus ~size =
      let win = max 3 (size.LTerm_geom.rows - 2) in
      let cols = size.LTerm_geom.cols in
      Pager.render ~win ~cols s.pager ~focus

    let on_key s key ~size =
      match key with
      | "t" ->
          Demo_shared.Tutorial_modal.show
            ~title:"Direct Page"
            ~markdown:tutorial_markdown
            () ;
          s
      | "Esc" | "Escape" ->
          Direct_page.go_back () ;
          s
      | _ ->
          let win = max 3 (size.LTerm_geom.rows - 2) in
          let pager, _ = Pager.handle_key ~win s.pager ~key in
          {pager}
  end)

  let has_modal (s : S.t) =
    match s.pager.Pager.input_mode with `Search_edit -> true | _ -> false

  let on_modal_key (s : S.t) key ~size =
    let win = max 3 (size.LTerm_geom.rows - 2) in
    let pager, _ = Pager.handle_key ~win s.pager ~key in
    {pager}

  let keymap _ =
    [
      ("Up/Down", "Scroll");
      ("/", "Search");
      ("n/p", "Next/prev match");
      ("t", "Tutorial");
      ("Esc", "Back");
    ]
end)
