(*****************************************************************************
 *                                                                           *
 * SPDX-License-Identifier: MIT                                              *
 * Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *
 *                                                                           *
 *****************************************************************************)

[@@@warning "-32-34-37-69"]

open Miaou_core

module Placeholder_page : Tui_page.PAGE_SIG = struct
  type state = string

  type msg = unit

  let init () =
    "No page registered.\n\
     Register your own page in Miaou_core.Registry (e.g. \"main\") and run \
     again with --page <name> or MIAOU_RUNNER_PAGE set."

  let update s _ = s

  let view s ~focus:_ ~size:_ = s

  let move s _ = s

  let refresh s = s

  let enter s = s

  let service_select s _ = s

  let service_cycle s _ = s

  let back s = s

  let keymap _ = []

  let handled_keys () = []

  let handle_modal_key s _ ~size:_ = s

  let handle_key s _ ~size:_ = s

  let next_page _ = None

  let has_modal _ = false
end

let find_page name =
  match Registry.find name with
  | Some p -> p
  | None ->
      prerr_endline
        (Printf.sprintf
           "Miaou runner: page \"%s\" not found; falling back to placeholder."
           name) ;
      Registry.register_once
        "miaou.runner.placeholder"
        (module Placeholder_page : Tui_page.PAGE_SIG)
      |> ignore ;
      Registry.find "miaou.runner.placeholder"
      |> Option.value ~default:(module Placeholder_page : Tui_page.PAGE_SIG)

let pick_page ~argv:_ =
  let page = ref None in
  let specs =
    [
      ( "--page",
        Arg.String (fun s -> page := Some s),
        "Name of the registered TUI page to start (default: env or \"main\")" );
    ]
  in
  Arg.parse specs (fun _ -> ()) "Miaou runner options:" ;
  match !page with
  | Some p -> p
  | None -> (
      match Sys.getenv_opt "MIAOU_RUNNER_PAGE" with
      | Some p -> p
      | None -> "main")
