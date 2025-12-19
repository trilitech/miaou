(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

module Inner = struct
  let tutorial_title = "Key Handling"

  let tutorial_markdown = [%blob "README.md"]

  type state = {message : string; next_page : string option}

  type msg = KeyPressed of string

  let init () = {message = "Press any key..."; next_page = None}

  let update s = function
    | KeyPressed k -> {s with message = Printf.sprintf "Last key: %s" k}

  let view s ~focus:_ ~size:_ =
    s.message ^ "\n\n" ^ "Esc returns to the launcher, t opens tutorial"

  let go_back s =
    {s with next_page = Some Demo_shared.Demo_config.launcher_page_name}

  let handle_key s key_str ~size:_ =
    match Miaou.Core.Keys.of_string key_str with
    | Some (Miaou.Core.Keys.Char "Esc") | Some (Miaou.Core.Keys.Char "Escape")
      ->
        go_back s
    | Some k -> update s (KeyPressed (Miaou.Core.Keys.to_string k))
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

  let has_modal _ = Miaou.Core.Modal_manager.has_active ()
end

include Demo_shared.Demo_page.Make (Inner)
