(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(** User-supplied keybinding overrides.

    A small line-based configuration format that lets end users override
    actions per page (or globally) without touching application code:

    {v
      # ~/.config/miaou/keymap.conf
      page=*        key=ctrl+q   action=quit
      page=files    key=ctrl+r   action=reload
      page=editor   key=ctrl+s   action=save
    v}

    Rules are matched in declaration order. The first rule whose [page]
    matches (either [page=*] or [page=<name>]) and whose [key] matches the
    pressed key wins. Any line beginning with [#] (after leading whitespace)
    is treated as a comment, blank lines are ignored.

    Keys are compared case-insensitively after a small set of normalisations:
    [ctrl+x] / [c-x] / [Ctrl-X] all become [C-x] (matching
    {!Miaou_core.Keys.to_string} for [Control "x"]). [shift+tab] is folded
    to [Shift-Tab]. *)

(** Parsed keymap. *)
type t

(** A keymap with no rules. *)
val empty : t

(** Whether the keymap has any rules. *)
val is_empty : t -> bool

(** Number of rules in the keymap. *)
val rule_count : t -> int

(** Parse the contents of a keymap file. Returns [Error msg] on the first
    syntactically invalid line, with [msg] including the offending line
    number. Empty input yields {!empty}. *)
val parse : string -> (t, string) result

(** Load a keymap from [path]. If [path] is omitted, the loader looks at
    [MIAOU_KEYMAP_FILE]; failing that, [$XDG_CONFIG_HOME/miaou/keymap.conf]
    (or [~/.config/miaou/keymap.conf]). A missing file silently yields
    {!empty} — only parse errors raise. *)
val load : ?path:string -> unit -> (t, string) result

(** Find the user-defined action for a [(page, key)] pair, if any. Both
    [page]-specific and global ([page=*]) rules are searched in order. *)
val find : t -> page:string -> key:string -> string option

(** All rules in declaration order, exposed for inspection / tests.
    Each tuple is [(page_pattern, key, action)] where [page_pattern]
    is [None] for [page=*]. *)
val rules : t -> (string option * string * string) list
