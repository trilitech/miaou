(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Mathias Bourgoin <mathias.bourgoin@atacama.tech>        *)
(*                                                                            *)
(******************************************************************************)

(** Miaou widget registry.

    Widgets self-register at startup by calling {!register}. Tools such as the
    MCP server can then call {!list}, {!find}, or {!search} to discover widgets
    and their public API (embedded from the corresponding [.mli] file). *)

(** A registered widget entry. [name] is the short widget name (e.g. ["textbox"])
    and [mli] is the full contents of the widget's public interface file. *)
type entry = {name : string; mli : string}

(** [register ~name ~mli ()] adds or replaces the entry for [name]. Safe to call
    from module initialisation (thread-safe). *)
val register : name:string -> mli:string -> unit -> unit

(** Return all registered entries sorted by name. *)
val list : unit -> entry list

(** [find ~name] returns the entry for [name], or [None] if not registered. *)
val find : name:string -> entry option

(** [search ~query] returns all entries whose [name ^ " " ^ mli] contains
    [query] (case-insensitive substring match), sorted by name. *)
val search : query:string -> entry list
