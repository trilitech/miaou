(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Mathias Bourgoin <mathias.bourgoin@atacama.tech>        *)
(*                                                                            *)
(******************************************************************************)

module Protocol_core = Miaou_protocol.Protocol_core
module Protocol_errors = Miaou_protocol.Protocol_errors
module Protocol_version = Miaou_protocol.Protocol_version

let classification =
  [
    ("render", `Read_only);
    ("wait_for", `Read_only);
    ("assert_screen", `Read_only);
    ("key", `Mutating);
    ("tick", `Mutating);
    ("resize", `Mutating);
    ("quit", `Mutating);
  ]

(* Every tool's [arguments] object is merged verbatim onto [("cmd", name)] and
   handed to Protocol_core.handle_cmd — the same assoc-list shape the
   JSON-over-stdio transport builds by parsing a request line. This keeps
   the two transports' command semantics identical by construction: neither
   duplicates per-command argument plumbing. *)
let args_fields (args : Yojson.Safe.t) : (string * Yojson.Safe.t) list =
  match args with `Assoc fields -> fields | _ -> []

let dispatch name (args : Yojson.Safe.t) : Yojson.Safe.t =
  fst (Protocol_core.handle_cmd (("cmd", `String name) :: args_fields args))

let is_error_response (resp : Yojson.Safe.t) : bool =
  match resp with
  | `Assoc fields -> List.assoc_opt "type" fields = Some (`String "error")
  | _ -> false

let to_result (resp : Yojson.Safe.t) : Mcp_kit.Tool.result =
  {
    Mcp_kit.Tool.content = [Mcp_kit.Tool.Text (Yojson.Safe.to_string resp)];
    is_error = is_error_response resp;
    structured_content = Some resp;
  }

let read_only_stub_result ~step : Mcp_kit.Tool.result =
  let resp =
    Protocol_errors.to_yojson
      ~schema_version:Protocol_version.current
      (Protocol_errors.make
         ~code:Protocol_errors.E_READ_ONLY
         ~step
         "mutating action rejected: server is running with --read-only")
  in
  {
    Mcp_kit.Tool.content = [Mcp_kit.Tool.Text (Yojson.Safe.to_string resp)];
    is_error = true;
    structured_content = Some resp;
  }

let make_tool ~read_only (name, kind) : Mcp_kit.Tool.t =
  let handler args =
    match (kind, read_only) with
    | `Mutating, true -> Ok (read_only_stub_result ~step:name)
    | (`Mutating | `Read_only), _ -> Ok (to_result (dispatch name args))
  in
  Mcp_kit.Tool.make name handler

let tools ~read_only = List.map (make_tool ~read_only) classification

let resources ~page_names ~protocol_version =
  [
    Mcp_kit.Resource.make
      ~uri:"miaou://pages"
      ~name:"pages"
      ~mime_type:"application/json"
      [
        Mcp_kit.Resource.Text
          {
            uri = "miaou://pages";
            mime_type = Some "application/json";
            text =
              Yojson.Safe.to_string
                (`List (List.map (fun n -> `String n) page_names));
          };
      ];
    Mcp_kit.Resource.make
      ~uri:"miaou://protocol/version"
      ~name:"protocol_version"
      ~mime_type:"application/json"
      [
        Mcp_kit.Resource.Text
          {
            uri = "miaou://protocol/version";
            mime_type = Some "application/json";
            text =
              Yojson.Safe.to_string
                (`Assoc [("schema_version", `String protocol_version)]);
          };
      ];
  ]
