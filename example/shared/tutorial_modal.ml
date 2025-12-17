(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*---------------------------------------------------------------------------*)
module Pager = Miaou_widgets_display.Pager_widget
module MU = Miaou_internals.Modal_utils
module Modal_manager = Miaou.Core.Modal_manager

let payload : (string * string) option ref = ref None

let set_payload ~title ~markdown = payload := Some (title, markdown)

type layout = {cols : int; max_height : int; base_win : int}

let pager_min_win = 1

let pager_overhead_lines = 6

let layout_from_size size =
  let rows = max 1 size.LTerm_geom.rows in
  let cols = max 40 (size.LTerm_geom.cols - 12) in
  let max_height = max 12 (rows - 6) in
  let base_win = max pager_min_win (max_height - pager_overhead_lines) in
  {cols; max_height; base_win}

let count_lines (s : string) = List.length (String.split_on_char '\n' s)

let rec with_fit layout pager ~focus ~win ~k =
  let rendered = Pager.render ~cols:layout.cols ~win pager ~focus in
  let lines = count_lines rendered in
  if lines <= layout.max_height || win <= pager_min_win then k rendered win
  else
    let overflow = lines - layout.max_height in
    let decrement = max 1 overflow in
    let next_win = max pager_min_win (win - decrement) in
    if next_win = win then k rendered win
    else with_fit layout pager ~focus ~win:next_win ~k

module Page : Miaou.Core.Tui_page.PAGE_SIG = struct
  type state = {pager : Pager.t}

  type msg = unit

  let init () =
    let title, markdown =
      match !payload with
      | Some (title, markdown) ->
          payload := None ;
          (title, markdown)
      | None -> ("Tutorial", "_No tutorial content available._")
    in
    let body = MU.markdown_to_ansi markdown in
    let lines = String.split_on_char '\n' body in
    let pager = Pager.open_lines ~title lines in
    {pager}

  let update s (_ : msg) = s

  let view s ~focus:_ ~size =
    let layout = layout_from_size size in
    with_fit
      layout
      s.pager
      ~focus:true
      ~win:layout.base_win
      ~k:(fun rendered _ -> rendered)

  let handle_key s key_str ~size =
    let layout = layout_from_size size in
    let win =
      with_fit layout s.pager ~focus:true ~win:layout.base_win ~k:(fun _ win ->
          win)
    in
    match key_str with
    | "Esc" | "Escape" | "Enter" ->
        let pager, _ = Pager.handle_key ~win s.pager ~key:"Esc" in
        {pager}
    | _ ->
        let pager, _ = Pager.handle_key ~win s.pager ~key:key_str in
        {pager}

  let move s _ = s

  let refresh s = s

  let enter s = s

  let service_select s _ = s

  let service_cycle s _ = s

  let handle_modal_key s _ ~size:_ = s

  let next_page _ = None

  let keymap (_ : state) = []

  let handled_keys () = []

  let back s = s

  let has_modal _ = false
end

let show ?max_width ~title ~markdown () =
  set_payload ~title ~markdown ;
  (* Use dynamic sizing: 80% of terminal width, clamped between 60 and 140 columns.
     The spec is resolved at render time, so the modal resizes with the terminal. *)
  let max_width_spec : Modal_manager.max_width_spec option =
    match max_width with
    | Some w -> Some (Fixed w)
    | None -> Some (Clamped {ratio = 0.8; min = 60; max = 140})
  in
  let ui : Modal_manager.ui =
    {title; left = Some 4; max_width = max_width_spec; dim_background = true}
  in
  Modal_manager.push_default
    (module Page)
    ~init:(Page.init ())
    ~ui
    ~on_close:(fun _ _ -> ())
