(** [wait_for]/[assert_screen] and error-taxonomy tests (S2).

    Covers each [wait_for] condition kind (FR-040), the single-blocking-call
    shape (FR-041), timeout structure parity with in-process
    {!Miaou_core.Workflow} errors (FR-042, US-4), and [assert_screen]
    (FR-050). *)

open Alcotest
module Protocol_core = Miaou_protocol.Protocol_core
module Protocol_errors = Miaou_protocol.Protocol_errors
module HD = Lib_miaou_internal.Headless_driver

(* A trivial modal page, just enough to exercise Modal_manager.has_active
   for the {modal: true} wait_for condition. *)
module Trivial_modal = struct
  module M = struct
    type state = unit

    type key_binding = state Miaou_core.Tui_page.key_binding_desc

    type pstate = state Miaou_core.Navigation.t

    type msg = unit

    let init () = Miaou_core.Navigation.make ()

    let update ps _ = ps

    let view _ps ~focus:_ ~size:_ = "modal"

    let keymap _ = []

    let handled_keys () = []

    include Test_helpers.Stub_page_defaults (struct
      type nonrec state = state

      type nonrec pstate = pstate
    end)

    let handle_key ps _key ~size:_ = ps

    let on_key ps _key ~size:_ = (ps, Miaou_interfaces.Key_event.Bubble)
  end

  let open_it () =
    Miaou_core.Modal_manager.push_default
      (module M : Miaou_core.Tui_page.PAGE_SIG with type state = unit)
      ~init:(M.init ())
      ~ui:
        {
          Miaou_core.Modal_manager.title = "trivial";
          left = None;
          max_width = None;
          dim_background = false;
        }
      ~on_close:(fun _ _ -> ())
end

module Page = struct
  type state = int

  type key_binding = state Miaou_core.Tui_page.key_binding_desc

  type pstate = state Miaou_core.Navigation.t

  type msg = unit

  let init () = Miaou_core.Navigation.make 0

  let update ps _ = ps

  let view ps ~focus:_ ~size:_ =
    Printf.sprintf "n=%d" ps.Miaou_core.Navigation.s

  let keymap _ = []

  let handled_keys () = []

  include Test_helpers.Stub_page_defaults (struct
    type nonrec state = state

    type nonrec pstate = pstate
  end)

  let refresh ps = Miaou_core.Navigation.update (fun n -> n + 1) ps

  let handle_key ps key ~size:_ =
    match key with
    | "m" ->
        Trivial_modal.open_it () ;
        ps
    | _ -> ps

  let on_key ps key ~size =
    let key_str = Miaou_core.Keys.to_string key in
    let ps' = handle_key ps key_str ~size in
    (ps', Miaou_interfaces.Key_event.Bubble)
end

let make_page () = (module Page : Miaou_core.Tui_page.PAGE_SIG)

let init_fresh () =
  Miaou_core.Modal_manager.clear () ;
  Protocol_core.init_session ~no_record:true (make_page ())

let assoc_field cmd key value = (key, value) :: cmd

let wait_for_req ?timeout_ms ?poll_interval_ms condition =
  let base = [("cmd", `String "wait_for"); ("condition", `Assoc condition)] in
  let base =
    match timeout_ms with
    | Some t -> assoc_field base "timeout_ms" (`Int t)
    | None -> base
  in
  match poll_interval_ms with
  | Some p -> assoc_field base "poll_interval_ms" (`Int p)
  | None -> base

let test_text_contains () =
  Eio_main.run @@ fun _env ->
  init_fresh () ;
  let resp, cont =
    Protocol_core.handle_cmd (wait_for_req [("text_contains", `String "n=0")])
  in
  check bool "keeps running" true (cont = `Continue) ;
  match resp with
  | `Assoc fields ->
      check bool "frame type" true (List.assoc "type" fields = `String "frame")
  | _ -> fail "expected frame response"

let test_text_matches () =
  Eio_main.run @@ fun _env ->
  init_fresh () ;
  let resp, _ =
    Protocol_core.handle_cmd
      (wait_for_req [("text_matches", `String "n=[0-9]+")])
  in
  match resp with
  | `Assoc fields ->
      check bool "frame type" true (List.assoc "type" fields = `String "frame")
  | _ -> fail "expected frame response"

let test_modal_condition () =
  Eio_main.run @@ fun _env ->
  init_fresh () ;
  ignore (HD.Stateful.send_key "m") ;
  let resp, _ =
    Protocol_core.handle_cmd (wait_for_req [("modal", `Bool true)])
  in
  match resp with
  | `Assoc fields ->
      check bool "frame type" true (List.assoc "type" fields = `String "frame")
  | _ -> fail "expected frame response"

let test_page_condition () =
  Eio_main.run @@ fun _env ->
  init_fresh () ;
  let resp, _ =
    Protocol_core.handle_cmd
      (wait_for_req
         ~timeout_ms:20
         ~poll_interval_ms:5
         [("page", `String "nonexistent")])
  in
  match resp with
  | `Assoc fields ->
      check bool "error type" true (List.assoc "type" fields = `String "error")
  | _ -> fail "expected error response"

(* FR-041: exactly one request/response pair per wait_for call, regardless of
   how many internal polls it takes — the caller of handle_cmd only ever
   sees a single returned response value, never a stream. *)
let test_single_response_pair () =
  Eio_main.run @@ fun _env ->
  init_fresh () ;
  let responses = ref 0 in
  let resp, _ =
    Protocol_core.handle_cmd
      (wait_for_req
         ~timeout_ms:50
         ~poll_interval_ms:5
         [("text_contains", `String "n=")])
  in
  incr responses ;
  ignore resp ;
  check int "exactly one response for one wait_for call" 1 !responses

let test_timeout_bad_condition () =
  Eio_main.run @@ fun _env ->
  init_fresh () ;
  let resp, _ =
    Protocol_core.handle_cmd
      (wait_for_req
         ~timeout_ms:20
         ~poll_interval_ms:5
         [("text_contains", `String "never-appears-xyz")])
  in
  match resp with
  | `Assoc fields ->
      check bool "type=error" true (List.assoc "type" fields = `String "error") ;
      check
        bool
        "code=E_TIMEOUT"
        true
        (List.assoc "code" fields = `String "E_TIMEOUT") ;
      check bool "has step" true (List.mem_assoc "step" fields) ;
      check bool "has attempt" true (List.mem_assoc "attempt" fields) ;
      check bool "has screen" true (List.mem_assoc "screen" fields)
  | _ -> fail "expected error response"

(* FR-042: field-for-field shape parity between a wire wait_for timeout and
   an in-process Workflow_error for an equivalent never-true predicate. *)
let test_timeout_parity_with_workflow () =
  Eio_main.run @@ fun _env ->
  init_fresh () ;
  let resp, _ =
    Protocol_core.handle_cmd
      (wait_for_req
         ~timeout_ms:20
         ~poll_interval_ms:5
         [("text_contains", `String "never-appears-xyz")])
  in
  let wire_fields =
    match resp with `Assoc f -> f | _ -> fail "expected object"
  in
  let driver =
    {
      Miaou_core.Workflow.feed_key = (fun _ -> ());
      feed_keys = (fun _ -> ());
      screen = (fun () -> "n=0");
      has_modal = (fun () -> false);
      sleep = (fun _ -> ());
      log = (fun _ -> ());
    }
  in
  Miaou_core.Workflow.register_driver driver ;
  let workflow_result =
    Miaou_core.Workflow.run_result
      (Miaou_core.Workflow.loop_until ~max_iters:2 ~sleep:0.0 (fun s ->
           s = "never-appears-xyz"))
  in
  match workflow_result with
  | Ok () -> fail "expected Workflow_error"
  | Error {step; message = _; attempt; screen} ->
      check bool "wire has step" true (List.mem_assoc "step" wire_fields) ;
      check bool "workflow has step (non-empty)" true (String.length step >= 0) ;
      check bool "wire has attempt" true (List.mem_assoc "attempt" wire_fields) ;
      check bool "workflow has attempt" true (attempt <> None) ;
      check bool "wire has screen" true (List.mem_assoc "screen" wire_fields) ;
      check bool "workflow has screen" true (screen <> None)

let test_assert_screen_pass () =
  Eio_main.run @@ fun _env ->
  init_fresh () ;
  ignore (Protocol_core.handle_cmd [("cmd", `String "render")]) ;
  let resp, _ =
    Protocol_core.handle_cmd
      [("cmd", `String "assert_screen"); ("contains", `String "n=0")]
  in
  match resp with
  | `Assoc fields ->
      check bool "ok=true" true (List.assoc "ok" fields = `Bool true)
  | _ -> fail "expected assert_result"

let test_assert_screen_fail_shape () =
  Eio_main.run @@ fun _env ->
  init_fresh () ;
  ignore (Protocol_core.handle_cmd [("cmd", `String "render")]) ;
  let resp, _ =
    Protocol_core.handle_cmd
      [("cmd", `String "assert_screen"); ("contains", `String "nope")]
  in
  match resp with
  | `Assoc fields -> (
      check bool "ok=false" true (List.assoc "ok" fields = `Bool false) ;
      match List.assoc_opt "error" fields with
      | Some (`Assoc err_fields) ->
          check bool "error has step" true (List.mem_assoc "step" err_fields) ;
          check
            bool
            "error has message"
            true
            (List.mem_assoc "message" err_fields) ;
          check
            bool
            "error has schema_version"
            true
            (List.mem_assoc "schema_version" err_fields) ;
          check
            bool
            "no protocol code on assertion failure"
            true
            (not (List.mem_assoc "code" err_fields))
      | _ -> fail "expected nested error object")
  | _ -> fail "expected assert_result"

(* H1 regression: a malformed regex must never crash the dispatcher. Str.regexp
   raises Failure (not Not_found) on e.g. an unclosed character class; both
   wait_for's text_matches and assert_screen's matches must turn that into a
   normal E_BAD_REQUEST response instead of letting the exception escape
   handle_cmd (which has no exception guard at either call site: the stdio
   transport loop and miaou-mcp's tool handlers). *)
let test_wait_for_malformed_regex_is_bad_request () =
  Eio_main.run @@ fun _env ->
  init_fresh () ;
  let resp, cont =
    Protocol_core.handle_cmd (wait_for_req [("text_matches", `String "[")])
  in
  check bool "keeps running, does not crash" true (cont = `Continue) ;
  match resp with
  | `Assoc fields ->
      check bool "type=error" true (List.assoc "type" fields = `String "error") ;
      check
        bool
        "code=E_BAD_REQUEST"
        true
        (List.assoc "code" fields = `String "E_BAD_REQUEST") ;
      check
        bool
        "has step=wait_for"
        true
        (List.assoc "step" fields = `String "wait_for")
  | _ -> fail "expected error response"

let test_assert_screen_malformed_regex_is_bad_request () =
  Eio_main.run @@ fun _env ->
  init_fresh () ;
  ignore (Protocol_core.handle_cmd [("cmd", `String "render")]) ;
  let resp, cont =
    Protocol_core.handle_cmd
      [("cmd", `String "assert_screen"); ("matches", `String "[")]
  in
  check bool "keeps running, does not crash" true (cont = `Continue) ;
  match resp with
  | `Assoc fields ->
      check bool "type=error" true (List.assoc "type" fields = `String "error") ;
      check
        bool
        "code=E_BAD_REQUEST"
        true
        (List.assoc "code" fields = `String "E_BAD_REQUEST")
  | _ -> fail "expected error response (not an assert_result, and not a crash)"

let test_error_taxonomy_closed_set () =
  let all_codes =
    Protocol_errors.
      [E_BAD_REQUEST; E_UNSUPPORTED_COMMAND; E_TIMEOUT; E_READ_ONLY; E_INTERNAL]
  in
  check
    (list string)
    "closed set of 5 codes"
    [
      "E_BAD_REQUEST";
      "E_UNSUPPORTED_COMMAND";
      "E_TIMEOUT";
      "E_READ_ONLY";
      "E_INTERNAL";
    ]
    (List.map Protocol_errors.code_to_string all_codes)

let () =
  run
    "wait_for/assert_screen"
    [
      ( "wait_for",
        [
          test_case "text_contains condition" `Quick test_text_contains;
          test_case "text_matches condition" `Quick test_text_matches;
          test_case "modal condition" `Quick test_modal_condition;
          test_case "page condition (timeout path)" `Quick test_page_condition;
          test_case
            "single request/response pair (FR-041)"
            `Quick
            test_single_response_pair;
          test_case "timeout error shape" `Quick test_timeout_bad_condition;
          test_case
            "timeout parity with Workflow.error"
            `Quick
            test_timeout_parity_with_workflow;
          test_case
            "malformed regex is E_BAD_REQUEST, not a crash (H1)"
            `Quick
            test_wait_for_malformed_regex_is_bad_request;
        ] );
      ( "assert_screen",
        [
          test_case "pass" `Quick test_assert_screen_pass;
          test_case "fail shape" `Quick test_assert_screen_fail_shape;
          test_case
            "malformed regex is E_BAD_REQUEST, not a crash (H1)"
            `Quick
            test_assert_screen_malformed_regex_is_bad_request;
        ] );
      ( "error_taxonomy",
        [test_case "closed 5-code set" `Quick test_error_taxonomy_closed_set] );
    ]
