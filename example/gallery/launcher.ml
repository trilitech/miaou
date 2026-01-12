(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

(* Gallery launcher - imports all demo modules and provides navigation *)

module FB = Miaou_widgets_layout.File_browser_widget
module Navigation = Miaou.Core.Navigation

type step = {title : string; open_demo : pstate -> pstate}

and state = {cursor : int}

and pstate = state Navigation.t

type key_binding = state Miaou.Core.Tui_page.key_binding_desc

type msg = Move of int

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
  ]

let init () = Navigation.make {cursor = 0}

let update ps = function
  | Move d ->
      let hi = max 0 (List.length demos - 1) in
      Navigation.update (fun s -> {cursor = max 0 (min hi (s.cursor + d))}) ps

let open_demo ps idx =
  match List.nth_opt demos idx with Some d -> d.open_demo ps | None -> ps

let view ps ~focus:_ ~size =
  let s = ps.Navigation.s in
  let module W = Miaou_widgets_display.Widgets in
  let title = "MIAOU demo launcher" in
  let instructions =
    W.dim
      "Use Up/Down (or j/k) to move, Enter to launch a demo, q or Esc to exit"
  in
  let header_overhead = if size.LTerm_geom.cols < 80 then 1 else 0 in
  let frame_overhead = 2 + 3 + header_overhead in
  let body_rows_available = max 0 (size.LTerm_geom.rows - frame_overhead) in
  let items_capacity = max 1 (body_rows_available - 2) in
  let max_lines = min 12 items_capacity in
  let start =
    let total = List.length demos in
    let max_start = max 0 (total - max_lines) in
    let desired = s.cursor - max_lines + 1 in
    max 0 (min desired max_start)
  in
  let slice =
    List.filteri (fun i _ -> i >= start && i < start + max_lines) demos
  in
  let items =
    List.mapi
      (fun idx d ->
        let i = start + idx in
        if i = s.cursor then W.green ("> " ^ d.title) else "  " ^ d.title)
      slice
  in
  String.concat "\n" (title :: instructions :: "" :: items)

let handle_key ps key_str ~size:_ =
  let s = ps.Navigation.s in
  match Miaou.Core.Keys.of_string key_str with
  | Some Miaou.Core.Keys.Up -> update ps (Move (-1))
  | Some Miaou.Core.Keys.Down -> update ps (Move 1)
  | Some Miaou.Core.Keys.Left -> update ps (Move (-1))
  | Some Miaou.Core.Keys.Right -> update ps (Move 1)
  | Some Miaou.Core.Keys.Enter -> open_demo ps s.cursor
  | Some (Miaou.Core.Keys.Char "q")
  | Some (Miaou.Core.Keys.Char "Esc")
  | Some (Miaou.Core.Keys.Char "Escape") ->
      Navigation.quit ps
  | Some (Miaou.Core.Keys.Char " ") -> open_demo ps s.cursor
  | Some (Miaou.Core.Keys.Char "j") -> update ps (Move 1)
  | Some (Miaou.Core.Keys.Char "k") -> update ps (Move (-1))
  | None -> ps
  | _ -> ps

let move ps delta = update ps (Move delta)

let refresh ps = ps

let service_select ps _ = ps

let service_cycle ps _ = ps

let handle_modal_key ps _ ~size:_ = ps

let keymap (_ : pstate) = []

let handled_keys () = []

let back ps = ps

let has_modal _ = Miaou.Core.Modal_manager.has_active ()
