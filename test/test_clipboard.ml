(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

open Alcotest
module Clipboard = Miaou_interfaces.Clipboard

(* Test OSC 52 encoding - uses BEL (\007) as terminator *)
let test_osc52_encode () =
  (* Empty string *)
  let encoded = Clipboard.osc52_encode "" in
  check string "empty string" "\027]52;c;\007" encoded ;

  (* Simple ASCII text *)
  let encoded = Clipboard.osc52_encode "Hello" in
  (* "Hello" in base64 is "SGVsbG8=" *)
  check string "Hello" "\027]52;c;SGVsbG8=\007" encoded ;

  (* Text with spaces *)
  let encoded = Clipboard.osc52_encode "Hello World" in
  (* "Hello World" in base64 is "SGVsbG8gV29ybGQ=" *)
  check string "Hello World" "\027]52;c;SGVsbG8gV29ybGQ=\007" encoded ;

  (* Single character *)
  let encoded = Clipboard.osc52_encode "a" in
  (* "a" in base64 is "YQ==" *)
  check string "single char" "\027]52;c;YQ==\007" encoded ;

  (* Two characters *)
  let encoded = Clipboard.osc52_encode "ab" in
  (* "ab" in base64 is "YWI=" *)
  check string "two chars" "\027]52;c;YWI=\007" encoded ;

  (* Three characters (no padding needed) *)
  let encoded = Clipboard.osc52_encode "abc" in
  (* "abc" in base64 is "YWJj" *)
  check string "three chars" "\027]52;c;YWJj\007" encoded ;

  (* Newlines *)
  let encoded = Clipboard.osc52_encode "line1\nline2" in
  (* "line1\nline2" in base64 is "bGluZTEKbGluZTI=" *)
  check string "newlines" "\027]52;c;bGluZTEKbGluZTI=\007" encoded

(* Test clipboard registration and copy *)
let test_clipboard_copy () =
  let copied_text = ref "" in
  let write_fn s = copied_text := s in
  Clipboard.register ~write:write_fn () ;

  let clip = Clipboard.require () in
  check bool "copy_available" true (clip.copy_available ()) ;

  clip.copy "test" ;
  (* "test" in base64 is "dGVzdA==" *)
  check string "copied text" "\027]52;c;dGVzdA==\007" !copied_text

(* Test clipboard with disabled *)
let test_clipboard_disabled () =
  let write_called = ref false in
  let write_fn _ = write_called := true in
  Clipboard.register ~write:write_fn ~enabled:false () ;

  let clip = Clipboard.require () in
  check bool "copy_available false" false (clip.copy_available ()) ;

  clip.copy "test" ;
  check bool "write not called" false !write_called

(* Test on_copy callback *)
let test_clipboard_on_copy () =
  let callback_text = ref "" in
  let write_fn _ = () in
  let on_copy text = callback_text := text in
  Clipboard.register ~write:write_fn ~on_copy () ;

  let clip = Clipboard.require () in
  clip.copy "hello callback" ;
  check string "callback received text" "hello callback" !callback_text

let () =
  run
    "clipboard"
    [
      ("osc52", [test_case "encode" `Quick test_osc52_encode]);
      ( "clipboard",
        [
          test_case "copy" `Quick test_clipboard_copy;
          test_case "disabled" `Quick test_clipboard_disabled;
          test_case "on_copy callback" `Quick test_clipboard_on_copy;
        ] );
    ]
