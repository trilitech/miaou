(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(** Turn recording on by default for a protocol session (FR-060), unless
    [MIAOU_NO_RECORD] is truthy (in which case this is a no-op — the explicit
    opt-out wins). Has no effect once a writer has already been resolved
    (Active or Disabled) for a given stream, since the writer decision
    freezes at first record; call this before the first frame/keystroke of
    the session. Does not override an explicit
    [MIAOU_DEBUG_KEYSTROKE_CAPTURE]/[MIAOU_DEBUG_FRAME_CAPTURE] setting of
    ["0"]/["false"] — those still win via {!val:record_keystroke}/
    {!val:record_frame}'s existing env lookup. *)
val force_enable : unit -> unit

(** Explicit opt-out (FR-061, e.g. [--no-record]). Recording stays disabled
    for the remainder of the process regardless of {!force_enable}. *)
val disable : unit -> unit

(** Append a keystroke event to the capture stream when enabled. *)
val record_keystroke : string -> unit

(** Append a rendered frame snapshot to the capture stream when enabled. [rows]
    and [cols] describe the geometry used for [frame]. *)
val record_frame : rows:int -> cols:int -> string -> unit

(** Close capture writers so tests can run with different environment settings.
    This is primarily intended for the test suite. *)
val reset_for_tests : unit -> unit
