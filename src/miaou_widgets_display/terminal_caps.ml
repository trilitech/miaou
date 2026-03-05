(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Mathias Bourgoin <mathias.bourgoin@atacama.tech>        *)
(*                                                                            *)
(******************************************************************************)

type render_mode = Sixel | Octant | Sextant | Half_block | Braille

let cached_mode : render_mode option ref = ref None

let mode_from_env () =
  match Sys.getenv_opt "MIAOU_PIXEL_MODE" with
  | Some "sixel" -> Some Sixel
  | Some "octant" -> Some Octant
  | Some "sextant" -> Some Sextant
  | Some "half_block" -> Some Half_block
  | Some "braille" -> Some Braille
  | _ -> None

(* VTE >= 7800 (GNOME VTE 0.78, released 2024) added Unicode 16 octant blocks *)
let vte_supports_octant () =
  match Sys.getenv_opt "VTE_VERSION" with
  | Some v -> (
      try int_of_string (String.trim v) >= 7800 with Failure _ -> false)
  | None -> false

(* foot terminal has full Unicode 16 octant support *)
let foot_terminal () =
  match Sys.getenv_opt "TERM" with
  | Some ("foot" | "foot-extra") -> true
  | _ -> false

(* WezTerm has Unicode 16 octant support *)
let wezterm () =
  match Sys.getenv_opt "TERM_PROGRAM" with Some "WezTerm" -> true | _ -> false

(* Kitty has Unicode 16 octant support *)
let kitty () =
  match Sys.getenv_opt "KITTY_WINDOW_ID" with Some _ -> true | _ -> false

let detect_octant () =
  vte_supports_octant () || foot_terminal () || wezterm () || kitty ()

(* Sextant (U+1FB00 range, Unicode 13.0) is widely supported since 2020.
   Check common terminals that are known to support it. *)
let detect_sextant () =
  match Sys.getenv_opt "TERM_PROGRAM" with
  | Some ("iTerm.app" | "WezTerm" | "Hyper") -> true
  | _ -> (
      match Sys.getenv_opt "COLORTERM" with
      | Some ("truecolor" | "24bit") -> (
          (* Most true-color terminals support sextant *)
          match Sys.getenv_opt "TERM" with
          | Some t ->
              let len = String.length t in
              (len >= 5 && String.sub t 0 5 = "xterm")
              || (len >= 6 && String.sub t 0 6 = "screen")
          | None -> false)
      | _ -> false)

let detect () =
  match !cached_mode with
  | Some m -> m
  | None ->
      let mode =
        match mode_from_env () with
        | Some m -> m
        | None ->
            if detect_octant () then Octant
            else if detect_sextant () then Sextant
            else Half_block
      in
      cached_mode := Some mode ;
      mode

let reset_cache () = cached_mode := None

(* Phase 2: querying terminal for physical cell pixel size via CSI 16 t
   requires raw terminal I/O (switching to raw mode, sending escape, reading
   response). Not implemented in Phase 1. *)
let cell_pixel_size () = None

[@@@enforce_exempt] (* non-widget module *)
