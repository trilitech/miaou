(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(** Rotating 3-D globe rendered with the {!Octant_canvas}.

    Coastline points are supplied as [(latitude, longitude)] pairs in degrees.
    Each frame the widget rotates the points by an internal yaw (and optional
    pitch), drops back-facing points, projects survivors to the screen, and
    paints them on a fresh {!Octant_canvas} with a Lambert-style fg shade so
    the lit hemisphere stands out from the limb.

    The rendered output is a newline-separated ANSI string ready to drop into
    a layout. Caller decides how many cells to allocate; the globe inscribes
    itself in [min cols rows] cells. *)

type t

(** Create a globe.

    @param coastline polyline segments where every other element is a separator
      pair (one per polyline). Concretely: pass an array of [(lat, lon)] points
      with [(nan, nan)] sentinels between segments — or just a flat point cloud
      if you don't care about line continuity (no segments will be drawn).
      Both forms render correctly; segments give cleaner continent outlines. *)
val create :
  ?is_land:(lat:float -> lon:float -> bool) ->
  coastline:(float * float) array ->
  unit ->
  t
(** [is_land] is an optional land/sea classifier consulted while filling the
    sphere. When provided, cells whose centre projects to a land latitude /
    longitude are painted in a sand/gold ramp (Lambert-shaded), giving filled
    continents instead of just an outlined coastline. *)

(** Advance the rotation by [dt] seconds. Default rotation rate: one full
    revolution every 20 s about the polar axis. *)
val advance : t -> dt:float -> t

(** Replace the rotation (yaw and pitch in radians). *)
val set_rotation : t -> yaw:float -> pitch:float -> t

(** Current yaw in radians. *)
val yaw : t -> float

(** Render the globe at the given cell size. The output is a newline-separated
    ANSI string, [rows] lines tall and [cols] cells wide. *)
val render : t -> cols:int -> rows:int -> string

(** Convert latitude/longitude (in degrees) to a 3-D unit vector
    [(x, y, z)] with the north pole at [+y]. Exposed for tests / for callers
    that need to project arbitrary points onto the same sphere as the globe. *)
val latlon_to_xyz : float -> float -> float * float * float

(** Great-circle distance in kilometres (mean Earth radius 6371 km). *)
val haversine_km : lat1:float -> lon1:float -> lat2:float -> lon2:float -> float
