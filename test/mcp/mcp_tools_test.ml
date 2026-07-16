(** [miaou-mcp] tool wiring and read-only enforcement (S4, FR-070–FR-076,
    FR-080–FR-081).

    Exercises {!Mcp_tools} directly (no external mcp-kit pin needed at
    runtime beyond what's already required to build this optional test),
    then drives a full {!Mcp_kit.Server.t} through a scripted JSON-RPC
    session over an in-process string transport to prove the wiring is
    correct end-to-end, without spawning the real binary (the tmux script
    covers that). *)

open Alcotest
module Protocol_core = Miaou_protocol.Protocol_core

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

  let handle_key ps key ~size:_ =
    if key = "Down" then Miaou_core.Navigation.update (fun n -> n + 1) ps
    else ps

  let on_key ps key ~size =
    let key_str = Miaou_core.Keys.to_string key in
    let ps' = handle_key ps key_str ~size in
    (ps', Miaou_interfaces.Key_event.Bubble)
end

let make_page () = (module Page : Miaou_core.Tui_page.PAGE_SIG)

let init_fresh () = Protocol_core.init_session ~no_record:true (make_page ())

(* FR-080's conformance fixture, and the M1 fix: derive the expected set
   from Protocol_core — the actual dispatcher — rather than from
   Mcp_tools.classification itself. A prior version of this test compared
   [classification] against [classification] (via [Mcp_tools.tools]'s own
   names), so a new mutating command added to Protocol_core.handle_cmd
   without a matching classification entry would be silently unreachable
   via MCP and this test would still pass. Now: every
   Protocol_core.dispatchable_commands entry, except the explicitly
   documented Protocol_core.deferred_commands, must appear in
   Mcp_tools.classification exactly once. *)
let test_classification_exhaustive () =
  let names = List.map fst Mcp_tools.classification in
  let unique = List.sort_uniq String.compare names in
  check
    int
    "no duplicate classification entries"
    (List.length names)
    (List.length unique) ;
  let expected =
    List.filter
      (fun cmd -> not (List.mem cmd Protocol_core.deferred_commands))
      Protocol_core.dispatchable_commands
  in
  check
    (list string)
    "classification == Protocol_core's dispatchable commands minus deferred \
     ones"
    (List.sort compare expected)
    (List.sort compare names) ;
  List.iter
    (fun read_only ->
      let tools = Mcp_tools.tools ~read_only in
      let tool_names = List.map Mcp_kit.Tool.name tools in
      check
        (list string)
        "registered tools == classification"
        (List.sort compare names)
        (List.sort compare tool_names))
    [true; false]

let test_read_only_stubs_every_mutating_tool () =
  Eio_main.run @@ fun _env ->
  init_fresh () ;
  let tools = Mcp_tools.tools ~read_only:true in
  List.iter
    (fun (name, kind) ->
      let tool = List.find (fun t -> Mcp_kit.Tool.name t = name) tools in
      let result = Mcp_kit.Tool.call tool (`Assoc []) in
      match kind with
      | `Mutating ->
          check
            bool
            (name ^ ": is_error under --read-only")
            true
            result.Mcp_kit.Tool.is_error ;
          let text =
            match result.Mcp_kit.Tool.content with
            | [Mcp_kit.Tool.Text t] -> t
            | _ -> fail (name ^ ": expected a single text content block")
          in
          check
            bool
            (name ^ ": carries E_READ_ONLY code")
            true
            (Test_helpers.contains_substring text "E_READ_ONLY")
      | `Read_only -> ())
    Mcp_tools.classification

let test_read_only_tools_still_work_under_read_only () =
  Eio_main.run @@ fun _env ->
  init_fresh () ;
  let tools = Mcp_tools.tools ~read_only:true in
  let render = List.find (fun t -> Mcp_kit.Tool.name t = "render") tools in
  let result = Mcp_kit.Tool.call render (`Assoc []) in
  check
    bool
    "render is not an error under --read-only"
    false
    result.Mcp_kit.Tool.is_error

let make_test_server ~read_only =
  let server = Mcp_kit.Server.create ~name:"miaou-mcp-test" ~version:"1.0" () in
  match Mcp_kit.Server.add_tools server (Mcp_tools.tools ~read_only) with
  | Ok server -> server
  | Error _ -> fail "unexpected duplicate tool in test server"

let session_call session json =
  match Mcp_kit.Server.dispatch_session_json session json with
  | Some resp -> resp
  | None -> fail "expected a response, got a notification-style None"

let test_stdio_session_end_to_end () =
  Eio_main.run @@ fun _env ->
  init_fresh () ;
  let server = make_test_server ~read_only:false in
  let session = Mcp_kit.Server.create_session server in
  let init_resp =
    session_call
      session
      (`Assoc
         [
           ("jsonrpc", `String "2.0");
           ("id", `Int 1);
           ("method", `String "initialize");
           ( "params",
             `Assoc
               [
                 ("protocolVersion", `String "2024-11-05");
                 ("capabilities", `Assoc []);
                 ( "clientInfo",
                   `Assoc [("name", `String "test"); ("version", `String "0")]
                 );
               ] );
         ])
  in
  check
    bool
    "initialize returns a result"
    true
    (Yojson.Safe.Util.member "result" init_resp <> `Null) ;
  ignore
    (Mcp_kit.Server.dispatch_session_json
       session
       (`Assoc
          [
            ("jsonrpc", `String "2.0");
            ("method", `String "notifications/initialized");
          ])) ;
  let render_resp =
    session_call
      session
      (`Assoc
         [
           ("jsonrpc", `String "2.0");
           ("id", `Int 2);
           ("method", `String "tools/call");
           ( "params",
             `Assoc [("name", `String "render"); ("arguments", `Assoc [])] );
         ])
  in
  let result = Yojson.Safe.Util.member "result" render_resp in
  check bool "tools/call render returns a result" true (result <> `Null) ;
  let is_error = Yojson.Safe.Util.member "isError" result in
  check bool "render is not an error" true (is_error = `Bool false) ;
  let key_resp =
    session_call
      session
      (`Assoc
         [
           ("jsonrpc", `String "2.0");
           ("id", `Int 3);
           ("method", `String "tools/call");
           ( "params",
             `Assoc
               [
                 ("name", `String "key");
                 ("arguments", `Assoc [("key", `String "Down")]);
               ] );
         ])
  in
  let key_result = Yojson.Safe.Util.member "result" key_resp in
  let content = Yojson.Safe.Util.member "content" key_result in
  let text =
    match content with
    | `List [item] ->
        Yojson.Safe.Util.to_string (Yojson.Safe.Util.member "text" item)
    | _ -> fail "expected a single content block"
  in
  check
    bool
    "key response reflects the moved cursor"
    true
    (Test_helpers.contains_substring text "n=1")

let () =
  run
    "miaou-mcp"
    [
      ( "classification",
        [
          test_case
            "exhaustive over all registered tools"
            `Quick
            test_classification_exhaustive;
          test_case
            "every mutating tool stubs under --read-only"
            `Quick
            test_read_only_stubs_every_mutating_tool;
          test_case
            "read-only tools still work under --read-only"
            `Quick
            test_read_only_tools_still_work_under_read_only;
        ] );
      ( "stdio_session",
        [
          test_case
            "initialize -> tools/call end to end"
            `Quick
            test_stdio_session_end_to_end;
        ] );
    ]
