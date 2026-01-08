(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

module FB = Miaou_widgets_layout.File_browser_widget

type state = FB.t

type pstate = state Miaou.Core.Navigation.t

type msg = unit

let init () =
  Miaou.Core.Navigation.make
    (FB.open_centered ~path:"./" ~dirs_only:false ~select_dirs:true ())

let update ps _ = ps

let view ps ~focus ~size =
  FB.render_with_size ps.Miaou.Core.Navigation.s ~focus ~size

let handle_key ps key_str ~size:_ =
  Miaou.Core.Navigation.update
    (fun s ->
      let s' = FB.handle_key s ~key:key_str in
      if key_str = "Enter" then
        match FB.get_selected_entry s' with
        | Some e when (not e.is_dir) || e.name = "." ->
            Miaou.Core.Modal_manager.close_top `Commit ;
            s'
        | _ -> s'
      else s')
    ps

let move ps _ = ps

let refresh ps = ps

let service_select ps _ = ps

let service_cycle ps _ = ps

let handle_modal_key ps _ ~size:_ = ps

let selection_summary (ps : pstate) =
  match FB.get_selection ps.Miaou.Core.Navigation.s with
  | Some path -> path
  | None -> "<none>"

let keymap (_ : pstate) = []

let handled_keys () = []

let back ps = ps

let has_modal _ = false
