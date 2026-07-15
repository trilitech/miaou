open Alcotest

let test_driver_flags () =
  (* Miaou_runner_common.Tui_driver_common.size was a dead
     [(Obj.magic 0 : t)] placeholder stub with no legitimate producer,
     removed in crash-ub-fixes slice S8; nothing else referenced it. *)
  ignore Miaou_runner_common.Html_driver.available ;
  ignore Miaou_driver_term.Lambda_term_driver.available ;
  ignore Miaou_driver_sdl.Sdl_enabled.enabled

let () =
  run
    "drivers_smoke"
    [("drivers_smoke", [test_case "driver flags" `Quick test_driver_flags])]
