open Alcotest
module Wz = Miaou_widgets_layout.Wizard_widget

(* User state shared across steps: a simple counter and a flag. *)
type ws = {n : int; flagged : bool}

let make_steps : ws Wz.step array =
  [|
    {
      title = "Counter";
      render = (fun s ~focus:_ ~size:_ -> Printf.sprintf "n = %d" s.n);
      validate =
        (fun s -> if s.n >= 1 then Ok () else Error "increment first (press +)");
      on_key =
        (fun s ~key ->
          match key with
          | "+" -> {s with n = s.n + 1}
          | "-" -> {s with n = s.n - 1}
          | _ -> s);
    };
    {
      title = "Flag";
      render =
        (fun s ~focus:_ ~size:_ -> Printf.sprintf "flagged = %b" s.flagged);
      validate = (fun s -> if s.flagged then Ok () else Error "toggle the flag");
      on_key =
        (fun s ~key -> match key with "f" -> {s with flagged = true} | _ -> s);
    };
    {
      title = "Done";
      render =
        (fun s ~focus:_ ~size:_ ->
          Printf.sprintf "n=%d flagged=%b" s.n s.flagged);
      validate = (fun _ -> Ok ());
      on_key = (fun s ~key:_ -> s);
    };
  |]

let initial = {n = 0; flagged = false}

let make () = Wz.create ~steps:make_steps ~initial

let key t k = Wz.handle_key t ~key:k

let test_initial_state () =
  let t = make () in
  check int "current is 0" 0 (Wz.current_index t) ;
  check int "step count is 3" 3 (Wz.step_count t) ;
  check string "title is Counter" "Counter" (Wz.current_title t) ;
  check bool "not finished" false (Wz.is_finished t) ;
  check bool "not cancelled" false (Wz.is_cancelled t) ;
  check (option string) "no error" None (Wz.current_error t)

let test_step_on_key_updates_state () =
  let t = make () in
  let t = key t "+" in
  let t = key t "+" in
  check int "n incremented twice" 2 (Wz.state t).n

let test_advance_blocked_by_validation () =
  let t = make () in
  let t = key t "Enter" in
  check int "still on step 0" 0 (Wz.current_index t) ;
  check
    (option string)
    "validation error surfaced"
    (Some "increment first (press +)")
    (Wz.current_error t)

let test_advance_after_valid () =
  let t = make () in
  let t = key t "+" in
  let t = key t "Enter" in
  check int "moved to step 1" 1 (Wz.current_index t) ;
  check (option string) "error cleared on advance" None (Wz.current_error t)

let test_back_navigation () =
  let t = make () in
  let t = key t "+" in
  let t = key t "Enter" in
  check int "on step 1" 1 (Wz.current_index t) ;
  let t = key t "Shift-Tab" in
  check int "back to step 0" 0 (Wz.current_index t) ;
  (* state preserved *)
  check int "n preserved on back" 1 (Wz.state t).n

let test_finish_on_last_step () =
  let t = make () in
  let t = key t "+" in
  let t = key t "Enter" in
  let t = key t "f" in
  let t = key t "Enter" in
  check int "on last step" 2 (Wz.current_index t) ;
  let t = key t "Enter" in
  check bool "finished" true (Wz.is_finished t) ;
  (* Further key events ignored once finished *)
  let t' = key t "Shift-Tab" in
  check bool "still finished" true (Wz.is_finished t') ;
  check int "still on last step" 2 (Wz.current_index t')

let test_cancel () =
  let t = make () in
  let t = key t "Escape" in
  check bool "cancelled" true (Wz.is_cancelled t)

let test_create_empty_raises () =
  check_raises
    "empty steps rejected"
    (Invalid_argument "Wizard_widget.create: steps must be non-empty")
    (fun () ->
      let _ = Wz.create ~steps:[||] ~initial:() in
      ())

let () =
  run
    "wizard_widget"
    [
      ( "navigation",
        [
          test_case "initial state" `Quick test_initial_state;
          test_case
            "step on_key updates state"
            `Quick
            test_step_on_key_updates_state;
          test_case
            "advance blocked by validation"
            `Quick
            test_advance_blocked_by_validation;
          test_case "advance after valid" `Quick test_advance_after_valid;
          test_case "back navigation" `Quick test_back_navigation;
          test_case "finish on last step" `Quick test_finish_on_last_step;
          test_case "Escape cancels" `Quick test_cancel;
          test_case "empty steps rejected" `Quick test_create_empty_raises;
        ] );
    ]
