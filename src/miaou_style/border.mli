(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

(** Border styles and characters for box drawing.
    
    Defines the different border styles available (single, double, rounded, etc.)
    and the character sets used to render them.
*)

(** Border style variants *)
type style =
  | None_  (** No border *)
  | Single  (** Single line: ┌─┐ │ └─┘ *)
  | Double  (** Double line: ╔═╗ ║ ╚═╝ *)
  | Rounded  (** Rounded corners: ╭─╮ │ ╰─╯ *)
  | Ascii  (** ASCII-only: +-+ | +-+ *)
  | Heavy  (** Heavy/thick: ┏━┓ ┃ ┗━┛ *)
[@@deriving yojson]

(** Border character set *)
type chars = {
  tl : string;  (** Top-left corner *)
  tr : string;  (** Top-right corner *)
  bl : string;  (** Bottom-left corner *)
  br : string;  (** Bottom-right corner *)
  h : string;  (** Horizontal line *)
  v : string;  (** Vertical line *)
  (* Junction characters for tables/grids *)
  t_down : string;  (** Top T junction ┬ *)
  t_up : string;  (** Bottom T junction ┴ *)
  t_right : string;  (** Left T junction ├ *)
  t_left : string;  (** Right T junction ┤ *)
  cross : string;  (** Cross junction ┼ *)
}

(** Get the character set for a border style *)
val chars_of_style : style -> chars

(** Default border style *)
val default_style : style
