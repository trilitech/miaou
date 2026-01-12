open Alcotest
module Driver = Miaou_driver_term.Lambda_term_driver

(* Minimal page that starts with a modal which consumes Enter and requests
   navigation to "NEXT" when closed. *)
module Dummy_page : Miaou_core.Tui_page.PAGE_SIG = struct
  type state = unit

  type key_binding = state Miaou_core.Tui_page.key_binding_desc

  type pstate = state Miaou_core.Navigation.t

  type msg = unit

  module Consuming_modal : Miaou_core.Tui_page.PAGE_SIG = struct
    type state = unit

    type key_binding = state Miaou_core.Tui_page.key_binding_desc

    type pstate = state Miaou_core.Navigation.t

    type msg = unit

    let init () = Miaou_core.Navigation.make ()

    let update ps _ = ps

    let view _ps ~focus:_ ~size:_ = ""

    let move ps _ = ps

    let refresh ps = ps

    let service_select ps _ = ps

    let service_cycle ps _ = ps

    let back ps = ps

    let handle_modal_key ps key ~size:_ =
      (match key with
      | "Enter" ->
          Miaou_core.Modal_manager.set_consume_next_key () ;
          Miaou_core.Modal_manager.close_top `Commit
      | "Esc" ->
          Miaou_core.Modal_manager.set_consume_next_key () ;
          Miaou_core.Modal_manager.close_top `Cancel
      | _ -> ()) ;
      ps

    let handle_key ps key ~size:_ =
      (match key with
      | "Enter" ->
          Miaou_core.Modal_manager.set_consume_next_key () ;
          Miaou_core.Modal_manager.close_top `Commit
      | "Esc" ->
          Miaou_core.Modal_manager.set_consume_next_key () ;
          Miaou_core.Modal_manager.close_top `Cancel
      | _ -> ()) ;
      ps

    let keymap _ = []

    let handled_keys () = []

    let has_modal _ = false
  end

  let push_modal () =
    Miaou_core.Modal_manager.push
      (module Consuming_modal)
      ~init:(Consuming_modal.init ())
      ~ui:
        {title = "test"; left = None; max_width = None; dim_background = false}
      ~commit_on:[]
      ~cancel_on:[]
      ~on_close:(fun _ outcome ->
        match outcome with
        | `Commit -> Miaou_core.Modal_manager.set_pending_navigation "NEXT"
        | _ -> ())

  let init () =
    Miaou_core.Modal_manager.clear () ;
    push_modal () ;
    Miaou_core.Navigation.make ()

  let update ps _ = ps

  let view _ps ~focus:_ ~size:_ = ""

  let move ps _ = ps

  let refresh ps = ps

  let service_select ps _ = ps

  let service_cycle ps _ = ps

  let back ps = ps

  let handle_modal_key ps key ~size:_ =
    Miaou_core.Modal_manager.handle_key key ;
    ps

  let handle_key ps _ ~size:_ = ps

  let keymap _ = []

  let handled_keys () = []

  let has_modal _ = Miaou_core.Modal_manager.has_active ()
end

let read_keys keys =
  let keys = ref keys in
  fun () ->
    match !keys with
    | hd :: tl ->
        keys := tl ;
        hd
    | [] -> Driver.Quit

let test_modal_consumes_enter_triggers_navigation () =
  let res =
    Driver.run_with_key_source_for_tests
      ~read_key:(read_keys [Driver.Enter])
      (module Dummy_page)
  in
  check
    (Alcotest.of_pp (fun fmt -> function
      | `Quit -> Format.fprintf fmt "Quit"
      | `SwitchTo s -> Format.fprintf fmt "SwitchTo %s" s))
    "navigation triggered"
    (`SwitchTo "NEXT")
    res

let () =
  run
    "core_driver_modal_navigation"
    [
      ( "modal_navigation",
        [
          test_case
            "enter closes modal and navigates"
            `Quick
            test_modal_consumes_enter_triggers_navigation;
        ] );
    ]
