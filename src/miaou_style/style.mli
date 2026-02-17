(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

(** Core style type for terminal rendering.
    
    A style defines visual attributes for text rendering: colors, 
    text decorations (bold, dim, underline, etc.), and can be combined 
    through patching/merging.
    
    All fields are [option] to support inheritance: [None] means 
    "inherit from parent", [Some v] means "use this value".
*)

(** Adaptive color that can have different values for light and dark terminals *)
type adaptive_color = {
  light : int;  (** Color value for light terminal backgrounds *)
  dark : int;  (** Color value for dark terminal backgrounds *)
}
[@@deriving yojson]

(** Color specification: either a fixed color or adaptive *)
type color =
  | Fixed of int  (** Fixed 256-color value *)
  | Adaptive of adaptive_color  (** Adapts to terminal background *)
[@@deriving yojson]

(** Core style record.
    
    All fields are optional to support style inheritance/cascade.
    [None] means "inherit from parent/default", [Some v] means "explicitly set".
*)
type t = {
  fg : color option;  (** Foreground color (256-color palette or adaptive) *)
  bg : color option;  (** Background color *)
  bold : bool option;  (** Bold text *)
  dim : bool option;  (** Dim/faint text *)
  italic : bool option;  (** Italic text *)
  underline : bool option;  (** Underlined text *)
  reverse : bool option;  (** Reverse video (swap fg/bg) *)
  strikethrough : bool option;  (** Strikethrough text *)
}
[@@deriving yojson]

(** Empty style - all fields are [None] (inherit everything) *)
val empty : t

(** Default style - concrete values for all fields *)
val default : t

(** {2 Constructors} *)

(** Create a style with specified attributes. Unspecified attributes are [None]. *)
val make :
  ?fg:color ->
  ?bg:color ->
  ?bold:bool ->
  ?dim:bool ->
  ?italic:bool ->
  ?underline:bool ->
  ?reverse:bool ->
  ?strikethrough:bool ->
  unit ->
  t

(** Convenience: create style with fixed foreground color *)
val fg : int -> t

(** Convenience: create style with fixed background color *)
val bg : int -> t

(** Convenience: create bold style *)
val bold : t

(** Convenience: create dim style *)
val dim : t

(** {2 Combining styles} *)

(** [patch ~base ~overlay] merges two styles.
    Values from [overlay] take precedence when they are [Some].
    This is like CSS cascade: more specific rules override general ones. *)
val patch : base:t -> overlay:t -> t

(** [resolve ~default style] collapses all [None] values using [default].
    Returns a style where all fields are [Some]. *)
val resolve : default:t -> t -> t

(** {2 ANSI rendering} *)

(** Resolved style with all concrete values (no Options) *)
type resolved = {
  r_fg : int;
  r_bg : int;
  r_bold : bool;
  r_dim : bool;
  r_italic : bool;
  r_underline : bool;
  r_reverse : bool;
  r_strikethrough : bool;
}

(** Resolve a color for the current terminal (dark mode assumed by default) *)
val resolve_color : ?dark_mode:bool -> color -> int

(** Resolve style to concrete values *)
val to_resolved : ?dark_mode:bool -> t -> resolved

(** Convert resolved style to ANSI escape sequence prefix *)
val to_ansi_prefix : resolved -> string

(** Convert resolved style to ANSI reset sequence *)
val ansi_reset : string

(** Apply a resolved style to a string (wrap with ANSI codes) *)
val apply : resolved -> string -> string

(** Apply style directly to string (resolves with defaults, assumes dark mode) *)
val render : t -> string -> string
