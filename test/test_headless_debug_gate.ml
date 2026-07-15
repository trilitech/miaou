(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Mathias Bourgoin <mathias.bourgoin@atacama.tech>        *)
(*                                                                            *)
(******************************************************************************)

(* Regression test for crash-ub-fixes slice S4: [Headless_driver]'s
   "[driver][debug] ..." tracing must stay silent on stderr unless
   MIAOU_DEBUG is set, instead of unconditionally firing on every
   key/refresh iteration. *)

open Alcotest
module Headless = Lib_miaou_internal.Headless_driver

module Page = struct
  type state = int

  type key_binding = state Miaou_core.Tui_page.key_binding_desc

  type pstate = state Miaou_core.Navigation.t

  type msg = unit

  let maybe_quit ps =
    if ps.Miaou_core.Navigation.s > 2 then Miaou_core.Navigation.quit ps else ps

  let init () = Miaou_core.Navigation.make 0

  let update ps _ = ps

  let view ps ~focus:_ ~size:_ =
    Printf.sprintf "st=%d" ps.Miaou_core.Navigation.s

  let refresh ps =
    Miaou_core.Navigation.update (fun st -> st + 1) ps |> maybe_quit

  let move ps delta =
    Miaou_core.Navigation.update (fun st -> st + delta) ps |> maybe_quit

  let service_select ps _ = ps

  let service_cycle ps _ = ps

  let back ps = ps

  let keymap _ = []

  let handled_keys () = []

  let handle_modal_key ps _ ~size:_ = ps

  let handle_key ps key ~size:_ =
    if key = "q" then ps
    else
      Miaou_core.Navigation.update (fun st -> st + String.length key) ps
      |> maybe_quit

  let on_key ps key ~size =
    let key_str = Miaou_core.Keys.to_string key in
    let ps' = handle_key ps key_str ~size in
    (ps', Miaou_interfaces.Key_event.Bubble)

  let on_modal_key ps key ~size =
    let key_str = Miaou_core.Keys.to_string key in
    let ps' = handle_modal_key ps key_str ~size in
    (ps', Miaou_interfaces.Key_event.Bubble)

  let key_hints _ = []

  let has_modal _ = false
end

(* Redirect fd 2 (stderr) to a temp file for the duration of [f], then
   return the captured content. *)
let capture_stderr f =
  Stdlib.flush Stdlib.stderr ;
  let path = Filename.temp_file "miaou_headless_debug_gate" ".log" in
  let saved_fd = Unix.dup Unix.stderr in
  let out_fd = Unix.openfile path [Unix.O_WRONLY; Unix.O_TRUNC] 0o600 in
  Unix.dup2 out_fd Unix.stderr ;
  Unix.close out_fd ;
  Fun.protect
    ~finally:(fun () ->
      Stdlib.flush Stdlib.stderr ;
      Unix.dup2 saved_fd Unix.stderr ;
      Unix.close saved_fd)
    (fun () ->
      f () ;
      Stdlib.flush Stdlib.stderr) ;
  let ic = open_in path in
  let content = really_input_string ic (in_channel_length ic) in
  close_in ic ;
  Sys.remove path ;
  content

let test_no_debug_output_by_default () =
  Unix.putenv "MIAOU_DEBUG" "" ;
  let captured =
    capture_stderr (fun () ->
        Headless.set_limits ~iterations:5 ~seconds:5.0 () ;
        Headless.feed_keys ["Down"; "Up"; "q"] ;
        ignore
          (Headless.run (module Page) : [`Quit | `Back | `SwitchTo of string]))
  in
  check
    bool
    "no [driver][debug] lines on stderr without MIAOU_DEBUG"
    false
    (Astring.String.is_infix ~affix:"[driver][debug]" captured)

(* Note: [debug_enabled] is a [lazy] value (memoized after first force), by
   design, matching the existing dprintf pattern elsewhere in the codebase
   (e.g. Modal_manager, Modal_renderer). That makes an "enabled" companion
   test order-dependent within a single test binary (whichever test forces
   the lazy first wins for the rest of the process), so we only assert the
   default (silent) behavior here, which is the crash/UB-relevant property:
   headless test runs must not spew "[driver][debug]" on stderr by default. *)

let () =
  run
    "headless_debug_gate"
    [
      ( "headless_debug_gate",
        [
          test_case
            "no debug output by default"
            `Quick
            test_no_debug_output_by_default;
        ] );
    ]
