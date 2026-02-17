(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

type adaptive_color = {light : int; dark : int} [@@deriving yojson]

type color = Fixed of int | Adaptive of adaptive_color [@@deriving yojson]

type t = {
  fg : color option;
  bg : color option;
  bold : bool option;
  dim : bool option;
  italic : bool option;
  underline : bool option;
  reverse : bool option;
  strikethrough : bool option;
}
[@@deriving yojson]

let empty =
  {
    fg = None;
    bg = None;
    bold = None;
    dim = None;
    italic = None;
    underline = None;
    reverse = None;
    strikethrough = None;
  }

let default =
  {
    fg = Some (Fixed (-1));
    (* -1 = terminal default *)
    bg = Some (Fixed (-1));
    bold = Some false;
    dim = Some false;
    italic = Some false;
    underline = Some false;
    reverse = Some false;
    strikethrough = Some false;
  }

let make ?fg ?bg ?bold ?dim ?italic ?underline ?reverse ?strikethrough () =
  {fg; bg; bold; dim; italic; underline; reverse; strikethrough}

let fg c = {empty with fg = Some (Fixed c)}

let bg c = {empty with bg = Some (Fixed c)}

let bold = {empty with bold = Some true}

let dim = {empty with dim = Some true}

(* Helper to pick first Some value *)
let first_some a b = match a with Some _ -> a | None -> b

let patch ~base ~overlay =
  {
    fg = first_some overlay.fg base.fg;
    bg = first_some overlay.bg base.bg;
    bold = first_some overlay.bold base.bold;
    dim = first_some overlay.dim base.dim;
    italic = first_some overlay.italic base.italic;
    underline = first_some overlay.underline base.underline;
    reverse = first_some overlay.reverse base.reverse;
    strikethrough = first_some overlay.strikethrough base.strikethrough;
  }

let resolve ~default:d style = patch ~base:d ~overlay:style

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

let resolve_color ?(dark_mode = true) = function
  | Fixed c -> c
  | Adaptive {light; dark} -> if dark_mode then dark else light

let to_resolved ?(dark_mode = true) style =
  let resolved = resolve ~default style in
  {
    r_fg =
      (match resolved.fg with
      | Some c -> resolve_color ~dark_mode c
      | None -> -1);
    r_bg =
      (match resolved.bg with
      | Some c -> resolve_color ~dark_mode c
      | None -> -1);
    r_bold = Option.value ~default:false resolved.bold;
    r_dim = Option.value ~default:false resolved.dim;
    r_italic = Option.value ~default:false resolved.italic;
    r_underline = Option.value ~default:false resolved.underline;
    r_reverse = Option.value ~default:false resolved.reverse;
    r_strikethrough = Option.value ~default:false resolved.strikethrough;
  }

let to_ansi_prefix r =
  let buf = Buffer.create 32 in
  let add_code code =
    if Buffer.length buf > 0 then Buffer.add_char buf ';' ;
    Buffer.add_string buf code
  in
  (* Text attributes *)
  if r.r_bold then add_code "1" ;
  if r.r_dim then add_code "2" ;
  if r.r_italic then add_code "3" ;
  if r.r_underline then add_code "4" ;
  if r.r_reverse then add_code "7" ;
  if r.r_strikethrough then add_code "9" ;
  (* Foreground color *)
  if r.r_fg >= 0 then add_code ("38;5;" ^ string_of_int r.r_fg) ;
  (* Background color *)
  if r.r_bg >= 0 then add_code ("48;5;" ^ string_of_int r.r_bg) ;
  (* Build escape sequence *)
  if Buffer.length buf > 0 then "\027[" ^ Buffer.contents buf ^ "m" else ""

let ansi_reset = "\027[0m"

let apply resolved s =
  let prefix = to_ansi_prefix resolved in
  if prefix = "" then s else prefix ^ s ^ ansi_reset

let render style s =
  let resolved = to_resolved style in
  apply resolved s
