(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

(* Gallery launcher - imports all demo modules and provides navigation *)

module FB = Miaou_widgets_layout.File_browser_widget
module Navigation = Miaou.Core.Navigation
module List_widget = Miaou_widgets_display.List_widget

type step = {title : string; open_demo : pstate -> pstate}

and state = {list : List_widget.t}

and pstate = state Navigation.t

type key_binding = state Miaou.Core.Tui_page.key_binding_desc

type msg = unit

let launcher_page_name = Demo_shared.Demo_config.launcher_page_name

let goto name page =
  let f ps =
    if not (Miaou.Core.Registry.exists name) then
      Miaou.Core.Registry.register name page ;
    Navigation.goto name ps
  in
  f

let demos =
  [
    {
      title = "Textbox Widget";
      open_demo =
        (fun ps ->
          Miaou.Core.Modal_manager.push
            (module Demo_modals.Textbox_modal)
            ~init:(Demo_modals.Textbox_modal.init ())
            ~ui:
              {
                title = "Textbox Demo";
                left = Some 20;
                max_width = Some (Fixed 60);
                dim_background = true;
              }
            ~commit_on:["Enter"; "Tab"]
            ~cancel_on:["Esc"]
            ~on_close:(fun _ -> function
              | `Commit -> Logs.info (fun m -> m "Textbox committed")
              | `Cancel -> Logs.info (fun m -> m "Textbox cancelled")) ;
          ps);
    };
    {
      title = "Select Widget";
      open_demo =
        (fun ps ->
          Miaou.Core.Modal_manager.confirm_with_extract
            (module Demo_modals.Select_modal)
            ~init:(Demo_modals.Select_modal.init ())
            ~title:"Select Demo"
            ~left:20
            ~max_width:(Fixed 60)
            ~dim_background:true
            ~extract:(fun modal_ps ->
              Demo_modals.Select_modal.extract_selection modal_ps)
            ~on_result:(fun res ->
              match res with
              | Some sel -> Logs.info (fun m -> m "Select committed: %s" sel)
              | None -> Logs.info (fun m -> m "Select cancelled"))
            () ;
          ps);
    };
    {
      title = "File Browser";
      open_demo =
        (fun ps ->
          Miaou.Core.Modal_manager.push
            (module Demo_modals.File_browser_modal)
            ~init:(Demo_modals.File_browser_modal.init ())
            ~ui:
              {
                title = "File Browser Demo";
                left = Some 10;
                max_width = Some (Fixed 80);
                dim_background = true;
              }
            ~commit_on:["Space"; " "]
            ~cancel_on:["Esc"]
            ~on_close:(fun
                (modal_ps : Demo_modals.File_browser_modal.pstate) ->
              function
              | `Commit ->
                  let st = modal_ps.Miaou.Core.Navigation.s in
                  let sel =
                    match FB.get_selection st with
                    | Some path -> path
                    | None -> "<none>"
                  in
                  Logs.info (fun m -> m "File browser committed: %s" sel) ;
                  Demo_shared.Tutorial_modal.show
                    ~title:"Selected path"
                    ~markdown:(Printf.sprintf "You selected:\n\n`%s`" sel)
                    ()
              | `Cancel ->
                  let st = modal_ps.Miaou.Core.Navigation.s in
                  Logs.info (fun m ->
                      m
                        "File browser cancelled (was on %s)"
                        (match FB.get_selection st with
                        | Some path -> path
                        | None -> "<none>"))) ;
          ps);
    };
    {
      title = "Select Widget (records)";
      open_demo =
        (fun ps ->
          Miaou.Core.Modal_manager.confirm_with_extract
            (module Demo_modals.Poly_select_modal)
            ~init:(Demo_modals.Poly_select_modal.init ())
            ~title:"Select Demo (poly)"
            ~left:20
            ~max_width:(Fixed 60)
            ~dim_background:true
            ~extract:(fun modal_ps ->
              Demo_modals.Poly_select_modal.extract_selection modal_ps)
            ~on_result:(fun res ->
              match res with
              | Some sel ->
                  Logs.info (fun m -> m "Poly select committed: %s" sel)
              | None -> Logs.info (fun m -> m "Poly select cancelled"))
            () ;
          ps);
    };
    {
      title = "Table Widget";
      open_demo =
        goto
          "demo_table"
          (module Table_demo.Page : Miaou.Core.Tui_page.PAGE_SIG);
    };
    {
      title = "Palette Sampler";
      open_demo =
        goto
          "demo_palette"
          (module Palette_demo.Page : Miaou.Core.Tui_page.PAGE_SIG);
    };
    {
      title = "Logger Demo";
      open_demo =
        goto
          "demo_logger"
          (module Logger_demo.Page : Miaou.Core.Tui_page.PAGE_SIG);
    };
    {
      title = "Key Handling";
      open_demo =
        goto
          "demo_keys"
          (module Key_handling_demo.Page : Miaou.Core.Tui_page.PAGE_SIG);
    };
    {
      title = "Description List";
      open_demo =
        goto
          "demo_description_list"
          (module Description_list_demo.Page : Miaou.Core.Tui_page.PAGE_SIG);
    };
    {
      title = "Pager Widget";
      open_demo =
        goto
          "demo_pager"
          (module Pager_demo.Page : Miaou.Core.Tui_page.PAGE_SIG);
    };
    {
      title = "Tree Viewer";
      open_demo =
        goto "demo_tree" (module Tree_demo.Page : Miaou.Core.Tui_page.PAGE_SIG);
    };
    {
      title = "Layout Helpers";
      open_demo =
        goto
          "demo_layout"
          (module Layout_helpers_demo.Page : Miaou.Core.Tui_page.PAGE_SIG);
    };
    {
      title = "Flex Layout";
      open_demo =
        goto
          "demo_flex"
          (module Flex_layout_demo.Page : Miaou.Core.Tui_page.PAGE_SIG);
    };
    {
      title = "Grid Layout";
      open_demo =
        goto
          "demo_grid"
          (module Grid_layout_demo.Page : Miaou.Core.Tui_page.PAGE_SIG);
    };
    {
      title = "Focus Ring";
      open_demo =
        goto
          "demo_focus_ring"
          (module Focus_ring_demo.Page : Miaou.Core.Tui_page.PAGE_SIG);
    };
    {
      title = "Link";
      open_demo =
        goto "demo_link" (module Link_demo.Page : Miaou.Core.Tui_page.PAGE_SIG);
    };
    {
      title = "Checkboxes";
      open_demo =
        goto
          "demo_checkboxes"
          (module Checkbox_demo.Page : Miaou.Core.Tui_page.PAGE_SIG);
    };
    {
      title = "Radio Buttons";
      open_demo =
        goto
          "demo_radio"
          (module Radio_demo.Page : Miaou.Core.Tui_page.PAGE_SIG);
    };
    {
      title = "Switch";
      open_demo =
        goto
          "demo_switch"
          (module Switch_demo.Page : Miaou.Core.Tui_page.PAGE_SIG);
    };
    {
      title = "Button";
      open_demo =
        goto
          "demo_button"
          (module Button_demo.Page : Miaou.Core.Tui_page.PAGE_SIG);
    };
    {
      title = "Validated Textbox";
      open_demo =
        goto
          "demo_validated_textbox"
          (module Validated_textbox_demo.Page : Miaou.Core.Tui_page.PAGE_SIG);
    };
    {
      title = "Breadcrumbs";
      open_demo =
        goto
          "demo_breadcrumbs"
          (module Breadcrumbs_demo.Page : Miaou.Core.Tui_page.PAGE_SIG);
    };
    {
      title = "Tabs Navigation";
      open_demo =
        goto "demo_tabs" (module Tabs_demo.Page : Miaou.Core.Tui_page.PAGE_SIG);
    };
    {
      title = "Toast Notifications";
      open_demo =
        goto
          "demo_toast"
          (module Toast_demo.Page : Miaou.Core.Tui_page.PAGE_SIG);
    };
    {
      title = "Card & Sidebar";
      open_demo =
        goto
          "demo_card_sidebar"
          (module Card_sidebar_demo.Page : Miaou.Core.Tui_page.PAGE_SIG);
    };
    {
      title = "Spinner & Progress";
      open_demo =
        goto
          "demo_spinner"
          (module Spinner_progress_demo.Page : Miaou.Core.Tui_page.PAGE_SIG);
    };
    {
      title = "Sparkline Charts";
      open_demo =
        goto
          "demo_sparkline"
          (module Sparkline_demo.Page : Miaou.Core.Tui_page.PAGE_SIG);
    };
    {
      title = "Line Chart";
      open_demo =
        goto
          "demo_line_chart"
          (module Line_chart_demo.Page : Miaou.Core.Tui_page.PAGE_SIG);
    };
    {
      title = "Bar Chart";
      open_demo =
        goto
          "demo_bar_chart"
          (module Bar_chart_demo.Page : Miaou.Core.Tui_page.PAGE_SIG);
    };
    {
      title = "System Monitor (Showcase)";
      open_demo =
        goto
          "demo_system_monitor"
          (module System_monitor_demo.Page : Miaou.Core.Tui_page.PAGE_SIG);
    };
    {
      title = "QR Code";
      open_demo =
        goto
          "demo_qr_code"
          (module Qr_code_demo.Page : Miaou.Core.Tui_page.PAGE_SIG);
    };
    {
      title = "Image";
      open_demo =
        goto
          "demo_image"
          (module Image_demo.Page : Miaou.Core.Tui_page.PAGE_SIG);
    };
    {
      title = "Braille Charts";
      open_demo =
        goto
          "demo_braille"
          (module Braille_demo.Page : Miaou.Core.Tui_page.PAGE_SIG);
    };
    {
      title = "Direct Page";
      open_demo =
        goto
          "demo_direct_page"
          (module Direct_page_demo.Page : Miaou.Core.Tui_page.PAGE_SIG);
    };
    {
      title = "Box Widget";
      open_demo =
        goto
          "demo_box_widget"
          (module Box_widget_demo.Page : Miaou.Core.Tui_page.PAGE_SIG);
    };
    {
      title = "Style System";
      open_demo =
        goto
          "demo_style_system"
          (module Style_system_demo.Page : Miaou.Core.Tui_page.PAGE_SIG);
    };
    {
      title = "Textarea";
      open_demo =
        goto
          "demo_textarea"
          (module Textarea_demo.Page : Miaou.Core.Tui_page.PAGE_SIG);
    };
    {
      title = "Focus Container";
      open_demo =
        goto
          "demo_focus_container"
          (module Focus_container_demo.Page : Miaou.Core.Tui_page.PAGE_SIG);
    };
    {
      title = "Canvas";
      open_demo =
        goto
          "demo_canvas"
          (module Canvas_demo.Page : Miaou.Core.Tui_page.PAGE_SIG);
    };
    {
      title = "Miaou Invaders (Game)";
      open_demo =
        goto
          "demo_miaou_invaders"
          (module Miaou_invaders_demo.Page : Miaou.Core.Tui_page.PAGE_SIG);
    };
  ]

let demo_at idx = List.nth_opt demos idx

let demo_items ids =
  ids
  |> List.filter_map (fun idx ->
      demo_at idx
      |> Option.map (fun d -> List_widget.item ~id:(string_of_int idx) d.title))

let demo_group name ids = List_widget.group name (demo_items ids)

let demo_tree =
  [
    List_widget.group
      "Widgets"
      [
        demo_group "Input" [0; 1; 2; 3; 15; 16; 17; 18; 19; 20; 21; 22; 23; 36];
        demo_group "Layout" [11; 12; 13; 24; 34; 37; 38];
        demo_group "Display" [4; 8; 9; 10; 25; 26; 27; 28; 30; 31; 32];
      ];
    demo_group "Core" [6; 7; 14; 33];
    demo_group "Styling" [5; 35];
    demo_group "Showcases" [29; 38];
    demo_group "Games" [39];
  ]

let init () =
  Navigation.make {list = List_widget.create ~expand_all:false demo_tree}

let update ps _ = ps

let open_demo ps idx =
  match demo_at idx with Some d -> d.open_demo ps | None -> ps

let open_demo_by_id ps id =
  match int_of_string_opt id with Some idx -> open_demo ps idx | None -> ps

let launcher_window ~size ~cursor ~total =
  let header_overhead = if size.LTerm_geom.cols < 80 then 1 else 0 in
  let frame_overhead = 2 + 3 + header_overhead in
  let body_rows_available = max 0 (size.LTerm_geom.rows - frame_overhead) in
  let items_capacity = max 1 (body_rows_available - 2) in
  let max_lines = min 12 items_capacity in
  let start =
    let max_start = max 0 (total - max_lines) in
    let desired = cursor - max_lines + 1 in
    max 0 (min desired max_start)
  in
  (start, max_lines)

let view ps ~focus:_ ~size =
  let s = ps.Navigation.s in
  let module W = Miaou_widgets_display.Widgets in
  let title = "MIAOU demo launcher" in
  let instructions =
    W.dim
      "Up/Down (j/k) move · Left/Right collapse/expand · Enter opens · q/Esc \
       quits"
  in
  let total = List_widget.visible_count s.list in
  let cursor = List_widget.cursor_index s.list in
  let start, max_lines = launcher_window ~size ~cursor ~total in
  let lines =
    List_widget.render s.list ~focus:true |> String.split_on_char '\n'
  in
  let slice =
    lines |> List.filteri (fun i _ -> i >= start && i < start + max_lines)
  in
  String.concat "\n" (title :: instructions :: "" :: slice)

let handle_key ps key_str ~size =
  let s = ps.Navigation.s in
  let wheel_delta = Miaou_helpers.Mouse.wheel_scroll_lines in
  let apply_n list n key =
    let rec loop list n =
      if n <= 0 then list else loop (List_widget.handle_key list ~key) (n - 1)
    in
    loop list n
  in
  let activate_selected ps list =
    match List_widget.selected list with
    | Some item when item.selectable && item.children = [] -> (
        match item.id with Some id -> open_demo_by_id ps id | None -> ps)
    | _ -> ps
  in
  if Miaou_helpers.Mouse.is_wheel_up key_str then
    let list = apply_n s.list wheel_delta "Up" in
    Navigation.update (fun _ -> {list}) ps
  else if Miaou_helpers.Mouse.is_wheel_down key_str then
    let list = apply_n s.list wheel_delta "Down" in
    Navigation.update (fun _ -> {list}) ps
  else
    match Miaou_helpers.Mouse.parse_click key_str with
    | Some {row; col = _} ->
        let total = List_widget.visible_count s.list in
        let cursor = List_widget.cursor_index s.list in
        let start, max_lines = launcher_window ~size ~cursor ~total in
        (* Items start at row 4: title(1) + instructions(2) + blank(3) + first item(4) *)
        let items_start_row = 4 in
        let idx_in_slice = row - items_start_row in
        if idx_in_slice >= 0 && idx_in_slice < max_lines then
          let idx = start + idx_in_slice in
          let list = List_widget.set_cursor_index s.list idx in
          let ps = Navigation.update (fun _ -> {list}) ps in
          activate_selected ps list
        else ps
    | None -> (
        match Miaou.Core.Keys.of_string key_str with
        | Some Miaou.Core.Keys.Escape | Some (Miaou.Core.Keys.Char "q") ->
            Navigation.quit ps
        | Some Miaou.Core.Keys.Enter | Some (Miaou.Core.Keys.Char " ") -> (
            let item = List_widget.selected s.list in
            match item with
            | Some it when it.children <> [] ->
                let list = List_widget.toggle s.list in
                Navigation.update (fun _ -> {list}) ps
            | Some it when it.selectable -> (
                match it.id with Some id -> open_demo_by_id ps id | None -> ps)
            | _ -> ps)
        | Some k ->
            let key = Miaou.Core.Keys.to_string k in
            let list = List_widget.handle_key s.list ~key in
            Navigation.update (fun _ -> {list}) ps
        | None -> ps)

let on_key ps key ~size =
  let key_str = Miaou.Core.Keys.to_string key in
  let ps' = handle_key ps key_str ~size in
  (ps', Miaou_interfaces.Key_event.Bubble)

let on_modal_key ps key ~size = on_key ps key ~size

let key_hints (_ : pstate) = []

let move ps _ = ps

let refresh ps = ps

let service_select ps _ = ps

let service_cycle ps _ = ps

let handle_modal_key ps _ ~size:_ = ps

let keymap (_ : pstate) = []

let handled_keys () = []

let back ps = ps

let has_modal _ = Miaou.Core.Modal_manager.has_active ()
