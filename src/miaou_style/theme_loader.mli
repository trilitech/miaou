(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

(** Theme loading from JSON files with file discovery and merging.
    
    Theme files are discovered in the following order (later overrides earlier):
    1. Built-in default theme (always present)
    2. User global: [~/.config/miaou/theme.json]
    3. Project local: [.miaou/theme.json]
    4. Environment variable: [$MIAOU_THEME] (path to a specific file)
    
    Named themes can be loaded from:
    - [~/.config/miaou/themes/{name}.json]
    
    All discovered theme files are merged, with later files taking precedence.
*)

(** {2 Configuration} *)

(** Get the list of paths that will be searched for theme files *)
val search_paths : unit -> string list

(** Get the directory for named themes *)
val themes_dir : unit -> string option

(** {2 Loading} *)

(** Load the effective theme by merging all discovered theme files.
    Returns the default theme if no files are found. *)
val load : unit -> Theme.t

(** Load a specific named theme (e.g., "light", "dark", "high-contrast").
    Looks in the themes directory for [{name}.json].
    Returns [None] if the theme is not found. *)
val load_named : string -> Theme.t option

(** Load a theme from a specific file path.
    Returns [Error] with message if loading fails. *)
val load_file : string -> (Theme.t, string) result

(** {2 Theme management} *)

(** List available named themes *)
val list_themes : unit -> string list

(** Reload the theme (useful after file changes) *)
val reload : unit -> Theme.t

(** {2 Parsing helpers} *)

(** Parse a theme from a JSON string *)
val of_json_string : string -> (Theme.t, string) result

(** Convert a theme to a JSON string *)
val to_json_string : ?pretty:bool -> Theme.t -> string
