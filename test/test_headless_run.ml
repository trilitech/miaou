open Alcotest
module Headless = Lib_miaou_internal.Headless_driver
open LTerm_geom

module Page = struct
  type state = int

  type pstate = state Miaou_core.Navigation.t

  type msg = unit

  let maybe_quit ps =
    if ps.Miaou_core.Navigation.s > 2 then Miaou_core.Navigation.quit ps else ps

  let init () = Miaou_core.Navigation.make 0

  let update ps _ = ps

  let view ps ~focus:_ ~size =
    Printf.sprintf "st=%d %dx%d" ps.Miaou_core.Navigation.s size.rows size.cols

  let move ps delta =
    Miaou_core.Navigation.update (fun st -> st + delta) ps |> maybe_quit

  let refresh ps =
    Miaou_core.Navigation.update (fun st -> st + 1) ps |> maybe_quit

  let service_select ps _ = ps

  let service_cycle ps _ = ps

  let back ps = ps

  let keymap _ = []

  let handled_keys () = []

  let handle_modal_key ps _ ~size:_ = ps

  let handle_key ps key ~size:_ =
    if key = "q" then ps
    else
      Miaou_core.Navigation.update (fun st -> st + String.length key) ps
      |> maybe_quit

  let has_modal _ = false
end

let test_run_loop () =
  Unix.putenv "MIAOU_TEST_ALLOW_FORCED_SWITCH" "1" ;
  Headless.set_limits ~iterations:10 ~seconds:5.0 () ;
  Headless.feed_keys ["Down"; "__SWITCH__:next"; "q"] ;
  let res = Headless.run (module Page) in
  check
    bool
    "quit or switch"
    true
    (match res with `Quit | `SwitchTo _ -> true)

let () =
  run
    "headless_run"
    [("headless_run", [test_case "run loop" `Quick test_run_loop])]
