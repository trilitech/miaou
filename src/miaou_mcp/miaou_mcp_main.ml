(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Mathias Bourgoin <mathias.bourgoin@atacama.tech>        *)
(*                                                                            *)
(******************************************************************************)

(** [miaou-mcp]: MCP server exposing the MIAOU agent protocol over stdio
    (FR-070–FR-076). Runs the gallery launcher demo — the same fixture used
    by the conformance suite (S5) — as its driven page.

    Flags: [--read-only] (FR-080: mutating tools become E_READ_ONLY stubs at
    registration time, not a list-time-only gate) and [--no-record]
    (FR-061). *)

module Protocol_core = Miaou_protocol.Protocol_core
module Protocol_version = Miaou_protocol.Protocol_version

let has_flag name = Array.exists (fun a -> a = name) Sys.argv

let () =
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
  let read_only = has_flag "--read-only" in
  Protocol_core.init_session ~no_record:(has_flag "--no-record") page ;
  let server =
    Mcp_kit.Server.create ~name:"miaou-mcp" ~version:Protocol_version.current ()
  in
  let server =
    match Mcp_kit.Server.add_tools server (Mcp_tools.tools ~read_only) with
    | Ok server -> server
    | Error (Mcp_kit.Server.Duplicate_tool name) ->
        Printf.eprintf "[miaou-mcp] duplicate tool registration: %s\n%!" name ;
        exit 1
    | Error (Mcp_kit.Server.Duplicate_resource name) ->
        Printf.eprintf
          "[miaou-mcp] duplicate resource registration: %s\n%!"
          name ;
        exit 1
    | Error (Mcp_kit.Server.Duplicate_prompt name) ->
        Printf.eprintf "[miaou-mcp] duplicate prompt registration: %s\n%!" name ;
        exit 1
  in
  let resources =
    Mcp_tools.resources
      ~page_names:(Miaou_core.Registry.list_names ())
      ~protocol_version:Protocol_version.current
  in
  let server =
    match Mcp_kit.Server.add_resources server resources with
    | Ok server -> server
    | Error (Mcp_kit.Server.Duplicate_tool name) ->
        Printf.eprintf "[miaou-mcp] duplicate tool registration: %s\n%!" name ;
        exit 1
    | Error (Mcp_kit.Server.Duplicate_resource name) ->
        Printf.eprintf
          "[miaou-mcp] duplicate resource registration: %s\n%!"
          name ;
        exit 1
    | Error (Mcp_kit.Server.Duplicate_prompt name) ->
        Printf.eprintf "[miaou-mcp] duplicate prompt registration: %s\n%!" name ;
        exit 1
  in
  Mcp_kit_stdio.run_channels server stdin stdout ;
  exit 0
