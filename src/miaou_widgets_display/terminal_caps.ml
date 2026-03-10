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

let foot_terminal () =
  match Sys.getenv_opt "TERM" with
  | Some ("foot" | "foot-extra") -> true
  | _ -> false

let wezterm () =
  match Sys.getenv_opt "TERM_PROGRAM" with Some "WezTerm" -> true | _ -> false

let kitty () =
  match Sys.getenv_opt "KITTY_WINDOW_ID" with Some _ -> true | _ -> false

(* Sixel: foot, WezTerm, kitty, iTerm2 have reliable Sixel support.
   VTE-based terminals (GNOME Terminal, Terminator) technically support Sixel
   from VTE 0.70+ but it's often disabled at compile time and hard to detect
   reliably. Users can override with MIAOU_PIXEL_MODE=sixel. *)
let detect_sixel () =
  let iterm =
    match Sys.getenv_opt "TERM_PROGRAM" with
    | Some "iTerm.app" -> true | _ -> false
  in
  foot_terminal () || wezterm () || kitty () || iterm

(* Octant (U+1CD00, Unicode 16): foot, WezTerm, kitty have font support.
   VTE >= 7800 supports the codepoints but user fonts rarely include them. *)
let detect_octant () = foot_terminal () || wezterm () || kitty ()

(* Sextant (U+1FB00, Unicode 13.0): widely supported since 2020.
   VTE-based terminals with truecolor all support sextant glyphs. *)
let detect_sextant () =
  match Sys.getenv_opt "TERM_PROGRAM" with
  | Some ("iTerm.app" | "WezTerm" | "Hyper") -> true
  | _ -> (
      (* VTE-based terminals (Terminator, GNOME Terminal, …) *)
      let has_vte = Sys.getenv_opt "VTE_VERSION" <> None in
      if has_vte then true
      else
        match Sys.getenv_opt "COLORTERM" with
        | Some ("truecolor" | "24bit") -> (
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
            if detect_sixel () then Sixel
            else if detect_octant () then Octant
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
