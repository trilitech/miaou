(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

module FB = Miaou_widgets_layout.File_browser_widget

type state = FB.t

type msg = unit

let init () = FB.open_centered ~path:"./" ~dirs_only:false ~select_dirs:true ()

let update s _ = s

let view s ~focus ~size = FB.render_with_size s ~focus ~size

let handle_key s key_str ~size:_ =
  let s' = FB.handle_key s ~key:key_str in
  if key_str = "Enter" then
    match FB.get_selected_entry s' with
    | Some e when (not e.is_dir) || e.name = "." ->
        Miaou.Core.Modal_manager.close_top `Commit ;
        s'
    | _ -> s'
  else s'

let move s _ = s

let refresh s = s

let enter s = s

let service_select s _ = s

let service_cycle s _ = s

let handle_modal_key s _ ~size:_ = s

let selection_summary (s : state) =
  match FB.get_selection s with Some path -> path | None -> "<none>"

let next_page _ = None

let keymap (_ : state) = []

let handled_keys () = []

let back s = s

let has_modal _ = false
