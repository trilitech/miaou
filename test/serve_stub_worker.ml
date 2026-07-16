(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(* Standalone process, driven by test_miaou_serve_lib.ml, that calls
   Miaou_serve.run against a trivial stub page. Slice 1 has no supervisor
   yet, so Miaou_serve.run blocks forever in Web_driver's accept loop —
   the test spawns this as a subprocess and kill -9's it once it has
   observed a successful HTTP response, rather than trying to cancel it
   in-process. *)

module Stub_page : Miaou_core.Tui_page.PAGE_SIG = struct
  type state = unit

  type key_binding = state Miaou_core.Tui_page.key_binding_desc

  type pstate = state Miaou_core.Navigation.t

  type msg = unit

  let init () = Miaou_core.Navigation.make ()

  let update ps _ = ps

  let view _ps ~focus:_ ~size:_ = "serve-stub-worker-marker"

  let move ps _ = ps

  let refresh ps = ps

  let service_select ps _ = ps

  let service_cycle ps _ = ps

  let back ps = ps

  let keymap _ : key_binding list = []

  let handled_keys () = []

  let handle_modal_key ps _ ~size:_ = ps

  let handle_key ps _ ~size:_ = ps

  let on_key ps _key ~size:_ = (ps, Miaou_interfaces.Key_event.Bubble)

  let on_modal_key ps _key ~size:_ = (ps, Miaou_interfaces.Key_event.Bubble)

  let key_hints _ = []

  let has_modal _ = false
end

let () =
  let port = int_of_string (Sys.getenv "MIAOU_SERVE_TEST_PORT") in
  let bind =
    match Sys.getenv_opt "MIAOU_SERVE_TEST_BIND" with
    | Some b -> b
    | None -> "127.0.0.1"
  in
  let auth_file = Sys.getenv_opt "MIAOU_SERVE_TEST_AUTH_FILE" in
  let insecure_allow_plaintext_external =
    match Sys.getenv_opt "MIAOU_SERVE_TEST_INSECURE" with
    | Some ("1" | "true") -> true
    | _ -> false
  in
  Miaou_serve.run
    ~bind
    ?auth_file
    ~port
    ~insecure_allow_plaintext_external
    (module Stub_page)
