open Alcotest
module Table = Miaou_widgets_display.Table_widget
module Modal_manager = Miaou_core.Modal_manager
module Headless = Lib_miaou_internal.Headless_driver

module Page : Miaou_core.Tui_page.PAGE_SIG = struct
  type state = int

  type key_binding = state Miaou_core.Tui_page.key_binding_desc

  type pstate = state Miaou_core.Navigation.t

  type msg = unit

  let init () = Miaou_core.Navigation.make 0

  let update ps _ = ps

  let view ps ~focus:_ ~size =
    let open LTerm_geom in
    let st = ps.Miaou_core.Navigation.s in
    let header = ("Name", "Status", "Value") in
    let rows =
      [("Alpha", "ok", "1"); ("Beta", "warn", "2"); ("Gamma", "ok", "3")]
    in
    Table.render_table_80
      ~cols:(Some size.cols)
      ~header
      ~rows
      ~cursor:st
      ~sel_col:0

  let move_state st delta = st + delta

  let move ps delta =
    Miaou_core.Navigation.update (fun st -> move_state st delta) ps

  let refresh ps = ps

  let service_select ps _ = ps

  let service_cycle ps _ = ps

  let back ps = ps

  let keymap _ = []

  let handled_keys () = []

  let handle_modal_key ps _ ~size:_ = ps

  let handle_key ps key ~size:_ =
    match key with "Down" -> move ps 1 | "Up" -> move ps (-1) | _ -> ps

  let has_modal _ = Modal_manager.has_active ()
end

let test_headless_page_with_modal () =
  Modal_manager.clear () ;
  Headless.set_size 12 60 ;
  (* Push a modal so overlay rendering is exercised. *)
  Modal_manager.push_default
    (module Page)
    ~init:(Page.init ())
    ~ui:{title = "Modal"; left = None; max_width = None; dim_background = true}
    ~on_close:(fun _ _ -> ()) ;
  Headless.set_page (module Page) ;
  Headless.render_page_with (module Page) (Page.init ()) ;
  let content = Headless.get_screen_content () in
  check bool "contains table header" true (String.contains content 'N') ;
  check bool "modal active" true (Modal_manager.has_active ()) ;
  Modal_manager.handle_key "Esc" ;
  check bool "modal cleared" true (not (Modal_manager.has_active ()))

let () =
  run
    "integration_tui"
    [
      ( "integration_tui",
        [
          test_case
            "headless page with modal"
            `Quick
            test_headless_page_with_modal;
        ] );
    ]
