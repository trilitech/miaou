open Alcotest

let test_driver_flags () =
  ignore Miaou_core.Html_driver.available ;
  ignore Miaou_core.Sdl_driver.available ;
  ignore Miaou_core.Lambda_term_driver.available ;
  ignore Miaou_driver_sdl.Sdl_enabled.enabled ;
  ignore Miaou_driver_term.Lambda_term_driver.available ;
  ignore (Miaou_core.Tui_driver.size ())

let () =
  run
    "drivers_smoke"
    [("drivers_smoke", [test_case "driver flags" `Quick test_driver_flags])]
