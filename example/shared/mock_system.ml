(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)
(* Mock System implementation for examples and tests.

   Previous version always returned a hard-coded service JSON embedding a
   delegate_key_alias of "delegateZ", which made tests asserting per-flow
   delegate selection fail (they always read delegateZ back). We now keep
   an in-memory table of written JSON files so that service creation logic
   (which writes the file) can be observed by later reads. *)

let json_store : (string, string) Hashtbl.t = Hashtbl.create 17

let read_file path =
  (* Prefer real file contents if present (Common.write_file writes actual
     registry JSON that tests expect to parse). *)
  try
    if Sys.file_exists path then (
      let ic = open_in_bin path in
      let len = in_channel_length ic in
      let buf = really_input_string ic len in
      close_in ic ;
      Hashtbl.replace json_store path buf ;
      Ok buf)
    else raise Not_found
  with _ -> (
    match Hashtbl.find_opt json_store path with
    | Some contents -> Ok contents
    | None ->
        let base = Filename.basename path in
        if
          String.length base > 5
          && String.sub base (String.length base - 5) 5 = ".json"
        then Ok "{}"
        else Ok ("mock-content:" ^ path))

let write_file path contents =
  Hashtbl.replace json_store path contents ;
  Ok ()

let file_exists path = Sys.file_exists path || Hashtbl.mem json_store path

let is_directory path = try Sys.is_directory path with _ -> false

let mkdir _ = Ok ()

let run_command ~argv:_ ~cwd:_ :
    (Miaou_interfaces.System.run_result, string) result =
  Ok {exit_code = 0; stdout = ""; stderr = ""}

let get_current_user_info () = Ok ("user", "/home/user")

let get_disk_usage ~path =
  try
    let st = Unix.stat path in
    Ok (Int64.of_int st.Unix.st_size)
  with _ -> Ok 0L

let list_dir path =
  try
    let arr = Sys.readdir path in
    Ok (Array.to_list arr)
  with e -> Error (Printexc.to_string e)

let probe_writable ~path =
  try
    let tmp =
      Filename.concat path (Printf.sprintf ".miaou_probe_%d" (Unix.getpid ()))
    in
    let oc = open_out tmp in
    output_string oc "" ;
    close_out oc ;
    Sys.remove tmp ;
    Ok true
  with _ -> Ok false

let get_env_var var = Sys.getenv_opt var

let register () =
  (* Reset store between test runs to avoid leakage of prior service state. *)
  Hashtbl.reset json_store ;
  let module Sys = Miaou_interfaces.System in
  Sys.set
    {
      Sys.file_exists;
      is_directory;
      read_file;
      write_file;
      mkdir;
      run_command;
      get_current_user_info;
      get_disk_usage;
      list_dir;
      probe_writable;
      get_env_var;
    }
