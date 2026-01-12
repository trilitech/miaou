open Alcotest
module MM = Miaou_core.Modal_manager

module Modal_page = struct
  type state = int

  type key_binding = state Miaou_core.Tui_page.key_binding_desc

  type pstate = state Miaou_core.Navigation.t

  type msg = unit

  let init () = Miaou_core.Navigation.make 0

  let update ps _ = ps

  let view ps ~focus:_ ~size:_ =
    Printf.sprintf "st=%d" ps.Miaou_core.Navigation.s

  let move ps _ = ps

  let refresh ps = ps

  let service_select ps _ = ps

  let service_cycle ps _ = ps

  let back ps = ps

  let keymap _ = []

  let handled_keys () = []

  let handle_modal_key ps _ ~size:_ = ps

  let handle_key ps key ~size:_ =
    if key = "inc" then Miaou_core.Navigation.update (fun st -> st + 1) ps
    else ps

  let has_modal _ = false
end

let test_push_commit_cancel () =
  MM.clear () ;
  let commit_called = ref false in
  let cancel_called = ref false in
  MM.set_current_size 30 120 ;
  MM.push
    (module Modal_page)
    ~init:(Modal_page.init ())
    ~ui:{title = "t"; left = None; max_width = None; dim_background = true}
    ~commit_on:["ok"]
    ~cancel_on:["Esc"]
    ~on_close:(fun _ -> function
      | `Commit -> commit_called := true | `Cancel -> cancel_called := true) ;
  check bool "has active" true (MM.has_active ()) ;
  MM.handle_key "inc" ;
  MM.handle_key "ok" ;
  check bool "commit called" true !commit_called ;
  MM.push_default
    (module Modal_page)
    ~init:(Modal_page.init ())
    ~ui:{title = "t2"; left = None; max_width = None; dim_background = true}
    ~on_close:(fun _ -> function
      | `Commit -> () | `Cancel -> cancel_called := true) ;
  MM.handle_key "Esc" ;
  check bool "cancel called" true !cancel_called ;
  check bool "cleared" false (MM.has_active ()) ;
  check (option string) "top title none" None (MM.top_title_opt ()) ;
  MM.set_consume_next_key () ;
  check bool "consume flag" true (MM.take_consume_next_key ())

let test_convenience () =
  MM.clear () ;
  let results = ref [] in
  MM.confirm
    (module Modal_page)
    ~init:(Modal_page.init ())
    ~on_result:(fun b -> results := ("confirm", Bool.to_string b) :: !results)
    () ;
  MM.handle_key "Enter" ;
  MM.confirm_with_extract
    (module Modal_page)
    ~init:(Modal_page.init ())
    ~extract:(fun ps -> Some ps.Miaou_core.Navigation.s)
    ~on_result:(fun v ->
      results :=
        ( "confirm_extract",
          Option.value ~default:"none" (Option.map string_of_int v) )
        :: !results)
    () ;
  MM.handle_key "inc" ;
  MM.handle_key "Enter" ;
  MM.prompt
    (module Modal_page)
    ~init:(Modal_page.init ())
    ~extract:(fun ps -> Some (ps.Miaou_core.Navigation.s + 10))
    ~on_result:(fun v ->
      results :=
        ("prompt", Option.value ~default:"none" (Option.map string_of_int v))
        :: !results)
    () ;
  MM.handle_key "Enter" ;
  check bool "helpers consumed" true (List.length !results = 3) ;
  check bool "stack empty" false (MM.has_active ())

let suite =
  [
    test_case "push/commit/cancel" `Quick test_push_commit_cancel;
    test_case "convenience helpers" `Quick test_convenience;
  ]

let () = run "modal_manager" [("modal_manager", suite)]
