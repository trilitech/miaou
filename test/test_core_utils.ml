open Alcotest
module HH = Miaou_core.Help_hint
module QF = Miaou_core.Quit_flag
module Reg = Miaou_core.Registry
module KHS = Miaou_internals.Key_handler_stack
module Narrow = Miaou_core.Narrow_modal.Page
module LogCap = Miaou_interfaces.Logger_capability

module Dummy_page = struct
  type state = unit

  type pstate = state Miaou_core.Navigation.t

  type msg = unit

  let init () = Miaou_core.Navigation.make ()

  let update ps _ = ps

  let view _ps ~focus:_ ~size:_ = "page"

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

let test_help_hint () =
  HH.set (Some "h") ;
  HH.push ~short:"s" () ;
  check (option string) "get" (Some "s") (HH.get ()) ;
  HH.pop () ;
  check (option string) "after pop" (Some "h") (HH.get ()) ;
  HH.clear () ;
  check (option string) "cleared" None (HH.get ())

let test_quit_flag () =
  QF.set_pending () ;
  check bool "pending" true (QF.is_pending ()) ;
  QF.clear_pending () ;
  check bool "cleared" false (QF.is_pending ())

let test_registry () =
  Reg.unregister "p" ;
  let added =
    Reg.register_once "p" (module Dummy_page : Miaou_core.Tui_page.PAGE_SIG)
  in
  check bool "added" true added ;
  check bool "exists" true (Reg.exists "p") ;
  Reg.register_lazy "lazy" (fun () -> (module Dummy_page)) ;
  ignore (Reg.find "lazy") ;
  Reg.override "p" (module Dummy_page) ;
  Reg.unregister "lazy" ;
  check bool "find" true (Reg.find "p" |> Option.is_some) ;
  check bool "list names" true (List.mem "p" (Reg.list_names ())) ;
  check
    bool
    "list entries"
    true
    (List.exists (fun (n, _) -> n = "p") (Reg.list ()))

let test_key_handler_stack () =
  let called = ref false in
  let st, h = KHS.push KHS.empty [("a", (fun () -> called := true), "help")] in
  let handled, st' = KHS.dispatch st "a" in
  check bool "handled" true handled ;
  check bool "action called" true !called ;
  let st'' = fst (KHS.push st' ~delegate:false [("b", (fun () -> ()), "hb")]) in
  let handled_b, _ = KHS.dispatch st'' "c" in
  check bool "delegate stops" false handled_b ;
  let st = KHS.pop st h |> KHS.pop_top |> KHS.clear in
  check int "depth" 0 (KHS.depth st)

let test_key_handler_listing () =
  let action () = () in
  let st, _ = KHS.push KHS.empty [("x", action, "hx")] in
  let st, _ = KHS.push st ~delegate:false [("y", action, "hy")] in
  let keys = KHS.top_keys st in
  check bool "top has y" true (List.mem "y" keys) ;
  let bindings = KHS.top_bindings st in
  check
    bool
    "top bindings include hy"
    true
    (List.exists (fun (k, h) -> k = "y" && h = "hy") bindings) ;
  let all = KHS.all_bindings st in
  check bool "all include x" true (List.exists (fun (k, _) -> k = "x") all)

let test_capabilities () =
  let module Cap = Miaou_core.Capability in
  Cap.clear () ;
  let k_int = Cap.create ~name:"int" in
  let k_str = Cap.create ~name:"str" in
  check bool "mem empty" false (Cap.mem k_int) ;
  Cap.register k_int 123 ;
  Cap.set k_str "abc" ;
  check (option int) "get int" (Some 123) (Cap.get k_int) ;
  check string "require str" "abc" (Cap.require k_str) ;
  let missing = Cap.create ~name:"missing" in
  check bool "mem missing" false (Cap.mem missing) ;
  let missing_list = Cap.check_all [Cap.any k_int; Cap.any missing] in
  check (list string) "missing list" ["missing"] missing_list ;
  let names = Cap.list () |> List.map fst in
  check bool "list contains int" true (List.mem "int" names) ;
  Cap.clear () ;
  match Cap.get k_int with
  | None -> ()
  | Some _ -> failwith "capability should be cleared"

let test_logger_capability () =
  Miaou_core.Capability.clear () ;
  let calls = ref [] in
  let logger =
    {
      LogCap.logf = (fun lvl msg -> calls := (lvl, msg) :: !calls);
      set_enabled =
        (fun flag -> calls := (LogCap.Info, string_of_bool flag) :: !calls);
      set_logfile =
        (fun f ->
          calls := (LogCap.Info, Option.value ~default:"none" f) :: !calls ;
          Ok ());
    }
  in
  LogCap.set logger ;
  ignore (LogCap.get ()) ;
  LogCap.require () |> fun l ->
  l.logf LogCap.Debug "hello" ;
  l.set_enabled true ;
  l.set_logfile (Some "file.log") |> ignore ;
  check bool "logger called" true (!calls <> [])

let () =
  run
    "core_utils"
    [
      ( "core_utils",
        [
          test_case "help hint" `Quick test_help_hint;
          test_case "quit flag" `Quick test_quit_flag;
          test_case "registry" `Quick test_registry;
          test_case "key handler stack" `Quick test_key_handler_stack;
          test_case "key handler listing" `Quick test_key_handler_listing;
          test_case "narrow modal page" `Quick (fun () ->
              let msg = Narrow.init () in
              let rendered =
                Narrow.view
                  msg
                  ~focus:true
                  ~size:{LTerm_geom.rows = 10; cols = 40}
              in
              let dummy_msg : Narrow.msg = Obj.magic () in
              let advanced =
                msg |> fun s ->
                Narrow.handle_key s "x" ~size:{LTerm_geom.rows = 10; cols = 40}
                |> fun s ->
                Narrow.handle_modal_key
                  s
                  "esc"
                  ~size:{LTerm_geom.rows = 5; cols = 20}
                |> fun s ->
                Narrow.update s dummy_msg |> fun s ->
                Narrow.move s 1 |> Narrow.refresh |> fun s ->
                Narrow.service_select s 0 |> fun s ->
                Narrow.service_cycle s 1 |> fun s ->
                Narrow.handle_key
                  s
                  "Enter"
                  ~size:{LTerm_geom.rows = 10; cols = 40}
                |> Narrow.back
              in
              check bool "contains text" true (String.length rendered > 0) ;
              check bool "no modal" false (Narrow.has_modal advanced) ;
              check
                bool
                "no next page"
                true
                (Option.is_none (Miaou_core.Navigation.pending msg)) ;
              check int "empty keymap" 0 (List.length (Narrow.keymap msg)));
          test_case "capabilities" `Quick test_capabilities;
          test_case "logger capability" `Quick test_logger_capability;
        ] );
    ]
