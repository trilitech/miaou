(** Golden-transcript replay test (S1, FR-100).

    Replays the exact request script used to record
    [golden/baseline_v1.jsonl] (`render`/`key`/`tick`/`resize`/malformed-JSON/
    unknown-command/`quit` against the gallery launcher) through the
    extracted {!Miaou_protocol.Protocol_core} dispatcher, and asserts every
    baseline response's fields are still present with the same values —
    only *additive* keys (`schema_version`, `code`, `step`, ...) may appear
    that weren't in the original recording. This is the backward-compat
    guard for FR-001/FR-002/FR-003/FR-100: a v1-only client that never looks
    at the new fields keeps working unmodified. *)

open Alcotest

let golden_path = "golden/baseline_v1.jsonl"

let requests =
  [
    `Line "{\"cmd\":\"render\"}";
    `Line "{\"cmd\":\"key\",\"key\":\"Down\"}";
    `Line "{\"cmd\":\"tick\",\"n\":2}";
    `Line "{\"cmd\":\"resize\",\"rows\":30,\"cols\":100}";
    `Line "not json";
    `Line "{\"cmd\":\"bogus\"}";
    `Line "{\"cmd\":\"quit\"}";
  ]

(* Mirrors the transport-level (not Protocol_core) handling of a raw stdio
   line in Headless_json_runner.run: JSON parsing happens in the stdio shim,
   before Protocol_core.handle_cmd is ever reached. *)
let dispatch_one (`Line line) =
  match Yojson.Safe.from_string line with
  | exception Yojson.Json_error msg ->
      `Assoc
        [
          ("type", `String "error");
          ("message", `String ("JSON parse error: " ^ msg));
        ]
  | `Assoc pairs -> fst (Miaou_protocol.Protocol_core.handle_cmd pairs)
  | _ ->
      `Assoc
        [
          ("type", `String "error");
          ("message", `String "Expected a JSON object");
        ]

(* [actual] must carry every (key, value) pair present in [baseline];
   extra keys in [actual] (schema_version, code, step, attempt, screen, ...)
   are the allowed additive surface and are ignored. *)
let assert_baseline_subset ~index baseline actual =
  match (baseline, actual) with
  | `Assoc base_fields, `Assoc actual_fields ->
      List.iter
        (fun (k, v) ->
          match List.assoc_opt k actual_fields with
          | None ->
              failf "response %d: baseline key %S missing from replay" index k
          | Some v' ->
              if not (Yojson.Safe.equal v v') then
                failf
                  "response %d: key %S changed (baseline %s, replay %s)"
                  index
                  k
                  (Yojson.Safe.to_string v)
                  (Yojson.Safe.to_string v'))
        base_fields
  | _ ->
      failf
        "response %d: expected both baseline and replay to be JSON objects"
        index

let test_replay () =
  let golden_lines =
    let ic = open_in golden_path in
    Fun.protect
      ~finally:(fun () -> close_in ic)
      (fun () ->
        let rec read acc =
          match input_line ic with
          | line -> read (line :: acc)
          | exception End_of_file -> List.rev acc
        in
        read [])
  in
  let golden = List.map Yojson.Safe.from_string golden_lines in
  check
    int
    "golden line count matches request script"
    (List.length requests)
    (List.length golden) ;
  Eio_main.run @@ fun env ->
  Eio.Switch.run @@ fun sw ->
  Miaou_helpers.Fiber_runtime.init ~env ~sw ;
  Demo_shared.Demo_config.register_mocks () ;
  Demo_shared.Demo_config.ensure_system_capability () ;
  let launcher_name = Demo_shared.Demo_config.launcher_page_name in
  let page : Miaou_core.Registry.page =
    (module Gallery.Launcher : Miaou_core.Tui_page.PAGE_SIG)
  in
  Miaou_core.Registry.register launcher_name page ;
  Miaou_protocol.Protocol_core.init_session ~no_record:true page ;
  List.iteri
    (fun i (req, base) ->
      let actual = dispatch_one req in
      assert_baseline_subset ~index:i base actual)
    (List.combine requests golden)

let () =
  run
    "protocol replay"
    [("baseline_v1", [test_case "backward-compat replay" `Quick test_replay])]
