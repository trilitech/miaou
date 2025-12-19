(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

module Bar_chart = Miaou_widgets_display.Bar_chart_widget

module Inner = struct
  let tutorial_title = "Bar Chart"

  let tutorial_markdown = [%blob "README.md"]

  type state = {data : Bar_chart.bar list; next_page : string option}

  type msg = unit

  let initial_data : Bar_chart.bar list =
    [
      ("Monday", 1250.0, None);
      ("Tuesday", 1800.0, None);
      ("Wednesday", 2100.0, Some "32");
      ("Thursday", 1650.0, None);
      ("Friday", 2400.0, Some "32");
      ("Saturday", 1900.0, None);
      ("Sunday", 1100.0, None);
    ]

  let init () = {data = initial_data; next_page = None}

  let update s (_ : msg) = s

  let randomize_data s =
    let new_data =
      List.map
        (fun (label, _, _) -> (label, 800.0 +. Random.float 1800.0, None))
        s.data
    in
    {s with data = new_data}

  let view s ~focus:_ ~size:_ =
    let module W = Miaou_widgets_display.Widgets in
    let header = W.titleize "Bar Chart Demo" in
    let thresholds =
      [{Bar_chart.value = 2000.0; color = "31"}; {value = 1500.0; color = "33"}]
    in
    let chart =
      Bar_chart.create
        ~width:70
        ~height:15
        ~data:s.data
        ~title:"Daily Sales ($)"
        ()
    in
    let chart_output =
      Bar_chart.render chart ~show_values:true ~thresholds ()
    in
    let hint = W.dim "Space to randomize • t for tutorial • Esc to return" in
    String.concat "\n" [header; ""; chart_output; ""; hint]

  let go_back s =
    {s with next_page = Some Demo_shared.Demo_config.launcher_page_name}

  let handle_key s key_str ~size:_ =
    match Miaou.Core.Keys.of_string key_str with
    | Some (Miaou.Core.Keys.Char "Esc") | Some (Miaou.Core.Keys.Char "Escape")
      ->
        go_back s
    | Some (Miaou.Core.Keys.Char " ") -> randomize_data s
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

  let back s = go_back s

  let has_modal _ = false
end

include Demo_shared.Demo_page.Make (Inner)
