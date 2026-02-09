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

  type key_binding = state Tui_page.key_binding_desc

  type pstate = state Navigation.t

  let init () =
    Navigation.make
      "No page registered.\n\
       Register your own page in Miaou_core.Registry (e.g. \"main\") and run \
       again with --page <name> or MIAOU_RUNNER_PAGE set."

  let update ps _ = ps

  let view ps ~focus:_ ~size:_ = ps.Navigation.s

  let move ps _ = ps

  let refresh ps = ps

  let service_select ps _ = ps

  let service_cycle ps _ = ps

  let back ps = ps

  let keymap _ = []

  let handled_keys () = []

  let handle_modal_key ps _ ~size:_ = ps

  let handle_key ps _ ~size:_ = ps

  let on_key ps key ~size =
    let key_str = Keys.to_string key in
    let ps' = handle_key ps key_str ~size in
    (ps', Miaou_interfaces.Key_event.Bubble)

  let on_modal_key ps key ~size =
    let key_str = Keys.to_string key in
    let ps' = handle_modal_key ps key_str ~size in
    (ps', Miaou_interfaces.Key_event.Bubble)

  let key_hints _ = []

  let has_modal _ = false
end

type options = {
  page_name : string;
  cli_output : bool;
  cols : int;
  rows : int;
  ticks : int;
}

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

let parse ~argv:_ =
  let page = ref None in
  let cli_output = ref false in
  let cols = ref 80 in
  let rows = ref 24 in
  let ticks = ref 0 in
  let specs =
    [
      ( "--page",
        Arg.String (fun s -> page := Some s),
        "Name of the registered TUI page to start (default: env or \"main\")" );
      ( "--cli-output",
        Arg.Set cli_output,
        "Render one static frame to stdout and exit" );
      ( "--cols",
        Arg.Int (fun n -> cols := max 10 n),
        "Viewport width for --cli-output (default: 80)" );
      ( "--rows",
        Arg.Int (fun n -> rows := max 4 n),
        "Viewport height for --cli-output (default: 24)" );
      ( "--ticks",
        Arg.Int (fun n -> ticks := max 0 n),
        "Number of refresh ticks before rendering in --cli-output mode" );
    ]
  in
  Arg.parse specs (fun _ -> ()) "Miaou runner options:" ;
  let page_name =
    match !page with
    | Some p -> p
    | None -> (
        match Sys.getenv_opt "MIAOU_RUNNER_PAGE" with
        | Some p -> p
        | None -> "main")
  in
  {
    page_name;
    cli_output = !cli_output;
    cols = !cols;
    rows = !rows;
    ticks = !ticks;
  }

let rec refresh_n refresh ps n =
  if n <= 0 then ps else refresh_n refresh (refresh ps) (n - 1)

let render_cli ?(focus = true) ~rows ~cols ~ticks page =
  let module P = (val page : Tui_page.PAGE_SIG) in
  let ps0 = P.init () in
  let ps = refresh_n P.refresh ps0 ticks in
  P.view ps ~focus ~size:{LTerm_geom.rows; cols}
