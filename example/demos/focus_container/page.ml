(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

module Inner = struct
  let tutorial_title = "Focus Container"

  let tutorial_markdown = [%blob "README.md"]

  module FC = Miaou_internals.Focus_container
  module W = Miaou_widgets_display.Widgets
  module CB = Miaou_widgets_input.Checkbox_widget
  module BT = Miaou_widgets_input.Button_widget

  (* Inline counter widget for the demo *)
  type counter = {value : int; label : string}

  let counter_ops : counter FC.widget_ops =
    {
      render =
        (fun c ~focus ->
          let marker = if focus then "> " else "  " in
          let text =
            Printf.sprintf "%s%s: %d (Up/Down)" marker c.label c.value
          in
          if focus then W.green (W.bold text) else text);
      handle_key =
        (fun c ~key ->
          match key with
          | "Up" -> ({c with value = c.value + 1}, `Handled)
          | "Down" -> ({c with value = c.value - 1}, `Handled)
          | _ -> (c, `Bubble));
    }

  let checkbox_ops : CB.t FC.widget_ops =
    FC.ops_simple ~render:CB.render ~handle_key:CB.handle_key

  let button_clicks = ref 0

  let button_ops : BT.t FC.widget_ops =
    FC.ops_bool ~render:BT.render ~handle_key:BT.handle_key

  type state = {container : FC.t; next_page : string option}

  type msg = unit

  let init () =
    let container =
      FC.create
        [
          FC.slot "checkbox" checkbox_ops (CB.create ~label:"Enable feature" ());
          FC.slot "counter" counter_ops {value = 0; label = "Counter"};
          FC.slot
            "button"
            button_ops
            (BT.create
               ~label:"Click me"
               ~on_click:(fun () -> incr button_clicks)
               ());
        ]
    in
    {container; next_page = None}

  let update s _ = s

  let view s ~focus:_ ~size:_ =
    let header = W.titleize "Focus Container (Esc returns, t opens tutorial)" in
    let widgets = FC.render_all s.container in
    let focused_info =
      match FC.focused_id s.container with
      | Some id -> W.dim (Printf.sprintf "Focused: %s" id)
      | None -> W.dim "No focus"
    in
    let widget_lines =
      List.map (fun (_id, _focused, rendered) -> rendered) widgets
    in
    let clicks_info =
      W.dim (Printf.sprintf "Button clicks: %d" !button_clicks)
    in
    let controls =
      W.dim
        "Tab: cycle focus  Space/Enter: activate  Up/Down: counter  Esc: return"
    in
    String.concat
      "\n"
      ([header; ""; focused_info; ""]
      @ widget_lines
      @ [""; clicks_info; ""; controls])

  let go_back s =
    {s with next_page = Some Demo_shared.Demo_config.launcher_page_name}

  let handle_key s key_str ~size:_ =
    match key_str with
    | "Esc" | "Escape" -> go_back s
    | _ ->
        let container, _status = FC.handle_key s.container ~key:key_str in
        {s with container}

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
end

include Demo_shared.Demo_page.Make (Inner)
