(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

open Miaou_core.Tui_page
module Modal_manager = Miaou_core.Modal_manager

type driver_key = Term_events.driver_key =
  | Quit
  | Refresh
  | Enter
  | NextPage
  | PrevPage
  | Up
  | Down
  | Left
  | Right
  | Other of string

let run_with_key_source ~read_key (module Page : PAGE_SIG) :
    [`Quit | `SwitchTo of string] =
  let default_size = {LTerm_geom.rows = 24; cols = 80} in
  let rec loop st =
    match (read_key () : driver_key) with
    | Quit -> `Quit
    | Refresh -> (
        let st' = Page.service_cycle st 0 in
        match Page.next_page st' with Some p -> `SwitchTo p | None -> loop st')
    | Enter -> (
        if Modal_manager.has_active () then (
          Modal_manager.handle_key "Enter" ;
          let st' = Page.refresh st in
          if Modal_manager.take_consume_next_key () then
            if not (Modal_manager.has_active ()) then
              let st'' = Page.service_cycle st' 0 in
              match Page.next_page st'' with
              | Some p -> `SwitchTo p
              | None -> loop st''
            else loop st'
          else if not (Modal_manager.has_active ()) then
            let st'' = Page.service_cycle st' 0 in
            match Page.next_page st'' with
            | Some p -> `SwitchTo p
            | None -> loop st''
          else loop st')
        else
          match Page.next_page st with
          | Some p -> `SwitchTo p
          | None -> (
              let st' = Page.enter st in
              match Page.next_page st' with
              | Some p -> `SwitchTo p
              | None -> loop st'))
    | Up | Down | Left | Right | NextPage | PrevPage -> loop st
    | Other key -> (
        let st' = Page.handle_key st key ~size:default_size in
        match Page.next_page st' with Some p -> `SwitchTo p | None -> loop st')
  in
  Modal_manager.clear () ;
  let st0 = Page.init () in
  loop st0
