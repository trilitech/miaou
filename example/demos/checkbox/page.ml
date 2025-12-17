(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

let tutorial_markdown = [%blob "README.md"]

module Checkbox = Miaou_widgets_input.Checkbox_widget
module Focus_chain = Miaou_internals.Focus_chain

type state = {
  boxes : Checkbox.t list;
  focus : Focus_chain.t;
  next_page : string option;
}

type msg = unit

let init () =
  let boxes =
    [
      Checkbox.create ~label:"Enable metrics" ();
      Checkbox.create ~label:"Enable RPCs" ();
      Checkbox.create ~label:"Enable baking" ~checked_:true ();
    ]
  in
  {
    boxes;
    focus = Focus_chain.create ~total:(List.length boxes);
    next_page = None;
  }

let update s (_ : msg) = s

let view s ~focus:_ ~size:_ =
  let module W = Miaou_widgets_display.Widgets in
  let items =
    List.mapi
      (fun i cb ->
        let prefix = W.dim (Printf.sprintf "%d) " (i + 1)) in
        let focus = Focus_chain.current s.focus = Some i in
        prefix ^ Checkbox.render cb ~focus)
      s.boxes
  in
  let hint =
    W.dim
      "Tab rotates focus \226\128\162 1/2/3 toggle \226\128\162 Space/Enter toggles focused \226\128\162 t \
       opens tutorial \226\128\162 Esc returns"
  in
  String.concat "\n" ((W.titleize "Checkboxes" :: items) @ [hint])

let toggle idx s =
  let boxes =
    List.mapi
      (fun i cb ->
        if i = idx then Checkbox.handle_key cb ~key:"Space" else cb)
      s.boxes
  in
  {s with boxes}

let toggle_focused key s =
  match Focus_chain.current s.focus with
  | Some idx ->
      let boxes =
        List.mapi
          (fun i cb -> if i = idx then Checkbox.handle_key cb ~key else cb)
          s.boxes
      in
      {s with boxes}
  | None -> s

let go_back s = {s with next_page = Some Demo_shared.Demo_config.launcher_page_name}

let show_tutorial () =
  Demo_shared.Tutorial_modal.show ~title:"Checkbox tutorial" ~markdown:tutorial_markdown ()

let handle_key s key_str ~size:_ =
  match Miaou.Core.Keys.of_string key_str with
  | Some (Miaou.Core.Keys.Char "Esc") | Some (Miaou.Core.Keys.Char "Escape") ->
      go_back s
  | Some Miaou.Core.Keys.Tab | Some (Miaou.Core.Keys.Char "Tab") ->
      let focus, _ = Focus_chain.handle_key s.focus ~key:"Tab" in
      {s with focus}
  | Some (Miaou.Core.Keys.Char k) when String.lowercase_ascii k = "t" ->
      show_tutorial () ;
      s
  | Some (Miaou.Core.Keys.Char n) -> (
      match int_of_string_opt n with
      | Some d when d >= 1 && d <= List.length s.boxes -> toggle (d - 1) s
      | _ -> toggle_focused key_str s)
  | _ -> toggle_focused key_str s

let move s _ = s

let refresh s = s

let enter s = toggle_focused "Enter" s

let service_select s _ = s

let service_cycle s _ = s

let handle_modal_key s _ ~size:_ = s

let next_page s = s.next_page

let keymap (_ : state) = []

let handled_keys () = []

let back s = go_back s

let has_modal _ = false
