open Alcotest
module Driver = Miaou_driver_term.Lambda_term_driver

(* Minimal page that starts with a modal which consumes Enter and requests
   navigation to "NEXT" when closed. *)
module Dummy_page : Miaou_core.Tui_page.PAGE_SIG = struct
  type state = unit

  type msg = unit

  let nav = ref None

  module Consuming_modal : Miaou_core.Tui_page.PAGE_SIG = struct
    type state = unit

    type msg = unit

    let init () = ()

    let update s _ = s

    let view _ ~focus:_ ~size:_ = ""

    let move s _ = s

    let refresh s = s

    let enter s = s

    let service_select s _ = s

    let service_cycle s _ = s

    let back s = s

    let handle_modal_key s key ~size:_ =
      (match key with
      | "Enter" ->
          Miaou_core.Modal_manager.set_consume_next_key () ;
          Miaou_core.Modal_manager.close_top `Commit
      | "Esc" ->
          Miaou_core.Modal_manager.set_consume_next_key () ;
          Miaou_core.Modal_manager.close_top `Cancel
      | _ -> ()) ;
      s

    let handle_key s key ~size:_ =
      (match key with
      | "Enter" ->
          Miaou_core.Modal_manager.set_consume_next_key () ;
          Miaou_core.Modal_manager.close_top `Commit
      | "Esc" ->
          Miaou_core.Modal_manager.set_consume_next_key () ;
          Miaou_core.Modal_manager.close_top `Cancel
      | _ -> ()) ;
      s

    let keymap _ = []

    let handled_keys () = []

    let next_page _ = None

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
        match outcome with `Commit -> nav := Some "NEXT" | _ -> ())

  let init () =
    Miaou_core.Modal_manager.clear () ;
    push_modal () ;
    ()

  let update s _ = s

  let view _ ~focus:_ ~size:_ = ""

  let move s _ = s

  let refresh s = s

  let enter s = s

  let service_select s _ = s

  let service_cycle s _ = s

  let back s = s

  let handle_modal_key s key ~size:_ =
    Miaou_core.Modal_manager.handle_key key ;
    s

  let handle_key s _ ~size:_ = s

  let keymap _ = []

  let handled_keys () = []

  let next_page _ = !nav

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
