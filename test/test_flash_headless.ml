open Alcotest
module Flash = Lib_miaou_internal.Flash_bus
module Headless = Lib_miaou_internal.Headless_driver

let test_flash_bus () =
  Flash.push ~duration:(-1.) "drop" ;
  Flash.push ~level:Flash.Warn ~duration:1. "keep" ;
  Flash.prune () ;
  let entries = Flash.snapshot () in
  check int "kept entries" 1 (List.length entries) ;
  check string "message" "keep" (snd (List.hd entries))

module Dummy_page = struct
  type state = int

  type msg = unit

  let init () = 0

  let update st _ = st

  let view st ~focus:_ ~size =
    LTerm_geom.(Printf.sprintf "state=%d size=%dx%d" st size.rows size.cols)

  let move st _ = st

  let refresh st = st

  let enter st = st

  let service_select st _ = st

  let service_cycle st _ = st

  let back st = st

  let keymap _ = []

  let handled_keys () = []

  let handle_modal_key st _ ~size:_ = st

  let handle_key st key ~size:_ = if key = "inc" then st + 1 else st

  let next_page _ = None

  let has_modal _ = false
end

let test_headless_driver () =
  Headless.set_size 10 20 ;
  Headless.set_page (module Dummy_page) ;
  Headless.feed_keys ["k1"; "k2"] ;
  check (option string) "takes key" (Some "k1") (Headless.Key_queue.take ()) ;
  Headless.Key_queue.clear () ;
  Flash.push ~level:Flash.Info "info" ;
  Flash.push ~level:Flash.Error "err" ;
  Headless.render_page_with (module Dummy_page) (Dummy_page.init ()) ;
  let content = Headless.get_screen_content () in
  check bool "renders size" true (String.exists (fun c -> c = 'x') content) ;
  check bool "contains state marker" true (String.contains content '0') ;
  check bool "flash message" true (String.exists (fun c -> c = '[') content) ;
  Headless.Screen.clear () ;
  check string "cleared" "" (Headless.Screen.get ())

let suite =
  [
    test_case "flash bus snapshot/prune" `Quick test_flash_bus;
    test_case "headless driver rendering" `Quick test_headless_driver;
  ]

let () = run "flash_headless" [("flash_headless", suite)]
