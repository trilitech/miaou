(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(** Configuration for the Matrix driver.

    Settings can be configured via environment variables:
    - MIAOU_MATRIX_FPS: Frame rate cap for rendering (default: 60)
    - MIAOU_MATRIX_TPS: Tick rate for effects/input (default: 60)
    - MIAOU_MATRIX_SCRUB_FRAMES: Full redraw interval in frames
      (default: 30, set 0 to disable)
    - MIAOU_MATRIX_DEBUG: Enable debug logging (default: false)
    - MIAOU_ENABLE_MOUSE: Enable mouse tracking (default: true, set to 0/false/no to disable for easier copy/paste)
    - MIAOU_INLINE_MODE: Run inline (no alt-screen). The TUI renders over
      the current terminal contents and its final frame stays in scrollback
      after exit. Mouse tracking is forced off in this mode for sane
      copy/paste. Default: false. Set to 1/true/yes to enable.
*)

type t = {
  fps_cap : int;  (** Maximum frames per second for render domain (1-120) *)
  frame_time_ms : float;  (** Minimum time between frames in ms *)
  tps_cap : int;  (** Maximum ticks per second for effects domain (1-120) *)
  tick_time_ms : float;  (** Minimum time between ticks in ms *)
  scrub_interval_frames : int;
      (** Perform a full clear+redraw every N frames (0 disables) *)
  debug : bool;  (** Enable debug logging *)
  enable_mouse : bool;
      (** Enable mouse tracking (set to false for easier copy/paste) *)
  handle_sigint : bool;
      (** If false, SIGINT (Ctrl+C) is not intercepted, allowing the app
          to receive it as a key event. Default: true *)
  inline_mode : bool;
      (** When true, the matrix driver skips the alternate-screen sequences.
          The TUI renders over the current terminal contents and its final
          frame stays in scrollback after exit. Mouse tracking is suppressed.
          Default: false. *)
}

(** Default configuration: 60 FPS, 60 TPS, no debug. *)
val default : t

(** Load configuration from environment variables. *)
val load : unit -> t

(** Minimum time in ms for given rate. *)
val time_of_rate : int -> float

(** Create a custom config with mouse tracking disabled.
    Useful for applications that want to allow terminal copy/paste. *)
val with_mouse_disabled : t -> t
