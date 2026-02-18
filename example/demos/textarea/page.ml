(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

module Inner = struct
  let tutorial_title = "Textarea Widget"

  let tutorial_markdown = [%blob "README.md"]

  module TA = Miaou_widgets_input.Textarea_widget
  module W = Miaou_widgets_display.Widgets

  type state = {textarea : TA.t; next_page : string option}

  type msg = unit

  let init () =
    let textarea =
      TA.open_centered
        ~title:"Enter your message"
        ~width:50
        ~height:8
        ~placeholder:"Type here... (Alt+Enter for newline)"
        ()
    in
    {textarea; next_page = None}

  let update s _ = s

  let view s ~focus:_ ~size =
    let header = W.titleize "Textarea Demo (Esc returns, t opens tutorial)" in
    let cols = size.LTerm_geom.cols in
    let textarea_view = TA.render s.textarea ~focus:true in
    let text = TA.get_text s.textarea in
    let char_count = String.length text in
    let line_count = TA.line_count s.textarea in
    let row, col = TA.cursor_position s.textarea in
    let info =
      W.dim
        (Printf.sprintf
           "Characters: %d | Lines: %d | Cursor: (%d, %d)"
           char_count
           line_count
           (row + 1)
           (col + 1))
    in
    let preview_title = W.fg_secondary "Preview:" in
    let preview =
      if String.length text = 0 then W.dim "(empty)"
      else
        let lines = String.split_on_char '\n' text in
        let preview_lines =
          List.mapi
            (fun i line ->
              let prefix = W.dim (Printf.sprintf "%2d: " (i + 1)) in
              let content =
                if String.length line > cols - 10 then
                  String.sub line 0 (cols - 13) ^ "..."
                else line
              in
              prefix ^ content)
            lines
        in
        String.concat "\n" preview_lines
    in
    let controls =
      W.dim "Alt+Enter: newline | Arrows: move | Esc: back | t: tutorial"
    in
    String.concat
      "\n"
      [
        header;
        "";
        textarea_view;
        "";
        info;
        "";
        preview_title;
        preview;
        "";
        controls;
      ]

  let go_back _s =
    {
      textarea = TA.create ();
      next_page = Some Demo_shared.Demo_config.launcher_page_name;
    }

  let handle_key s key_str ~size:_ =
    match key_str with
    | "Esc" | "Escape" -> go_back s
    | _ ->
        let textarea = TA.handle_key s.textarea ~key:key_str in
        {s with textarea}

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

include Demo_shared.Demo_page.MakeSimple (Inner)
