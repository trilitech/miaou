(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(** Filetype glyphs and colour hints for file-listing widgets.

    Provides a small extension-keyed table of icons and 256-colour foreground
    codes used by {!File_browser_widget} (and any user code that wants to
    style file listings consistently).

    {b Two glyph sets}: by default, plain Unicode glyphs are used so the
    output is legible in any terminal. Setting [MIAOU_NERD_FONT=1] in the
    environment switches to a Nerd Font glyph set (requires a Nerd-patched
    font installed and selected in the terminal).
*)

(** Return the icon (with trailing space) for the given entry. *)
val icon_for : name:string -> is_dir:bool -> string

(** Return the 256-colour foreground code for the given entry, or [None] to
    inherit the surrounding theme. *)
val color_for : name:string -> is_dir:bool -> int option

(** Wrap a label with the appropriate icon prefix and foreground colour.
    Convenience for the common case [icon ^ themed colour ^ label]. *)
val decorate : name:string -> is_dir:bool -> string -> string

(** Whether the Nerd Font glyph set is currently in use (driven by
    [MIAOU_NERD_FONT]). Re-read from the environment on each call. *)
val nerd_font_enabled : unit -> bool
