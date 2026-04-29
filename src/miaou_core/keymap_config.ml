(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

type rule = {page : string option; key : string; action : string}

type t = rule list

let empty : t = []

let is_empty t = t = []

let rule_count t = List.length t

let rules t =
  List.map
    (fun r ->
      let pp = r.page in
      (pp, r.key, r.action))
    t

(* Normalise a key string from human form (ctrl+r, c-r, Ctrl-X) to the
   canonical Keys.to_string form (C-r, C-x, Shift-Tab, Enter, ...). *)
let normalize_key k =
  let s = String.trim k in
  let lower_prefix p =
    String.length s >= String.length p
    && String.lowercase_ascii (String.sub s 0 (String.length p)) = p
  in
  if String.length s = 0 then s
  else if lower_prefix "ctrl+" then
    let rest = String.sub s 5 (String.length s - 5) in
    "C-" ^ String.lowercase_ascii rest
  else if lower_prefix "ctrl-" then
    let rest = String.sub s 5 (String.length s - 5) in
    "C-" ^ String.lowercase_ascii rest
  else if lower_prefix "c-" then
    let rest = String.sub s 2 (String.length s - 2) in
    "C-" ^ String.lowercase_ascii rest
  else if
    String.lowercase_ascii s = "shift+tab"
    || String.lowercase_ascii s = "shift-tab"
    || String.lowercase_ascii s = "s-tab"
  then "Shift-Tab"
  else
    (* Capitalise common named keys for canonical form. *)
    match String.lowercase_ascii s with
    | "enter" -> "Enter"
    | "escape" | "esc" -> "Escape"
    | "tab" -> "Tab"
    | "backspace" -> "Backspace"
    | "delete" -> "Delete"
    | "up" -> "Up"
    | "down" -> "Down"
    | "left" -> "Left"
    | "right" -> "Right"
    | "home" -> "Home"
    | "end" -> "End"
    | "pageup" -> "PageUp"
    | "pagedown" -> "PageDown"
    | _ -> s

(* Parse "key=value" tokens. Returns (key, value) or None. *)
let parse_kv tok =
  match String.index_opt tok '=' with
  | None -> None
  | Some i ->
      let k = String.sub tok 0 i in
      let v = String.sub tok (i + 1) (String.length tok - i - 1) in
      Some (String.trim k, String.trim v)

(* Split a non-comment line into whitespace-separated tokens. *)
let tokenise line =
  String.split_on_char ' ' line
  |> List.concat_map (String.split_on_char '\t')
  |> List.filter (fun s -> s <> "")

let parse_line ~lineno line =
  let trimmed = String.trim line in
  if trimmed = "" || (String.length trimmed > 0 && trimmed.[0] = '#') then
    Ok None
  else
    let tokens = tokenise trimmed in
    let kvs = List.filter_map parse_kv tokens in
    let lookup k = List.assoc_opt k kvs in
    match (lookup "page", lookup "key", lookup "action") with
    | Some page, Some key, Some action ->
        let page = if page = "*" then None else Some page in
        let key = normalize_key key in
        if action = "" then
          Error (Printf.sprintf "line %d: empty action" lineno)
        else Ok (Some {page; key; action})
    | _ ->
        Error
          (Printf.sprintf
             "line %d: expected `page=<name|*> key=<key> action=<id>`"
             lineno)

let parse text =
  let lines = String.split_on_char '\n' text in
  let rec loop lineno acc = function
    | [] -> Ok (List.rev acc)
    | line :: rest -> (
        match parse_line ~lineno line with
        | Ok None -> loop (lineno + 1) acc rest
        | Ok (Some r) -> loop (lineno + 1) (r :: acc) rest
        | Error msg -> Error msg)
  in
  loop 1 [] lines

let default_path () =
  match Sys.getenv_opt "MIAOU_KEYMAP_FILE" with
  | Some p when p <> "" -> Some p
  | _ -> (
      let xdg = Sys.getenv_opt "XDG_CONFIG_HOME" in
      let home = Sys.getenv_opt "HOME" in
      match (xdg, home) with
      | Some x, _ when x <> "" -> Some (Filename.concat x "miaou/keymap.conf")
      | _, Some h when h <> "" ->
          Some (Filename.concat h ".config/miaou/keymap.conf")
      | _ -> None)

let read_file path =
  try
    let ic = open_in path in
    let len = in_channel_length ic in
    let buf = really_input_string ic len in
    close_in ic ;
    Some buf
  with _ -> None

let load ?path () =
  let p = match path with Some p -> Some p | None -> default_path () in
  match p with
  | None -> Ok empty
  | Some p -> (
      match read_file p with None -> Ok empty | Some text -> parse text)

let find t ~page ~key =
  let key = normalize_key key in
  let rec walk = function
    | [] -> None
    | r :: rest ->
        let page_match =
          match r.page with None -> true | Some p -> p = page
        in
        if page_match && r.key = key then Some r.action else walk rest
  in
  walk t
