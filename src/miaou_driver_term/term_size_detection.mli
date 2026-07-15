(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(** Terminal size detection for the lambda-term driver — thin wrapper
    around {!Miaou_driver_common.Terminal_raw}'s cached size query, adapted
    to [LTerm_geom.size].

    Operates on the single session handle the driver already owns (see
    {!Term_terminal_setup.setup_and_cleanup}) rather than opening a second
    [/dev/tty] handle of its own, so there is exactly one size cache per
    session and one place to invalidate it on SIGWINCH. *)

(** Query the current terminal size, using the session's cache.
    Call {!invalidate_cache} on SIGWINCH to pick up terminal resize. *)
val detect_size : Miaou_driver_common.Terminal_raw.t -> LTerm_geom.size

(** Invalidate the session's cached terminal size. Call this on SIGWINCH. *)
val invalidate_cache : Miaou_driver_common.Terminal_raw.t -> unit
