open Alcotest
module Headless = Lib_miaou_internal.Headless_driver
open LTerm_geom

module Page = struct
  type state = int

  type msg = unit

  let init () = 0

  let update st _ = st

  let view st ~focus:_ ~size =
    Printf.sprintf "st=%d %dx%d" st size.rows size.cols

  let move st delta = st + delta

  let refresh st = st + 1

  let enter st = st

  let service_select st _ = st

  let service_cycle st _ = st

  let back st = st

  let keymap _ = []

  let handled_keys () = []

  let handle_modal_key st _ ~size:_ = st

  let handle_key st key ~size:_ =
    if key = "q" then st else st + String.length key

  let next_page st = if st > 2 then Some "__QUIT__" else None

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
