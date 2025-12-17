(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

let _tutorial_markdown = [%blob "README.md"]

module Radio = Miaou_widgets_input.Radio_button_widget
module Focus_chain = Miaou_internals.Focus_chain

type state = {
  options : Radio.t list;
  focus : Focus_chain.t;
  next_page : string option;
}

type msg = unit

let init () =
  let options =
    [
      Radio.create ~label:"Mainnet" ~selected:true ();
      Radio.create ~label:"Ghostnet" ();
      Radio.create ~label:"Custom" ();
    ]
  in
  {
    options;
    focus = Focus_chain.create ~total:(List.length options);
    next_page = None;
  }

let update s (_ : msg) = s

let view s ~focus:_ ~size:_ =
  let module W = Miaou_widgets_display.Widgets in
  let items =
    List.mapi
      (fun i r ->
        let prefix = W.dim (Printf.sprintf "%d) " (i + 1)) in
        let focus = Focus_chain.current s.focus = Some i in
        prefix ^ Radio.render r ~focus)
      s.options
  in
  String.concat "\n" (W.titleize "Radio buttons" :: items)

let select idx s =
  let options =
    List.mapi
      (fun i r ->
        if i = idx then Radio.handle_key r ~key:"Enter"
        else Radio.set_selected r false)
      s.options
  in
  {s with options}

let go_back s = {s with next_page = Some Demo_shared.Demo_config.launcher_page_name}

let handle_key s key_str ~size:_ =
  match Miaou.Core.Keys.of_string key_str with
  | Some (Miaou.Core.Keys.Char "Esc") | Some (Miaou.Core.Keys.Char "Escape") ->
      go_back s
  | Some Miaou.Core.Keys.Tab | Some (Miaou.Core.Keys.Char "Tab") ->
      let focus, _ = Focus_chain.handle_key s.focus ~key:"Tab" in
      {s with focus}
  | Some (Miaou.Core.Keys.Char n) -> (
      match int_of_string_opt n with
      | Some d when d >= 1 && d <= List.length s.options -> select (d - 1) s
      | _ -> s)
  | _ -> (
      match Focus_chain.current s.focus with
      | Some idx ->
          let options =
            List.mapi
              (fun i r ->
                if i = idx then Radio.handle_key r ~key:key_str
                else Radio.set_selected r false)
              s.options
          in
          {s with options}
      | None -> s)

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
