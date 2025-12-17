(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

let _tutorial_markdown = [%blob "README.md"]

type row = string * string * string

type state = {
  table : row Miaou_widgets_display.Table_widget.Table.t;
  next_page : string option;
}

type msg = Move of int | Enter

let init () =
  let rows : row list =
    [
      ("Alice", "42", "Active");
      ("Bob", "7", "Inactive");
      ("Charlie", "99", "Active");
    ]
  in
  let columns =
    [
      {
        Miaou_widgets_display.Table_widget.Table.header = "Name";
        to_string = (fun (n, _, _) -> n);
      };
      {header = "Score"; to_string = (fun (_, s, _) -> s)};
      {header = "Status"; to_string = (fun (_, _, st) -> st)};
    ]
  in
  {
    table = Miaou_widgets_display.Table_widget.Table.create ~columns ~rows ();
    next_page = None;
  }

let set_table s table = {s with table}

let update s = function
  | Move d ->
      let table =
        Miaou_widgets_display.Table_widget.Table.move_cursor s.table d
      in
      set_table s table
  | Enter -> s

let enter s = s

let view s ~focus:_ ~size:_ =
  let header =
    Miaou_widgets_display.Widgets.dim
      "↑/↓ to move • Enter logs the selection • Esc returns"
  in
  let body =
    Miaou_widgets_display.Table_widget.render_table_80
      ~cols:(Some 80)
      ~header:("Name", "Score", "Status")
      ~rows:s.table.rows
      ~cursor:s.table.cursor
      ~sel_col:0
  in
  header ^ "\n\n" ^ body

let log_selection table =
  match Miaou_widgets_display.Table_widget.Table.get_selected table with
  | None -> Logs.info (fun m -> m "No selection")
  | Some (n, sc, st) ->
      Logs.info (fun m -> m "Selected: %s (%s) - %s" n sc st)

let go_back s = {s with next_page = Some Demo_shared.Demo_config.launcher_page_name}

let handle_key s key_str ~size:_ =
  match Miaou.Core.Keys.of_string key_str with
  | Some Miaou.Core.Keys.Up -> update s (Move (-1))
  | Some Miaou.Core.Keys.Down -> update s (Move 1)
  | Some Miaou.Core.Keys.Enter ->
      log_selection s.table ;
      update s Enter
  | Some (Miaou.Core.Keys.Char "q")
  | Some (Miaou.Core.Keys.Char "Q")
  | Some Miaou.Core.Keys.Backspace
  | Some (Miaou.Core.Keys.Char "Esc")
  | Some (Miaou.Core.Keys.Char "Escape") ->
      go_back s
  | _ -> s

let move s d = update s (Move d)
let refresh s = s
let service_select s _ = s
let service_cycle s _ = s
let handle_modal_key s _ ~size:_ = s
let next_page s = s.next_page
let keymap (_ : state) = []
let handled_keys () = []
let back s = go_back s
let has_modal _ = false
