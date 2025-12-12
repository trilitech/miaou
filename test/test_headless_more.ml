open Alcotest
module Headless = Lib_miaou_internal.Headless_driver
module Flash = Lib_miaou_internal.Flash_bus
open LTerm_geom

module Dummy = struct
  type state = int

  type msg = unit

  let init () = 1

  let update st _ = st

  let view st ~focus:_ ~size =
    Printf.sprintf "st=%d %dx%d" st size.rows size.cols

  let move st _ = st

  let refresh st = st

  let enter st = st

  let service_select st _ = st

  let service_cycle st _ = st

  let back st = st

  let keymap _ = []

  let handled_keys () = []

  let handle_modal_key st _ ~size:_ = st

  let handle_key st _ ~size:_ = st

  let next_page _ = None

  let has_modal _ = false
end

let test_size_and_keys () =
  Headless.set_size 5 7 ;
  let sz = Headless.get_size () in
  check int "rows" 5 sz.rows ;
  Headless.set_page (module Dummy) ;
  Headless.feed_keys ["k"] ;
  check (option string) "take key" (Some "k") (Headless.Key_queue.take ()) ;
  Headless.Key_queue.clear () ;
  Flash.push ~level:Flash.Warn "warn" ;
  Headless.render_page_with (module Dummy) (Dummy.init ()) ;
  let content = Headless.get_screen_content () in
  check bool "content contains size" true (String.contains content 'x') ;
  check bool "flash appended" true (String.contains content 'w')

let () =
  run
    "headless_more"
    [("headless_more", [test_case "size and keys" `Quick test_size_and_keys])]
