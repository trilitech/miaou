(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

module Modal_manager = Miaou_core.Modal_manager
module Navigation = Miaou_core.Navigation

type key = Key of string | Quit

let script keys =
  let remaining = ref keys in
  fun () ->
    match !remaining with
    | hd :: tl ->
        remaining := tl ;
        hd
    | [] -> Quit

let run ~read_key (module Page : Miaou_core.Tui_page.PAGE_SIG) :
    [`Quit | `Back | `SwitchTo of string] =
  let default_size : LTerm_geom.size = {rows = 24; cols = 80} in
  let apply_pending_modal_nav ps =
    match Modal_manager.take_pending_navigation () with
    | Some (Navigation.Goto page) -> Navigation.goto page ps
    | Some Navigation.Back -> Navigation.back ps
    | Some Navigation.Quit -> Navigation.quit ps
    | None -> ps
  in
  let check_nav ps =
    let ps = apply_pending_modal_nav ps in
    match Navigation.pending ps with
    | Some Navigation.Quit -> `Quit
    | Some Navigation.Back -> `Back
    | Some (Navigation.Goto p) -> `SwitchTo p
    | None -> `Continue ps
  in
  let dispatch ps key_str =
    if Modal_manager.has_active () then (
      Modal_manager.handle_key key_str ;
      Page.refresh ps)
    else Page.handle_key ps key_str ~size:default_size
  in
  let rec loop ps =
    match read_key () with
    | Quit -> `Quit
    | Key key_str -> (
        let ps' = dispatch ps key_str in
        match check_nav ps' with
        | `Continue ps'' -> loop ps''
        | (`Quit | `Back | `SwitchTo _) as r -> r)
  in
  Modal_manager.clear () ;
  let ps0 = Page.init () in
  match check_nav ps0 with
  | `Continue ps0' -> loop ps0'
  | (`Quit | `Back | `SwitchTo _) as r -> r
