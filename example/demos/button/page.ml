(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

module Button = Miaou_widgets_input.Button_widget

module Inner = struct
  let tutorial_title = "Button"

  let tutorial_markdown = [%blob "README.md"]

  type state = {button : Button.t; clicks : int; next_page : string option}

  type msg = unit

  let init () =
    let clicks = 0 in
    let button =
      Button.create
        ~label:"Deploy"
        ~on_click:(fun () -> Logs.info (fun m -> m "Clicked"))
        ()
    in
    {button; clicks; next_page = None}

  let update s (_ : msg) = s

  let view s ~focus:_ ~size:_ =
    let module W = Miaou_widgets_display.Widgets in
    let header = W.titleize "Button" in
    let body = Button.render s.button ~focus:true in
    let info =
      W.dim
        (Printf.sprintf "Clicks: %d • t opens tutorial • Esc returns" s.clicks)
    in
    String.concat "\n\n" [header; body; info]

  let go_back s =
    {s with next_page = Some Demo_shared.Demo_config.launcher_page_name}

  let handle_key s key_str ~size:_ =
    let button, fired = Button.handle_key s.button ~key:key_str in
    let clicks = if fired then s.clicks + 1 else s.clicks in
    match Miaou.Core.Keys.of_string key_str with
    | Some (Miaou.Core.Keys.Char "Esc") | Some (Miaou.Core.Keys.Char "Escape")
      ->
        go_back {s with button; clicks}
    | _ -> {s with button; clicks}

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
