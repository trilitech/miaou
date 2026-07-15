(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

(** Shared "terminal too narrow" (< 80 columns) warning, used by every
    terminal-rendering driver.

    Two things happen while the terminal is narrow:
    - a small header banner is rendered on every frame ({!header_lines});
    - a one-time dismissible modal is pushed the first time a frame renders
      narrow ({!maybe_warn}), auto-dismissed after 5s or on any key.

    State ([t]) is per driver session — {b never} a process-wide global.
    Two driver backends (or two sessions of the same backend, e.g. under
    test) must not share a single "have I warned yet" flag. *)

type t

(** Fresh per-session state: not yet warned. *)
val create : unit -> t

(** Header lines to prepend to a frame when [cols < 80]; empty otherwise.
    Pure — does not read or mutate session state. *)
val header_lines : cols:int -> string list

(** Called once per render tick with the frame's current column count.
    The first time [cols < 80] is observed for this session, pushes the
    one-time "Narrow terminal" modal (auto-dismissed after 5s, or sooner on
    any key) and marks the session as warned so it never fires again. *)
val maybe_warn : t -> cols:int -> unit
