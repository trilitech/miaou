(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(** [miaou serve] CLI surface (FR-001).

    Flag parsing is exposed separately from process-exiting evaluation so
    it can be unit-tested as a pure round-trip ([argv -> config]) without
    invoking cmdliner's process-exit behavior. *)

(** [parse_argv argv] parses [argv] (including [argv.(0)], the program
    name, exactly like {!Sys.argv}) as [miaou serve <flags>] and returns
    the resulting {!Serve_config.t}, or [Error msg] if parsing failed
    (including [--help]/[--version], which cmdliner treats as
    "successful but nothing to run" — callers that need the raw
    exit-code behavior should use {!cmd} with {!Cmdliner.Cmd.eval}
    instead). *)
val parse_argv : string array -> (Serve_config.t, string) result

(** The [serve] subcommand as a [unit] cmdliner command: resolves
    [--app] via {!Miaou_core.Registry.find} and, if found, calls
    {!Miaou_serve.run}; otherwise prints an error and does not start a
    server. Exposed so a host binary can register it under a top-level
    [miaou] command group ([Cmdliner.Cmd.group]). *)
val cmd : unit Cmdliner.Cmd.t
