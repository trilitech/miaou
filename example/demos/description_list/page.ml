(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

module Inner = struct
  let tutorial_title = "Description List"

  let tutorial_markdown = [%blob "README.md"]

  type state = {
    widget : Miaou_widgets_display.Description_list.t;
    next_page : string option;
  }

  type msg = unit

  let init () =
    let items =
      [
        ("Name", "Alice in Wonderland");
        ("Role", "Developer");
        ( "Location",
          "Remote - Available for emergencies across multiple timezones" );
      ]
    in
    let widget =
      Miaou_widgets_display.Description_list.create ~title:"Profile" ~items ()
    in
    {widget; next_page = None}

  let update s _ = s

  let view s ~focus:_ ~size:_ =
    let body =
      Miaou_widgets_display.Description_list.render s.widget ~focus:false
    in
    let footer = "Press t to open tutorial • Esc to return to the launcher" in
    body ^ "\n\n" ^ footer

  let go_back s =
    {s with next_page = Some Demo_shared.Demo_config.launcher_page_name}

  let handle_key s key_str ~size:_ =
    match Miaou.Core.Keys.of_string key_str with
    | Some (Miaou.Core.Keys.Char "Esc")
    | Some (Miaou.Core.Keys.Char "Escape")
    | Some (Miaou.Core.Keys.Char "q") ->
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
