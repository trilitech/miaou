open Alcotest

module Adaptive_page : Miaou_core.Tui_page.PAGE_SIG = struct
  type state = unit

  type key_binding = state Miaou_core.Tui_page.key_binding_desc

  type pstate = state Miaou_core.Navigation.t

  type msg = unit

  let init () = Miaou_core.Navigation.make ()

  let update ps _ = ps

  let layout_for size =
    let module Pane = Miaou_widgets_layout.Pane in
    let left = "CPU Stats\n- load: 0.42\n- temp: 41C" in
    let right = "Logs\nline one\nline two" in
    if size.LTerm_geom.cols >= 80 then
      Pane.split_vertical_with_left_width
        ~width:size.LTerm_geom.cols
        ~left_pad:1
        ~right_pad:1
        ~border:true
        ~wrap:true
        ~sep:"│"
        ~left
        ~right
        ~left_width:(size.LTerm_geom.cols / 3)
    else
      Pane.split_horizontal
        ~height:size.LTerm_geom.rows
        ~top_pad:0
        ~bottom_pad:0
        ~border:false
        ~wrap:true
        ~sep:"-----"
        ~top:left
        ~bottom:right

  let view _ps ~focus:_ ~size = layout_for size

  let move ps _ = ps

  let refresh ps = ps

  let service_select ps _ = ps

  let service_cycle ps _ = ps

  let back ps = ps

  let keymap _ = []

  let handled_keys () = []

  let handle_modal_key ps _ ~size:_ = ps

  let handle_key ps _ ~size:_ = ps

  let has_modal _ = false
end

let render_at cols =
  Lib_miaou_internal.Headless_driver.set_size 24 cols ;
  Lib_miaou_internal.Headless_driver.render_only (module Adaptive_page) ;
  Lib_miaou_internal.Headless_driver.get_screen_content ()

let starts_with s prefix =
  let len = String.length prefix in
  String.length s >= len && String.sub s 0 len = prefix

let () =
  let test_layout_differs_by_width () =
    let wide = render_at 100 in
    let narrow = render_at 60 in
    check bool "wide and narrow render differ" true (wide <> narrow)
  in
  let test_wide_shows_columns () =
    let wide = render_at 100 in
    let first_line =
      match String.split_on_char '\n' wide with [] -> "" | l :: _ -> l
    in
    let corner = Miaou_widgets_display.Widgets.glyph_corner_tl in
    check bool "border present" true (starts_with first_line corner) ;
    check bool "contains CPU" true (String.contains wide 'C') ;
    check bool "contains Logs" true (String.contains wide 'L')
  in
  let test_narrow_stacks_sections () =
    let narrow = render_at 50 in
    let lines = String.split_on_char '\n' narrow in
    let rec find_index prefix idx = function
      | [] -> None
      | l :: tl ->
          if starts_with l prefix then Some idx
          else find_index prefix (idx + 1) tl
    in
    let cpu_idx = find_index "CPU" 0 lines in
    let logs_idx = find_index "Logs" 0 lines in
    match (cpu_idx, logs_idx) with
    | Some ci, Some li -> check bool "logs appear after cpu" true (li > ci)
    | _ -> fail "expected both sections"
  in
  run
    "adaptive_layout"
    [
      ( "responsive",
        [
          test_case "renders-differ" `Quick test_layout_differs_by_width;
          test_case "wide-columns" `Quick test_wide_shows_columns;
          test_case "narrow-stacked" `Quick test_narrow_stacks_sections;
        ] );
    ]
