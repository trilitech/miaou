(** Guards docs/agent-protocol.md's version header against drifting from
    the actual protocol version (S5). The doc carries a machine-readable
    [<!-- protocol_version: X.Y -->] marker near its top; this test extracts
    it and asserts it equals {!Miaou_protocol.Protocol_version.current}. *)

open Alcotest

let doc_path = "../../docs/agent-protocol.md"

let marker_prefix = "<!-- protocol_version: "

let extract_version path =
  let ic = open_in path in
  Fun.protect
    ~finally:(fun () -> close_in ic)
    (fun () ->
      let rec scan () =
        match input_line ic with
        | line -> (
            match
              if
                String.length line >= String.length marker_prefix
                && String.sub line 0 (String.length marker_prefix)
                   = marker_prefix
              then Some line
              else None
            with
            | Some line ->
                let rest =
                  String.sub
                    line
                    (String.length marker_prefix)
                    (String.length line - String.length marker_prefix)
                in
                let end_idx = String.index rest ' ' in
                Some (String.sub rest 0 end_idx)
            | None -> scan ())
        | exception End_of_file -> None
      in
      scan ())

let test_doc_version_matches_protocol_version () =
  match extract_version doc_path with
  | None ->
      fail
        "docs/agent-protocol.md is missing its <!-- protocol_version: X.Y --> \
         marker"
  | Some v ->
      check
        string
        "doc version header matches Protocol_version.current"
        Miaou_protocol.Protocol_version.current
        v

let () =
  run
    "docs version"
    [
      ( "agent-protocol.md",
        [
          test_case
            "version header matches Protocol_version.current"
            `Quick
            test_doc_version_matches_protocol_version;
        ] );
    ]
