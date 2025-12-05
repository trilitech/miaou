open Alcotest

module MM = Miaou_core.Modal_manager

module Modal_page = struct
  type state = int

  type msg = unit

  let init () = 0

  let update st _ = st

  let view st ~focus:_ ~size:_ = Printf.sprintf "st=%d" st

  let move st _ = st

  let refresh st = st

  let enter st = st

  let service_select st _ = st

  let service_cycle st _ = st

  let back st = st

  let keymap _ = []

  let handle_modal_key st _ ~size:_ = st

  let handle_key st key ~size:_ = if key = "inc" then st + 1 else st

  let next_page _ = None

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
    ~on_close:(fun _ -> function `Commit -> commit_called := true | `Cancel -> cancel_called := true) ;
  check bool "has active" true (MM.has_active ()) ;
  MM.handle_key "inc" ;
  MM.handle_key "ok" ;
  check bool "commit called" true !commit_called ;
  MM.push_default
    (module Modal_page)
    ~init:(Modal_page.init ())
    ~ui:{title = "t2"; left = None; max_width = None; dim_background = true}
    ~on_close:(fun _ -> function `Commit -> () | `Cancel -> cancel_called := true) ;
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
    ~extract:(fun st -> Some st)
    ~on_result:(fun v ->
      results :=
        ("confirm_extract", Option.value ~default:"none"
                               (Option.map string_of_int v))
        :: !results)
    () ;
  MM.handle_key "inc" ;
  MM.handle_key "Enter" ;
  MM.prompt
    (module Modal_page)
    ~init:(Modal_page.init ())
    ~extract:(fun st -> Some (st + 10))
    ~on_result:(fun v ->
      results :=
        ("prompt", Option.value ~default:"none"
                     (Option.map string_of_int v))
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
