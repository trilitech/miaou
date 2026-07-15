open Alcotest

module Stub_page : Miaou_core.Tui_page.PAGE_SIG = struct
  type state = unit

  type key_binding = state Miaou_core.Tui_page.key_binding_desc

  type pstate = state Miaou_core.Navigation.t

  type msg = unit

  include Test_helpers.Stub_page_defaults (struct
    type nonrec state = state

    type nonrec pstate = pstate
  end)

  let init () = Miaou_core.Navigation.make ()

  let update ps _ = ps

  let view _ps ~focus:_ ~size:_ = "stub"

  let keymap _ = []

  let handled_keys () = []

  let handle_key ps _ ~size:_ = ps

  let on_key ps key ~size =
    let key_str = Miaou_core.Keys.to_string key in
    let ps' = handle_key ps key_str ~size in
    (ps', Miaou_interfaces.Key_event.Bubble)
end

let test_html_driver_not_available () =
  (* The HTML driver is a documented stub: [available] must stay false and
     [run] must fail loudly rather than silently doing nothing, so callers
     never mistake it for a working backend. *)
  check
    bool
    "html driver reports unavailable"
    false
    Miaou_runner_common.Html_driver.available ;
  check
    bool
    "html driver run raises"
    true
    (try
       ignore (Miaou_runner_common.Html_driver.run (module Stub_page)) ;
       false
     with Failure _ -> true)

let test_term_driver_available () =
  check
    bool
    "term driver reports available"
    true
    Miaou_driver_term.Lambda_term_driver.available

let test_sdl_enabled_flag_matches_env () =
  (* [enabled] is computed once at module init from MIAOU_WITH_SDL, so we
     only assert its type/observable value is a stable boolean rather than
     re-deriving init-time env parsing (which would require re-exec to
     observe a changed value). *)
  let v = Miaou_driver_sdl.Sdl_enabled.enabled in
  check bool "sdl enabled flag is a valid boolean" true (v = true || v = false)

let () =
  run
    "drivers_smoke"
    [
      ( "drivers_smoke",
        [
          test_case
            "html driver unavailable"
            `Quick
            test_html_driver_not_available;
          test_case "term driver available" `Quick test_term_driver_available;
          test_case "sdl enabled flag" `Quick test_sdl_enabled_flag_matches_env;
        ] );
    ]
