(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

open Alcotest
module Parser = Miaou_driver_common.Input_parser

(* Helper to create a parser with pre-filled buffer via pipe *)
let parser_with_input input =
  let r, w = Unix.pipe () in
  let _ = Unix.write_substring w input 0 (String.length input) in
  Unix.close w ;
  let p = Parser.create r in
  ignore (Parser.refill p ~timeout_s:0.1) ;
  (p, r)

let cleanup (_, r) = try Unix.close r with _ -> ()

(* Test key_to_string conversion *)
let test_key_to_string () =
  check string "Enter" "Enter" (Parser.key_to_string Parser.Enter) ;
  check string "Tab" "Tab" (Parser.key_to_string Parser.Tab) ;
  check string "Backspace" "Backspace" (Parser.key_to_string Parser.Backspace) ;
  check string "Escape" "Esc" (Parser.key_to_string Parser.Escape) ;
  check string "Up" "Up" (Parser.key_to_string Parser.Up) ;
  check string "Down" "Down" (Parser.key_to_string Parser.Down) ;
  check string "Left" "Left" (Parser.key_to_string Parser.Left) ;
  check string "Right" "Right" (Parser.key_to_string Parser.Right) ;
  check string "Delete" "Delete" (Parser.key_to_string Parser.Delete) ;
  check string "Ctrl-a" "C-a" (Parser.key_to_string (Parser.Ctrl 'a')) ;
  check string "Ctrl-c" "C-c" (Parser.key_to_string (Parser.Ctrl 'c')) ;
  check string "Char a" "a" (Parser.key_to_string (Parser.Char "a")) ;
  check string "Char space" " " (Parser.key_to_string (Parser.Char " ")) ;
  check
    string
    "Mouse"
    "Mouse:5:10"
    (Parser.key_to_string (Parser.Mouse {row = 5; col = 10; release = true})) ;
  check string "Refresh" "Refresh" (Parser.key_to_string Parser.Refresh) ;
  check string "Unknown" "xyz" (Parser.key_to_string (Parser.Unknown "xyz"))

(* Test is_nav_key *)
let test_is_nav_key () =
  check bool "Up is nav" true (Parser.is_nav_key Parser.Up) ;
  check bool "Down is nav" true (Parser.is_nav_key Parser.Down) ;
  check bool "Left is nav" true (Parser.is_nav_key Parser.Left) ;
  check bool "Right is nav" true (Parser.is_nav_key Parser.Right) ;
  check bool "Tab is nav" true (Parser.is_nav_key Parser.Tab) ;
  check bool "Delete is nav" true (Parser.is_nav_key Parser.Delete) ;
  check bool "Enter not nav" false (Parser.is_nav_key Parser.Enter) ;
  check bool "Escape not nav" false (Parser.is_nav_key Parser.Escape) ;
  check bool "Char not nav" false (Parser.is_nav_key (Parser.Char "a"))

(* Test simple key parsing *)
let test_parse_simple_keys () =
  (* Enter *)
  let p, r = parser_with_input "\n" in
  (match Parser.parse_key p with
  | Some Parser.Enter -> ()
  | _ -> fail "Expected Enter") ;
  cleanup (p, r) ;

  (* Tab *)
  let p, r = parser_with_input "\t" in
  (match Parser.parse_key p with
  | Some Parser.Tab -> ()
  | _ -> fail "Expected Tab") ;
  cleanup (p, r) ;

  (* Backspace *)
  let p, r = parser_with_input "\127" in
  (match Parser.parse_key p with
  | Some Parser.Backspace -> ()
  | _ -> fail "Expected Backspace") ;
  cleanup (p, r) ;

  (* Regular char *)
  let p, r = parser_with_input "a" in
  (match Parser.parse_key p with
  | Some (Parser.Char "a") -> ()
  | _ -> fail "Expected Char 'a'") ;
  cleanup (p, r) ;

  (* Ctrl-a *)
  let p, r = parser_with_input "\001" in
  (match Parser.parse_key p with
  | Some (Parser.Ctrl 'a') -> ()
  | _ -> fail "Expected Ctrl 'a'") ;
  cleanup (p, r) ;

  (* Ctrl-c *)
  let p, r = parser_with_input "\003" in
  (match Parser.parse_key p with
  | Some (Parser.Ctrl 'c') -> ()
  | _ -> fail "Expected Ctrl 'c'") ;
  cleanup (p, r) ;

  (* Refresh marker *)
  let p, r = parser_with_input "\000" in
  (match Parser.parse_key p with
  | Some Parser.Refresh -> ()
  | _ -> fail "Expected Refresh") ;
  cleanup (p, r)

(* Test arrow key parsing *)
let test_parse_arrow_keys () =
  (* Up: ESC [ A *)
  let p, r = parser_with_input "\027[A" in
  (match Parser.parse_key p with
  | Some Parser.Up -> ()
  | _ -> fail "Expected Up") ;
  cleanup (p, r) ;

  (* Down: ESC [ B *)
  let p, r = parser_with_input "\027[B" in
  (match Parser.parse_key p with
  | Some Parser.Down -> ()
  | _ -> fail "Expected Down") ;
  cleanup (p, r) ;

  (* Right: ESC [ C *)
  let p, r = parser_with_input "\027[C" in
  (match Parser.parse_key p with
  | Some Parser.Right -> ()
  | _ -> fail "Expected Right") ;
  cleanup (p, r) ;

  (* Left: ESC [ D *)
  let p, r = parser_with_input "\027[D" in
  (match Parser.parse_key p with
  | Some Parser.Left -> ()
  | _ -> fail "Expected Left") ;
  cleanup (p, r) ;

  (* Up with ESC O A format *)
  let p, r = parser_with_input "\027OA" in
  (match Parser.parse_key p with
  | Some Parser.Up -> ()
  | _ -> fail "Expected Up (O format)") ;
  cleanup (p, r) ;

  (* Delete: ESC [ 3 ~ *)
  let p, r = parser_with_input "\027[3~" in
  (match Parser.parse_key p with
  | Some Parser.Delete -> ()
  | _ -> fail "Expected Delete") ;
  cleanup (p, r)

(* Test escape alone *)
let test_parse_escape () =
  let p, r = parser_with_input "\027" in
  (match Parser.parse_key p with
  | Some Parser.Escape -> ()
  | _ -> fail "Expected Escape") ;
  cleanup (p, r)

(* Test multiple keys in sequence *)
let test_parse_sequence () =
  let p, r = parser_with_input "abc" in
  (match Parser.parse_key p with
  | Some (Parser.Char "a") -> ()
  | _ -> fail "Expected 'a'") ;
  (match Parser.parse_key p with
  | Some (Parser.Char "b") -> ()
  | _ -> fail "Expected 'b'") ;
  (match Parser.parse_key p with
  | Some (Parser.Char "c") -> ()
  | _ -> fail "Expected 'c'") ;
  (match Parser.parse_key p with
  | None -> ()
  | _ -> fail "Expected None after buffer empty") ;
  cleanup (p, r)

(* Test SGR mouse parsing *)
let test_parse_mouse_sgr () =
  (* SGR mouse release: ESC [ < 0;10;5m *)
  let p, r = parser_with_input "\027[<0;10;5m" in
  (match Parser.parse_key p with
  | Some (Parser.Mouse {row = 5; col = 10; release = true}) -> ()
  | Some (Parser.Mouse {row; col; release}) ->
      fail
        (Printf.sprintf
           "Mouse parsed but wrong values: row=%d col=%d release=%b"
           row
           col
           release)
  | Some k ->
      fail (Printf.sprintf "Expected Mouse, got %s" (Parser.key_to_string k))
  | None -> fail "Expected Mouse, got None") ;
  cleanup (p, r) ;

  (* SGR mouse press (motion): ESC [ < 0;10;5M *)
  let p, r = parser_with_input "\027[<0;10;5M" in
  (match Parser.parse_key p with
  | Some (Parser.Mouse {release = false; _}) -> ()
  | _ -> fail "Expected Mouse with release=false") ;
  cleanup (p, r)

(* Test peek doesn't consume *)
let test_peek_no_consume () =
  let p, r = parser_with_input "a" in
  (* Peek should return Some without consuming *)
  (match Parser.peek_key p with
  | Some (Parser.Char "a") -> ()
  | _ -> fail "Expected Char 'a' from peek") ;
  check int "buffer still has 1 byte" 1 (Parser.pending_length p) ;
  (* Parse should also return it *)
  (match Parser.parse_key p with
  | Some (Parser.Char "a") -> ()
  | _ -> fail "Expected Char 'a' from parse") ;
  check int "buffer now empty" 0 (Parser.pending_length p) ;
  cleanup (p, r)

(* Test clear *)
let test_clear () =
  let p, r = parser_with_input "abc" in
  check int "buffer has 3 bytes" 3 (Parser.pending_length p) ;
  Parser.clear p ;
  check int "buffer empty after clear" 0 (Parser.pending_length p) ;
  cleanup (p, r)

let () =
  run
    "input_parser"
    [
      ( "key_to_string",
        [
          test_case "conversion" `Quick test_key_to_string;
          test_case "is_nav_key" `Quick test_is_nav_key;
        ] );
      ( "parse",
        [
          test_case "simple keys" `Quick test_parse_simple_keys;
          test_case "arrow keys" `Quick test_parse_arrow_keys;
          test_case "escape" `Quick test_parse_escape;
          test_case "sequence" `Quick test_parse_sequence;
          test_case "mouse sgr" `Quick test_parse_mouse_sgr;
        ] );
      ( "peek",
        [
          test_case "no consume" `Quick test_peek_no_consume;
          test_case "clear" `Quick test_clear;
        ] );
    ]
