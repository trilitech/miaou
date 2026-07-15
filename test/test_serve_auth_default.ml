(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(* FR-003: miaou serve MUST refuse to bind a non-loopback address when no
   auth mechanism is configured, and MUST allow it when auth is configured
   or explicitly overridden. The "allowed" cases are checked at the pure
   policy-decision layer ({!Miaou_serve.Serve_policy.check}): actually
   opening the listening socket and serving is an end-to-end concern
   exercised by the subprocess integration test in
   test_miaou_serve_lib.ml, not repeated here since {!Miaou_serve.run}
   blocks forever in its accept loop (no supervisor/cancellation exists
   yet — that lands in Slice 2). *)

open Alcotest
module Serve_policy = Miaou_serve.Serve_policy

module Stub_page : Miaou_core.Tui_page.PAGE_SIG = struct
  type state = unit

  type key_binding = state Miaou_core.Tui_page.key_binding_desc

  type pstate = state Miaou_core.Navigation.t

  type msg = unit

  let init () = Miaou_core.Navigation.make ()

  let update ps _ = ps

  let view _ps ~focus:_ ~size:_ = "stub"

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

let page : (module Miaou_core.Tui_page.PAGE_SIG) = (module Stub_page)

let test_refuses_public_bind_without_auth () =
  let raised = ref false in
  (try Miaou_serve.run ~bind:"0.0.0.0" ~port:0 page
   with Miaou_serve.Bind_refused _ -> raised := true) ;
  check bool "Bind_refused raised before any socket opens" true !raised

let test_loopback_allowed_without_auth () =
  match
    Serve_policy.check
      ~bind:"127.0.0.1"
      ~has_auth:false
      ~insecure_allow_plaintext_external:false
  with
  | Ok () -> ()
  | Error r -> fail (Serve_policy.refusal_message r)

let test_insecure_override_allows_public_bind () =
  match
    Serve_policy.check
      ~bind:"0.0.0.0"
      ~has_auth:false
      ~insecure_allow_plaintext_external:true
  with
  | Ok () -> ()
  | Error r -> fail (Serve_policy.refusal_message r)

let test_auth_allows_public_bind () =
  match
    Serve_policy.check
      ~bind:"0.0.0.0"
      ~has_auth:true
      ~insecure_allow_plaintext_external:false
  with
  | Ok () -> ()
  | Error r -> fail (Serve_policy.refusal_message r)

let () =
  run
    "serve_auth_default"
    [
      ( "fail-closed",
        [
          test_case
            "refuses public bind, no auth"
            `Quick
            test_refuses_public_bind_without_auth;
          test_case
            "allows loopback, no auth"
            `Quick
            test_loopback_allowed_without_auth;
          test_case
            "insecure flag allows public bind"
            `Quick
            test_insecure_override_allows_public_bind;
          test_case
            "auth token allows public bind"
            `Quick
            test_auth_allows_public_bind;
        ] );
    ]
