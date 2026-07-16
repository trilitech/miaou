open Alcotest

module Capture_page : Miaou_core.Tui_page.PAGE_SIG = struct
  type state = int

  type key_binding = state Miaou_core.Tui_page.key_binding_desc

  type pstate = state Miaou_core.Navigation.t

  type msg = unit

  include Test_helpers.Stub_page_defaults (struct
    type nonrec state = state

    type nonrec pstate = pstate
  end)

  let init () = Miaou_core.Navigation.make 0

  let update ps _ = ps

  let view ps ~focus:_ ~size:_ =
    Printf.sprintf "Capture demo %d" ps.Miaou_core.Navigation.s

  let keymap _ = []

  let handled_keys () = []

  let handle_key ps key ~size:_ =
    if key = "x" then Miaou_core.Navigation.update (fun s -> s + 1) ps else ps

  let on_key ps key ~size =
    let key_str = Miaou_core.Keys.to_string key in
    let ps' = handle_key ps key_str ~size in
    (ps', Miaou_interfaces.Key_event.Bubble)
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

(* Frame-hash dedup: a run of identical (rows, cols, frame) triples only
   produces one JSONL line, so a wait_for poll loop re-rendering the same
   unchanged screen a hundred times over doesn't inflate the recording. *)
let test_frame_dedup () =
  with_temp_file "miaou_dedup_frames" (fun frames ->
      with_env
        [
          ("MIAOU_DEBUG_FRAME_CAPTURE", Some "1");
          ("MIAOU_DEBUG_FRAME_CAPTURE_PATH", Some frames);
        ]
        (fun () ->
          for _ = 1 to 100 do
            Miaou_core.Tui_capture.record_frame ~rows:24 ~cols:80 "same frame"
          done ;
          Miaou_core.Tui_capture.record_frame
            ~rows:24
            ~cols:80
            "different frame" ;
          let payload = slurp frames in
          let line_count =
            String.fold_left
              (fun n c -> if c = '\n' then n + 1 else n)
              0
              payload
          in
          check int "100 identical frames + 1 different = 2 lines" 2 line_count ;
          Miaou_core.Tui_capture.reset_for_tests ()))

let () =
  run
    "capture"
    [
      ("capture", [test_case "writes files" `Quick test_capture_outputs]);
      ( "frame_dedup",
        [test_case "consecutive identical frames dedup" `Quick test_frame_dedup]
      );
    ]
