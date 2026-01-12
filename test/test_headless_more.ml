open Alcotest
module Headless = Lib_miaou_internal.Headless_driver
module Flash = Lib_miaou_internal.Flash_bus
open LTerm_geom

module Dummy = struct
  type state = int

  type key_binding = state Miaou_core.Tui_page.key_binding_desc

  type pstate = state Miaou_core.Navigation.t

  type msg = unit

  let init () = Miaou_core.Navigation.make 1

  let update ps _ = ps

  let view ps ~focus:_ ~size =
    Printf.sprintf "st=%d %dx%d" ps.Miaou_core.Navigation.s size.rows size.cols

  let move ps _ = ps

  let refresh ps = ps

  let service_select ps _ = ps

  let service_cycle ps _ = ps

  let back ps = ps

  let keymap _ = []

  let handled_keys () = []

  let handle_modal_key ps _ ~size:_ = ps

  let handle_key ps _ ~size:_ = ps

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
