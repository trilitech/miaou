(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

open Miaou_core.Tui_page
module Registry = Miaou_core.Registry
module Navigation = Miaou_core.Navigation

type 'r handler = {
  on_quit : unit -> 'r;
  on_back : unit -> 'r;
  on_same_page : unit -> 'r;
  on_new_page :
    'new_s.
    (module PAGE_SIG with type state = 'new_s) -> 'new_s Navigation.t -> 'r;
}

let handle_next_page (type s r) (module P : PAGE_SIG with type state = s)
    (ps : s Navigation.t) (handler : r handler) : r =
  (* Check for pending navigation from modal callbacks *)
  let ps =
    match Miaou_core.Modal_manager.take_pending_navigation () with
    | Some (Navigation.Goto page) -> Navigation.goto page ps
    | Some Navigation.Back -> Navigation.back ps
    | Some Navigation.Quit -> Navigation.quit ps
    | None -> ps
  in
  match Navigation.pending ps with
  | Some Navigation.Quit -> handler.on_quit ()
  | Some (Navigation.Goto name) -> (
      match Registry.find name with
      | Some (module Next : PAGE_SIG) ->
          let ps_to = Next.init () in
          handler.on_new_page (module Next) ps_to
      | None -> handler.on_quit ())
  | Some Navigation.Back -> handler.on_back ()
  | None -> handler.on_same_page ()
