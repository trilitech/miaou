(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

module Inner = struct
  let tutorial_title = "Tree Viewer"

  let tutorial_markdown = [%blob "README.md"]

  module Tree = Miaou_widgets_display.Tree_widget

  type state = {tree : Tree.t; next_page : string option}

  type msg = unit

  let sample_json =
    "{\"services\": {\"scheduler\": {\"status\": \"ready\"}, \"worker\": \
     {\"status\": \"syncing\"}}, \"counters\": [1,2,3]}"

  let init () =
    let node = Tree.of_json (Yojson.Safe.from_string sample_json) in
    {tree = Tree.open_root node; next_page = None}

  let update s _ = s

  let view s ~focus:_ ~size:_ =
    let module W = Miaou_widgets_display.Widgets in
    let lines =
      [
        "Tree widget demo (t opens tutorial, Esc returns)";
        "";
        Tree.render s.tree ~focus:false;
      ]
    in
    String.concat "\n" lines

  let go_back s =
    {s with next_page = Some Demo_shared.Demo_config.launcher_page_name}

  let handle_key s key_str ~size:_ =
    match Miaou.Core.Keys.of_string key_str with
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

  let keymap (_ : state) = []

  let handled_keys () = []

  let back s = go_back s

  let has_modal _ = false
end

include Demo_shared.Demo_page.Make (Inner)
