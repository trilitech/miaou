(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

(** Built-in themes inspired by popular color schemes.

    These themes are embedded directly in the library for easy access without
    requiring external files. Themes can be listed with {!list_builtin} and
    loaded with {!get_builtin}.

    Available themes:
    - Dark: catppuccin-mocha, dracula, nord, gruvbox-dark, tokyonight, opencode, oled
    - Light: catppuccin-latte, nord-light, gruvbox-light, tokyonight-day

    The [opencode] and [oled] themes use borderless style ([default_border_style: "None"])
    for a clean, minimal look. The [oled] theme features true black background (#000000)
    with soft pastel colors, optimized for OLED screens to save battery and reduce eye strain.
*)

(** Theme descriptor with metadata *)
type builtin_theme = {
  id : string;  (** Unique identifier (e.g., "catppuccin-mocha") *)
  name : string;  (** Display name (e.g., "Catppuccin Mocha") *)
  description : string;  (** Short description *)
  dark_mode : bool;  (** Whether this is a dark theme *)
  borderless : bool;  (** Whether this theme uses no borders *)
}

(** {2 Theme Discovery} *)

(** List all available built-in themes with metadata *)
val list_builtin : unit -> builtin_theme list

(** List just the theme IDs (for quick iteration) *)
val list_builtin_ids : unit -> string list

(** Get theme info by ID *)
val get_info : string -> builtin_theme option

(** Check if a theme ID is a built-in theme *)
val is_builtin : string -> bool

(** {2 Theme Loading} *)

(** Load a built-in theme by ID.
    Returns [None] if the ID doesn't match a built-in theme.

    Example:
    {[
      match Builtin_themes.get_builtin "dracula" with
      | Some theme -> Style_context.set_theme theme
      | None -> (* fallback to default *)
    ]}
*)
val get_builtin : string -> Theme.t option

(** Get the raw JSON string for a built-in theme (for debugging/export) *)
val get_json : string -> string option
