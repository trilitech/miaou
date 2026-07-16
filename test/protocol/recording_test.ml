(** Default-on session recording (S3, FR-060/FR-061).

    Deliberately kept in its own test executable/process, separate from
    [test_capture.ml]: it asserts behavior when [MIAOU_DEBUG_*_CAPTURE]
    env vars are genuinely absent, and OCaml's [Unix] has no [unsetenv] to
    restore a var to "absent" after another test in the same process has
    set it — so any test that needs true absence must run in a fresh
    process rather than share one with tests that set-then-"clear" (which
    only ever reaches the empty string, not absence) these variables. *)

open Alcotest

let with_temp_dir prefix f =
  let path = Filename.temp_file prefix "" in
  Sys.remove path ;
  Fun.protect
    ~finally:(fun () ->
      if Sys.file_exists path then (
        (try
           Array.iter
             (fun e -> try Sys.remove (Filename.concat path e) with _ -> ())
             (Sys.readdir path)
         with _ -> ()) ;
        try Unix.rmdir path with _ -> ()))
    (fun () -> f path)

(* This process must never have had MIAOU_DEBUG_KEYSTROKE_CAPTURE,
   MIAOU_DEBUG_FRAME_CAPTURE, or MIAOU_NO_RECORD set by its environment for
   these assertions to be meaningful; that's the normal case for a `dune
   test` invocation and is what FR-060 is actually about (an operator who
   set none of these env vars still gets a recording). *)
let precondition_env_absent () =
  List.for_all
    (fun k -> Sys.getenv_opt k = None)
    [
      "MIAOU_DEBUG_KEYSTROKE_CAPTURE";
      "MIAOU_DEBUG_FRAME_CAPTURE";
      "MIAOU_NO_RECORD";
    ]

let test_force_enable_default_on () =
  Miaou_core.Tui_capture.reset_for_tests () ;
  check
    bool
    "precondition: fresh process, no capture env vars set"
    true
    (precondition_env_absent ()) ;
  with_temp_dir "miaou_default_dir" (fun dir ->
      Unix.putenv "MIAOU_DEBUG_CAPTURE_DIR" dir ;
      Miaou_core.Tui_capture.force_enable () ;
      Miaou_core.Tui_capture.record_keystroke "x" ;
      Miaou_core.Tui_capture.record_frame ~rows:24 ~cols:80 "frame one" ;
      check bool "capture dir was created" true (Sys.file_exists dir) ;
      let entries = Sys.readdir dir in
      check
        bool
        "a keystrokes jsonl was written under the capture dir"
        true
        (Array.exists
           (fun f -> Test_helpers.contains_substring f "keystrokes")
           entries) ;
      check
        bool
        "a frames jsonl was written under the capture dir"
        true
        (Array.exists
           (fun f -> Test_helpers.contains_substring f "frames")
           entries) ;
      Miaou_core.Tui_capture.reset_for_tests ())

let test_no_record_opt_out () =
  Miaou_core.Tui_capture.reset_for_tests () ;
  with_temp_dir "miaou_no_record_dir" (fun dir ->
      Unix.putenv "MIAOU_DEBUG_CAPTURE_DIR" dir ;
      Unix.putenv "MIAOU_NO_RECORD" "1" ;
      Miaou_core.Tui_capture.force_enable () ;
      Miaou_core.Tui_capture.record_keystroke "x" ;
      Miaou_core.Tui_capture.record_frame ~rows:24 ~cols:80 "frame one" ;
      check
        bool
        "no capture dir is created when MIAOU_NO_RECORD wins"
        false
        (Sys.file_exists dir) ;
      Miaou_core.Tui_capture.reset_for_tests ())

let () =
  run
    "default_on_recording"
    [
      ( "recording",
        [
          test_case
            "force_enable turns recording on by default"
            `Quick
            test_force_enable_default_on;
          test_case "MIAOU_NO_RECORD opts out" `Quick test_no_record_opt_out;
        ] );
    ]
