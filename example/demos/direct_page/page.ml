(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

module Direct_page = Miaou.Core.Direct_page

module Inner = struct
  let tutorial_title = "Direct Page"

  let tutorial_markdown = [%blob "README.md"]

  type state = {count : int; next_page : string option}

  type msg = unit

  let init () = {count = 0; next_page = None}

  let update s (_ : msg) = s

  let go_back s =
    {s with next_page = Some Demo_shared.Demo_config.launcher_page_name}

  let view s ~focus:_ ~size:_ =
    let module W = Miaou_widgets_display.Widgets in
    let header = W.titleize "Direct Page Demo" in
    let sep = String.make 60 '-' in
    let before =
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
        W.dim "    ... (* 5 more identity functions *)";
        W.dim "  end";
      ]
    in
    let after =
      [
        "";
        W.bold "Direct_page (8 lines):";
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
      ]
    in
    let counter =
      [
        "";
        sep;
        "";
        W.bold "Interactive counter:";
        "";
        Printf.sprintf "  Count: %s" (W.bold (string_of_int s.count));
        "";
        W.dim "  Up/Down to change  |  Esc to return  |  t for tutorial";
      ]
    in
    String.concat "\n" (header :: sep :: (before @ after @ counter))

  let handle_key s key_str ~size:_ =
    match Miaou.Core.Keys.of_string key_str with
    | Some Miaou.Core.Keys.Up -> {s with count = s.count + 1}
    | Some Miaou.Core.Keys.Down -> {s with count = s.count - 1}
    | Some (Miaou.Core.Keys.Char "Esc") | Some (Miaou.Core.Keys.Char "Escape")
      ->
        go_back s
    | _ -> s

  let move s _ = s

  let refresh s = s

  let enter s = s

  let service_select s _ = s

  let service_cycle s _ = s

  let handle_modal_key s _ ~size:_ = s

  let next_page s = s.next_page

  let keymap (_ : state) =
    [
      ("Up", Fun.id, "Increment");
      ("Down", Fun.id, "Decrement");
      ("Esc", Fun.id, "Back");
    ]

  let handled_keys () = []

  let back s = go_back s

  let has_modal _ = false
end

include Demo_shared.Demo_page.Make (Inner)
