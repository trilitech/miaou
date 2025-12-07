(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(** Sparkline widget for compact inline time-series visualization.

    Sparklines use Unicode block characters ( ▂▃▄▅▆▇█) to display trends
    in a minimal footprint, ideal for dashboards and monitoring displays.

    {1 Usage Example}

    {[
      let spark = Sparkline_widget.create ~width:30 ~max_points:30 () in
      for i = 1 to 30 do
        Sparkline_widget.push spark (Random.float 100.)
      done;
      print_endline (Sparkline_widget.render spark ~focus:true ~show_value:true)
    ]}

    Output: [ ▃▄▆▇█▇▅▃▂ ▂▃▅▆▇█▇▆▄▃▂ ] 42.3%
*)

type threshold = {value : float; color : string}
(** A threshold for coloring sparkline segments with a value above it. *)

type t
(** The sparkline widget type. *)

val create :
  width:int ->
  max_points:int ->
  ?min_value:float ->
  ?max_value:float ->
  unit ->
  t
(** Create a sparkline with fixed width.
    - [width] Display width in characters.
    - [max_points] Maximum data points to retain (circular buffer).
    - [min_value] Optional fixed minimum for scaling (default: auto-scale).
    - [max_value] Optional fixed maximum for scaling (default: auto-scale). *)

val push : t -> float -> unit
(** Add a data point to the sparkline. Older points are dropped when
    [max_points] is exceeded. *)

val render :
  t ->
  focus:bool ->
  show_value:bool ->
  ?color:string ->
  ?thresholds:threshold list ->
  unit ->
  string
(** Render the sparkline using block characters ( ▂▃▄▅▆▇█).
    - [focus] Whether to highlight (bold/color).
    - [show_value] If true, append current value as text.
    - [color] Optional default ANSI color code for the sparkline.
    - [thresholds] Optional list of thresholds for coloring segments.
      Segments with a value greater than a threshold's [value] will be
      colored with the threshold's [color]. If multiple thresholds are
      exceeded, the one with the highest value is used. *)

val render_with_label :
  t ->
  label:string ->
  focus:bool ->
  ?color:string ->
  ?thresholds:threshold list ->
  unit ->
  string
(** Render with a label prefix.
    Example: "CPU: [ ▂▃▄▅▆▇█] 78%" *)

val stats : t -> float * float * float
(** Get current statistics: (min, max, current). *)

val clear : t -> unit
(** Clear all data points. *)

val get_data : t -> float list
(** Get all data points as a list. *)

val get_bounds : t -> float * float * float
(** Get bounds and current value: (min, max, current). *)

val is_empty : t -> bool
(** Check if sparkline has no data. *)
