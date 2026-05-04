(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(** Helpers shared across the gallery's arcade-style demos.

    All sub-modules are designed for tight game loops:
    - no per-frame allocation in the hot paths
    - 256-colour palettes hand-snapped to the xterm cube to avoid the banding
      that hits "smooth" RGB gradients on Octant render mode
    - persistent high score helper so the "one more try" loop pays off across
      sessions *)

(** {1 Particles} *)

module Particles : sig
  type t

  (** Pre-allocate a particle pool of [capacity] entries. No allocations
      happen in [tick] or [spawn]. [capacity] should be a hard upper bound
      on the simultaneous particle count; older particles are recycled when
      the pool fills. *)
  val create : capacity:int -> t

  val clear : t -> unit

  val alive_count : t -> int

  (** Emit one particle. [hue] is a key into a palette ramp (0..n-1). *)
  val spawn :
    t ->
    x:float ->
    y:float ->
    vx:float ->
    vy:float ->
    life:float ->
    hue:int ->
    unit

  (** Emit [n] particles in a uniform radial burst around [(x, y)] with
      randomised speeds in [0.3·speed .. speed] and a small life jitter. *)
  val spawn_burst :
    t ->
    x:float ->
    y:float ->
    n:int ->
    speed:float ->
    life:float ->
    hue:int ->
    rng:Random.State.t ->
    unit

  (** Advance the simulation by [dt] seconds. [(ax, ay)] is a constant
      acceleration applied each frame (gravity, wind, drag…). *)
  val tick : t -> dt:float -> ax:float -> ay:float -> unit

  (** Visit each live particle. [life01] is remaining life as a 0..1
      fraction so callers can fade alpha / size. *)
  val iter :
    t -> f:(x:float -> y:float -> life01:float -> hue:int -> unit) -> unit
end

(** {1 Hue ramps} *)

module Hue : sig
  (** Each entry is a ready-to-use SGR foreground payload, e.g. ["38;5;214"].
      Indexed 0 = darkest, last = brightest. *)
  type ramp = string array

  val cyan : ramp

  val magenta : ramp

  val amber : ramp

  val sand : ramp

  val lava : ramp

  val ice : ramp

  val grass : ramp

  (** Pick a shade based on a 0..1 lifetime fraction (1 = newborn,
      0 = expiring). Linear bucketing across the ramp. *)
  val pick : ramp -> life01:float -> string

  (** Same as [pick] but returns the matching (r, g, b) approximation for
      use in pixel-buffer rendering. *)
  val rgb : ramp -> life01:float -> int * int * int
end

(** {1 Screen FX} *)

module Screen_fx : sig
  type t

  val create : unit -> t

  (** Pulse a full-screen white flash of [intensity] (0..1) decaying linearly
      over [duration] seconds. *)
  val flash : t -> intensity:float -> duration:float -> unit

  (** Trigger a screen shake of [magnitude] cells decaying over [duration]
      seconds. Read via [shake_offset] to apply to render coordinates. *)
  val shake : t -> magnitude:float -> duration:float -> unit

  val tick : t -> dt:float -> unit

  (** Current flash intensity in 0..1. *)
  val flash_alpha : t -> float

  (** Current shake delta as integer cell offsets. *)
  val shake_offset : t -> int * int
end

(** {1 Persistent score store} *)

module Score_store : sig
  (** Read the persisted high score for [demo] (e.g. ["miaou_force"]).
      Returns 0 if the file is missing or unreadable. Never raises. *)
  val load : demo:string -> int

  (** Write [score] to disk. Silent on any IO failure — high scores are not
      critical-path. *)
  val save : demo:string -> int -> unit

  (** [record ~demo score] updates the file if [score] is a new high and
      returns the resulting best (max of existing, [score]). *)
  val record : demo:string -> int -> int
end

(** {1 Pixel mode} *)

module Pixel_mode : sig
  (** Returns the framebuffer rendering mode for arcade demos. Defaults to
      [Octant] (256-colour, fast through the matrix driver) and never calls
      [Caps.detect ()] — auto-detected Sixel produces fragmented output on
      Konsole. Override per demo via the corresponding env var, e.g.
      [MIAOU_FORCE_PIXEL_MODE=sixel]. *)
  val resolve :
    ?env_var:string -> unit -> Miaou_widgets_display.Terminal_caps.render_mode
end
