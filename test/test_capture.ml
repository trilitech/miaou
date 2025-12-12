open Alcotest

module Capture_page : Miaou_core.Tui_page.PAGE_SIG = struct
  type state = int

  type msg = unit

  let init () = 0

  let update s _ = s

  let view s ~focus:_ ~size:_ = Printf.sprintf "Capture demo %d" s

  let move s _ = s

  let refresh s = s

  let enter s = s

  let service_select s _ = s

  let service_cycle s _ = s

  let back s = s

  let keymap _ = []

  let handled_keys () = []

  let handle_modal_key s _ ~size:_ = s

  let handle_key s key ~size:_ = if key = "x" then s + 1 else s

  let next_page _ = None

  let has_modal _ = false
end

let with_temp_file prefix f =
  let path = Filename.temp_file prefix ".jsonl" in
  Sys.remove path ;
  Fun.protect
    ~finally:(fun () -> if Sys.file_exists path then Sys.remove path)
    (fun () -> f path)

let set_env name value =
  match value with Some v -> Unix.putenv name v | None -> Unix.putenv name ""

let with_env vars f =
  let snapshot = List.map (fun (k, _) -> (k, Sys.getenv_opt k)) vars in
  List.iter (fun (k, v) -> set_env k v) vars ;
  Fun.protect
    ~finally:(fun () -> List.iter (fun (k, v) -> set_env k v) snapshot)
    f

let slurp path =
  let ic = open_in path in
  Fun.protect
    ~finally:(fun () -> close_in ic)
    (fun () -> really_input_string ic (in_channel_length ic))

let test_capture_outputs () =
  with_temp_file "miaou_keys" (fun keys ->
      with_temp_file "miaou_frames" (fun frames ->
          with_env
            [
              ("MIAOU_DEBUG_KEYSTROKE_CAPTURE", Some "1");
              ("MIAOU_DEBUG_KEYSTROKE_CAPTURE_PATH", Some keys);
              ("MIAOU_DEBUG_FRAME_CAPTURE", Some "1");
              ("MIAOU_DEBUG_FRAME_CAPTURE_PATH", Some frames);
            ]
            (fun () ->
              Lib_miaou_internal.Headless_driver.Stateful.init
                (module Capture_page) ;
              ignore (Lib_miaou_internal.Headless_driver.Stateful.send_key "x") ;
              ignore (Lib_miaou_internal.Headless_driver.Stateful.send_key "q") ;
              check bool "keystrokes file exists" true (Sys.file_exists keys) ;
              let key_payload = slurp keys in
              check
                bool
                "keystrokes non empty"
                true
                (String.length key_payload > 0) ;
              check bool "frames file exists" true (Sys.file_exists frames) ;
              let frame_payload = slurp frames in
              check
                bool
                "frames non empty"
                true
                (String.length frame_payload > 0) ;
              Miaou_core.Tui_capture.reset_for_tests ())))

let () =
  run
    "capture"
    [("capture", [test_case "writes files" `Quick test_capture_outputs])]
