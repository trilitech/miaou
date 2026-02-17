(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

module Inner = struct
  let tutorial_title = "Style System"

  let tutorial_markdown = [%blob "README.md"]

  module Box = Miaou_widgets_layout.Box_widget
  module Flex = Miaou_widgets_layout.Flex_layout
  module H = Miaou_helpers.Helpers
  module Style_context = Miaou_style.Style_context
  module Theme = Miaou_style.Theme
  module Theme_loader = Miaou_style.Theme_loader
  module W = Miaou_widgets_display.Widgets

  type theme_choice = Dark | Light | High_contrast

  type loaded_theme = {theme : Theme.t; error : string option}

  type themes = {
    dark : loaded_theme;
    light : loaded_theme;
    high_contrast : loaded_theme;
  }

  type state = {
    themes : themes;
    choice : theme_choice;
    cursor : int;
    next_page : string option;
  }

  type msg = unit

  let load_theme ~label blob =
    match Theme_loader.of_json_string blob with
    | Ok t -> {theme = t; error = None}
    | Error e -> {theme = Theme.default; error = Some (label ^ ": " ^ e)}

  let load_theme_file ~label path =
    if Sys.file_exists path then
      match Theme_loader.load_file path with
      | Ok t -> {theme = t; error = None}
      | Error e -> {theme = Theme.default; error = Some (label ^ ": " ^ e)}
    else load_theme ~label [%blob "theme.json"]

  let themes =
    let dark =
      load_theme_file ~label:"dark" "example/demos/style_system/theme.json"
    in
    let light = load_theme ~label:"light" [%blob "themes/light.json"] in
    let high_contrast =
      load_theme ~label:"high-contrast" [%blob "themes/high-contrast.json"]
    in
    {dark; light; high_contrast}

  let init () = {themes; choice = Dark; cursor = 0; next_page = None}

  let theme_name = function
    | Dark -> "dark"
    | Light -> "light"
    | High_contrast -> "high-contrast"

  let current_theme s =
    match s.choice with
    | Dark -> s.themes.dark
    | Light -> s.themes.light
    | High_contrast -> s.themes.high_contrast

  let clamp_idx i = if i < 0 then 0 else if i > 3 then 3 else i

  let render_tile ~index ~cursor ~title ~size =
    let focused = index = cursor in
    Style_context.with_child_context
      ~widget_name:"flex-child"
      ~focused
      ~selected:focused
      ~index
      ~count:4
      (fun () ->
        let body_lines =
          [
            "Contextual background";
            "Accent: " ^ W.themed_accent "link";
            "Status: " ^ W.themed_success "success" ^ " / "
            ^ W.themed_error "error";
            "Selection: " ^ W.themed_selection "selected";
          ]
        in
        let body =
          body_lines |> List.map W.themed_contextual |> H.concat_lines
        in
        let label = if focused then title ^ " (focus)" else title in
        Box.render
          ~title:label
          ~style:Box.None_
          ~padding:{left = 1; right = 1; top = 0; bottom = 0}
          ~width:size.LTerm_geom.cols
          body)

  let row s size =
    let titles = ["Tokens"; "Context"; "Selection"; "Focus"] in
    let children =
      List.mapi
        (fun i title ->
          {
            Flex.render = render_tile ~index:i ~cursor:s.cursor ~title;
            basis = Flex.Fill;
            cross = None;
          })
        titles
    in
    Flex.create
      ~direction:Flex.Row
      ~gap:{h = 2; v = 0}
      ~padding:{left = 1; right = 1; top = 0; bottom = 0}
      ~align_items:Flex.Center
      ~justify:Flex.Space_between
      children
    |> fun flex -> Flex.render flex ~size

  let update s _ = s

  let view s ~focus:_ ~size =
    let current = current_theme s in
    Style_context.with_theme current.theme (fun () ->
        let header = W.themed_emphasis "Style System Demo" in
        let sub =
          W.themed_muted
            "1/2/3 switch theme · Left/Right move focus · Esc returns"
        in
        let theme_line =
          W.themed_text
            ("Theme: " ^ theme_name s.choice ^ " (" ^ current.theme.name ^ ")")
        in
        let status_line =
          match current.error with
          | None -> W.themed_success "Theme parse: ok"
          | Some e -> W.themed_error ("Theme parse: " ^ e)
        in
        let warnings =
          if current.error = None then
            let warnings = Theme.validate current.theme in
            match warnings with
            | [] -> []
            | w :: _ -> [W.themed_warning ("Theme warning: " ^ w)]
          else []
        in
        let row_height = max 6 (size.LTerm_geom.rows - 6) in
        let tiles =
          row s {LTerm_geom.cols = size.LTerm_geom.cols; rows = row_height}
        in
        String.concat
          "\n\n"
          ((header :: sub :: theme_line :: status_line :: warnings) @ [tiles]))

  let go_back s =
    {s with next_page = Some Demo_shared.Demo_config.launcher_page_name}

  let handle_key s key_str ~size:_ =
    match key_str with
    | "1" -> {s with choice = Dark}
    | "2" -> {s with choice = Light}
    | "3" -> {s with choice = High_contrast}
    | "Left" | "h" -> {s with cursor = clamp_idx (s.cursor - 1)}
    | "Right" | "l" -> {s with cursor = clamp_idx (s.cursor + 1)}
    | _ -> (
        match Miaou.Core.Keys.of_string key_str with
        | Some Miaou.Core.Keys.Escape -> go_back s
        | _ -> s)

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
