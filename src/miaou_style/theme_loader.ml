(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

let home_dir () = Sys.getenv_opt "HOME"

let xdg_config_home () =
  match Sys.getenv_opt "XDG_CONFIG_HOME" with
  | Some dir -> Some dir
  | None -> (
      match home_dir () with
      | Some home -> Some (Filename.concat home ".config")
      | None -> None)

let config_dir () =
  match xdg_config_home () with
  | Some xdg -> Some (Filename.concat xdg "miaou")
  | None -> None

let themes_dir () =
  match config_dir () with
  | Some dir -> Some (Filename.concat dir "themes")
  | None -> None

let search_paths () =
  let paths = ref [] in
  (* User global config *)
  (match config_dir () with
  | Some dir -> paths := Filename.concat dir "theme.json" :: !paths
  | None -> ()) ;
  (* Project local config *)
  paths := ".miaou/theme.json" :: !paths ;
  (* Environment variable override *)
  (match Sys.getenv_opt "MIAOU_THEME" with
  | Some path -> paths := path :: !paths
  | None -> ()) ;
  List.rev !paths

let file_exists path = try Sys.file_exists path with _ -> false

let read_file path =
  try
    let ic = open_in path in
    let n = in_channel_length ic in
    let s = really_input_string ic n in
    close_in ic ;
    Ok s
  with e -> Error (Printexc.to_string e)

let of_json_string s =
  try
    let json = Yojson.Safe.from_string s in
    Theme.of_yojson json
  with Yojson.Json_error msg -> Error msg

let to_json_string ?(pretty = true) theme =
  let json = Theme.to_yojson theme in
  if pretty then Yojson.Safe.pretty_to_string json
  else Yojson.Safe.to_string json

let load_file path =
  match read_file path with
  | Error e -> Error (Printf.sprintf "Cannot read %s: %s" path e)
  | Ok content -> (
      match of_json_string content with
      | Error e -> Error (Printf.sprintf "Cannot parse %s: %s" path e)
      | Ok theme -> Ok theme)

let load () =
  let paths = search_paths () in
  let existing_paths = List.filter file_exists paths in
  List.fold_left
    (fun acc path ->
      match load_file path with
      | Ok overlay -> Theme.merge ~base:acc ~overlay
      | Error _ -> acc (* Silently skip invalid files *))
    Theme.default
    existing_paths

let load_named name =
  match themes_dir () with
  | None -> None
  | Some dir ->
      let path = Filename.concat dir (name ^ ".json") in
      if file_exists path then
        match load_file path with
        | Ok theme -> Some (Theme.merge ~base:Theme.default ~overlay:theme)
        | Error _ -> None
      else None

let list_themes () =
  match themes_dir () with
  | None -> []
  | Some dir -> (
      if not (file_exists dir) then []
      else
        try
          Sys.readdir dir |> Array.to_list
          |> List.filter (fun f -> Filename.check_suffix f ".json")
          |> List.map Filename.remove_extension
          |> List.sort String.compare
        with _ -> [])

let list_all_themes () =
  (* Built-in themes *)
  let builtins =
    Builtin_themes.list_builtin ()
    |> List.map (fun t -> (t.Builtin_themes.id, t.Builtin_themes.name, true))
  in
  (* User themes *)
  let user_themes =
    list_themes ()
    |> List.filter (fun id -> not (Builtin_themes.is_builtin id))
    |> List.map (fun id -> (id, String.capitalize_ascii id, false))
  in
  builtins @ user_themes

let reload () = load ()

let load_any name =
  (* Try built-in first *)
  match Builtin_themes.get_builtin name with
  | Some theme -> Some theme
  | None -> load_named name
