(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(** Time-based animation primitives.

    This module provides a single {!type:t} value that tracks progress
    through an animation defined by a duration and an easing curve.
    The caller is responsible for feeding delta-time via {!tick};
    the module has no dependency on the framework clock.

    {b Typical usage with the Clock capability}:
    {[
      (* Create a 300 ms ease-out transition *)
      let anim = Animation.create ~duration:0.3 ~easing:Ease_out ()

      (* Each frame, advance by the clock delta *)
      let anim = Animation.tick anim ~dt:(clock.dt ())

      (* Read the eased progress (0.0 .. 1.0) *)
      let progress = Animation.lerp 30.0 80.0 anim   (* 30 → 80 *)
    ]}

    {b Repeating animations}:
    {[
      (* Continuous loop (e.g. spinner) *)
      let spin = Animation.create ~duration:1.0 ~repeat:Loop ()

      (* Ping-pong pulse (e.g. focus glow) *)
      let pulse = Animation.create ~duration:0.8
                    ~repeat:Ping_pong ~easing:Ease_in_out ()
    ]} *)

(** {1 Configuration} *)

(** Easing curve applied to the raw linear progress. *)
type easing =
  | Linear  (** Constant speed. *)
  | Ease_in  (** Slow start, accelerating (cubic). *)
  | Ease_out  (** Fast start, decelerating (cubic). *)
  | Ease_in_out  (** Slow start and end (cubic). *)
  | Bounce
      (** Overshoots to ~1.1 then settles back to 1.0.
          Useful for "pop" / impact effects in games. *)
  | Custom of (float -> float)
      (** User-supplied easing function.  Receives raw progress in
          [\[0, 1\]], should return the eased value (may exceed
          [\[0, 1\]] for overshoot effects). *)

(** What happens when the animation reaches the end of its duration. *)
type repeat =
  | Once  (** Stops at 1.0 and {!finished} returns [true]. *)
  | Loop  (** Wraps back to 0.0 and repeats indefinitely. *)
  | Ping_pong
      (** Reverses direction at each end, oscillating 0→1→0
          indefinitely. *)

(** {1 Animation value} *)

(** An opaque animation state. *)
type t

(** {1 Creation} *)

(** Create a new animation.

    @param duration Total duration in seconds (must be > 0).
    @param easing Easing curve (default: {!Linear}).
    @param repeat Repeat mode (default: {!Once}). *)
val create : duration:float -> ?easing:easing -> ?repeat:repeat -> unit -> t

(** {1 Updating} *)

(** Advance the animation by [dt] seconds.

    For {!Once} animations, progress is clamped to 1.0.
    For {!Loop}, it wraps around.  For {!Ping_pong}, it reverses. *)
val tick : t -> dt:float -> t

(** Reset the animation to the beginning (elapsed = 0). *)
val reset : t -> t

(** {1 Reading} *)

(** The current eased progress, in the range [\[0.0, 1.0\]]. *)
val value : t -> float

(** The raw (linear) progress before easing, in [\[0.0, 1.0\]]. *)
val raw : t -> float

(** [true] when a {!Once} animation has reached its full duration.
    Always [false] for {!Loop} and {!Ping_pong}. *)
val finished : t -> bool

(** Total elapsed time in seconds (may exceed [duration] for {!Once}). *)
val elapsed : t -> float

(** {1 Interpolation helpers} *)

(** [lerp a b anim] linearly interpolates between [a] and [b] using
    the eased {!value}.  Returns [a] when value is 0, [b] when 1. *)
val lerp : float -> float -> t -> float

(** Integer version of {!lerp} (result is rounded to nearest int). *)
val lerp_int : int -> int -> t -> int

(** {1 Combinators} *)

(** [delay seconds] creates an animation that stays at value 0.0 for
    [seconds], then finishes.  Useful for inserting pauses into a
    {!sequence}.

    @param seconds Delay duration (clamped to > 0). *)
val delay : float -> t

(** [sequence anims] chains a list of animations end-to-end.  The
    resulting animation's {!value} is that of whichever sub-animation
    is currently active.  {!finished} is [true] only when the last
    sub-animation finishes.

    An empty list produces an already-finished animation with value 0.

    {b Example} — flash, hold, then fade out:
    {[
      Animation.sequence [
        Animation.create ~duration:0.1 ~easing:Ease_out () ;  (* flash in *)
        Animation.delay 0.5 ;                                  (* hold *)
        Animation.create ~duration:0.3 ~easing:Ease_in () ;    (* fade out *)
      ]
    ]}

    Note: sub-animations should use [Once] repeat mode.  {!Loop} and
    {!Ping_pong} sub-animations never finish, so subsequent steps
    would never be reached. *)
val sequence : t list -> t
