(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

type adaptive_color = {light : int; dark : int} [@@deriving yojson]

type color = Fixed of int | Adaptive of adaptive_color

let color_to_yojson = function
  | Fixed c -> `Assoc [("Fixed", `Int c)]
  | Adaptive a -> `Assoc [("Adaptive", adaptive_color_to_yojson a)]

let color_of_yojson = function
  | `Int c -> Ok (Fixed c)
  | `List [`String "Fixed"; `Int c] -> Ok (Fixed c)
  | `Assoc [("Fixed", `Int c)] -> Ok (Fixed c)
  | `List [`String "Adaptive"; json] -> (
      match adaptive_color_of_yojson json with
      | Ok a -> Ok (Adaptive a)
      | Error e -> Error e)
  | `Assoc [("Adaptive", json)] -> (
      match adaptive_color_of_yojson json with
      | Ok a -> Ok (Adaptive a)
      | Error e -> Error e)
  | _ -> Error "Style.color"

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

let t_to_yojson t =
  let field name value = (name, value) in
  let opt_field name = function
    | None -> None
    | Some v -> Some (field name v)
  in
  let fields =
    [
      opt_field "fg" (Option.map color_to_yojson t.fg);
      opt_field "bg" (Option.map color_to_yojson t.bg);
      opt_field "bold" (Option.map (fun b -> `Bool b) t.bold);
      opt_field "dim" (Option.map (fun b -> `Bool b) t.dim);
      opt_field "italic" (Option.map (fun b -> `Bool b) t.italic);
      opt_field "underline" (Option.map (fun b -> `Bool b) t.underline);
      opt_field "reverse" (Option.map (fun b -> `Bool b) t.reverse);
      opt_field "strikethrough" (Option.map (fun b -> `Bool b) t.strikethrough);
    ]
    |> List.filter_map (fun x -> x)
  in
  `Assoc fields

let t_of_yojson json =
  let ( let* ) = Result.bind in
  let bool_of_yojson = function `Bool b -> Ok b | _ -> Error "bool" in
  let parse_opt name parser fields =
    match List.assoc_opt name fields with
    | None | Some `Null -> Ok None
    | Some v -> parser v |> Result.map (fun x -> Some x)
  in
  match json with
  | `Assoc fields ->
      let* fg = parse_opt "fg" color_of_yojson fields in
      let* bg = parse_opt "bg" color_of_yojson fields in
      let* bold = parse_opt "bold" bool_of_yojson fields in
      let* dim = parse_opt "dim" bool_of_yojson fields in
      let* italic = parse_opt "italic" bool_of_yojson fields in
      let* underline = parse_opt "underline" bool_of_yojson fields in
      let* reverse = parse_opt "reverse" bool_of_yojson fields in
      let* strikethrough = parse_opt "strikethrough" bool_of_yojson fields in
      Ok {fg; bg; bold; dim; italic; underline; reverse; strikethrough}
  | _ -> Error "Style.t"

let to_yojson = t_to_yojson

let of_yojson = t_of_yojson

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

let fg_ansi_code n =
  if n >= 0 && n <= 7 then string_of_int (30 + n)
  else if n >= 8 && n <= 15 then string_of_int (90 + n - 8)
  else if n >= 16 then "38;5;" ^ string_of_int n
  else ""

let bg_ansi_code n =
  if n >= 0 && n <= 7 then string_of_int (40 + n)
  else if n >= 8 && n <= 15 then string_of_int (100 + n - 8)
  else if n >= 16 then "48;5;" ^ string_of_int n
  else ""

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
  (* Foreground color: 0-15 use basic ANSI codes (terminal-configurable),
     16-255 use 256-color extended codes *)
  let fg_code = fg_ansi_code r.r_fg in
  if fg_code <> "" then add_code fg_code ;
  (* Background color: same logic *)
  let bg_code = bg_ansi_code r.r_bg in
  if bg_code <> "" then add_code bg_code ;
  (* Build escape sequence *)
  if Buffer.length buf > 0 then "\027[" ^ Buffer.contents buf ^ "m" else ""

let ansi_reset = "\027[0m"

let apply resolved s =
  let prefix = to_ansi_prefix resolved in
  if prefix = "" then s else prefix ^ s ^ ansi_reset

let render style s =
  let resolved = to_resolved style in
  apply resolved s
