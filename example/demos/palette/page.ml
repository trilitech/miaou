(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

let _tutorial_markdown = [%blob "README.md"]

type state = {next_page : string option}

type msg = unit

let init () = {next_page = None}

let update s _ = s

let view _s ~focus:_ ~size:_ =
  let module P = Miaou_widgets_display.Palette in
  let samples =
    [
      ("Primary", P.fg_primary);
      ("Secondary", P.fg_secondary);
      ("Muted", P.fg_muted);
      ("Stealth", P.fg_stealth);
      ("Slate", P.fg_slate);
      ("Steel", P.fg_steel);
      ("Success", P.fg_success);
      ("Error", P.fg_error);
    ]
  in
  let header =
    Miaou_widgets_display.Widgets.titleize "Palette demo (Esc returns)"
  in
  let body =
    List.map
      (fun (name, color_fn) ->
        Printf.sprintf
          "%s %s"
          (color_fn (Printf.sprintf "%10s" name))
          (color_fn "██████████"))
      samples
  in
  String.concat "\n" (header :: "" :: body)

let go_back = {next_page = Some Demo_shared.Demo_config.launcher_page_name}

let handle_key s key_str ~size:_ =
  match Miaou.Core.Keys.of_string key_str with
  | Some (Miaou.Core.Keys.Char "Esc")
  | Some (Miaou.Core.Keys.Char "Escape")
  | Some (Miaou.Core.Keys.Char "q") ->
      go_back
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
let back _ = go_back
let has_modal _ = false
