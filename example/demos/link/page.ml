(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

module Inner = struct
  let tutorial_title = "Link"

  let tutorial_markdown = [%blob "README.md"]

  module Link = Miaou_widgets_navigation.Link_widget
  module W = Miaou_widgets_display.Widgets

  type state = {
    link : Link.t;
    target : Link.target;
    message : string;
    next_page : string option;
  }

  type msg = unit

  let init () =
    let target = Link.Internal "docs" in
    let link =
      Link.create ~label:"Open internal page" ~target ~on_navigate:(fun _ -> ())
    in
    {
      link;
      target;
      message = "Press Enter or Space to activate";
      next_page = None;
    }

  let update s (_ : msg) = s

  let view s ~focus:_ ~size:_ =
    let header = W.titleize "Link widget (t opens tutorial)" in
    let body = Link.render s.link ~focus:true in
    (* OSC 8 hyperlink examples *)
    let section_osc8 = W.bold "OSC 8 Terminal Hyperlinks" in
    let osc8_plain =
      "  "
      ^ W.hyperlink
          ~url:"https://github.com/trilitech/miaou"
          "github.com/trilitech/miaou"
    in
    let osc8_styled =
      "  "
      ^ W.hyperlink
          ~url:"https://ocaml.org"
          (W.themed_accent "ocaml.org (themed accent)")
    in
    let osc8_long_url =
      let url =
        "https://ghostnet.tzkt.io/ook5WtHh6MB3b9WRESPHfNM5fhTqf4Dn84yPaVbtmgpLGwcsWjs"
      in
      "  " ^ W.hyperlink ~url (W.cyan "ook5WtH...csWjs")
    in
    let osc8_status =
      if Lazy.force W.osc8_supported then W.themed_success "  OSC 8: enabled"
      else
        W.themed_warning
          "  OSC 8: disabled (tmux/screen detected, set \
           MIAOU_TUI_HYPERLINKS=on to force)"
    in
    let hint =
      W.dim
        "  Hover/click links if your terminal supports OSC 8 (kitty, iTerm2, \
         GNOME Terminal, ...)"
    in
    String.concat
      "\n\n"
      [
        header;
        body;
        W.dim s.message;
        section_osc8;
        osc8_status;
        osc8_plain;
        osc8_styled;
        osc8_long_url;
        hint;
      ]

  let go_back s =
    {s with next_page = Some Demo_shared.Demo_config.launcher_page_name}

  let handle_key s key_str ~size:_ =
    let handle_link key =
      let link, acted = Link.handle_key s.link ~key in
      let message =
        if acted then
          match s.target with
          | Link.Internal id -> Printf.sprintf "Navigated to %s" id
          | Link.External url -> Printf.sprintf "Would open %s" url
        else s.message
      in
      {s with link; message}
    in
    if Miaou_helpers.Mouse.is_mouse_event key_str then s
    else
      match Miaou.Core.Keys.of_string key_str with
      | Some Miaou.Core.Keys.Escape -> go_back s
      | Some k -> handle_link (Miaou.Core.Keys.to_string k)
      | None -> s

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
