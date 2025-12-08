(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

let detect_size () =
  let try_lterm () =
    try
      let term = Lwt_main.run (Lazy.force LTerm.stdout) in
      let sz = LTerm.size term in
      Some {LTerm_geom.rows = sz.LTerm_geom.rows; cols = sz.LTerm_geom.cols}
    with _ -> None
  in
  let try_env_override () =
    match
      (Sys.getenv_opt "MIAOU_TUI_ROWS", Sys.getenv_opt "MIAOU_TUI_COLS")
    with
    | Some r, Some c -> (
        try
          let rows = int_of_string (String.trim r) in
          let cols = int_of_string (String.trim c) in
          Some {LTerm_geom.rows; cols}
        with _ -> None)
    | _ -> None
  in
  let try_stty () =
    try
      let sys = Miaou_interfaces.System.require () in
      let try_stdout_fd () =
        match
          sys.run_command
            ~argv:["stty"; "size"; "-F"; "/proc/self/fd/1"]
            ~cwd:None
        with
        | Ok {stdout; _} -> (
            let trimmed = String.trim stdout in
            match String.split_on_char ' ' trimmed with
            | [r; c] ->
                let rows = int_of_string r in
                let cols = int_of_string c in
                Some {LTerm_geom.rows; cols}
            | _ -> None)
        | Error _ -> None
      in
      match try_stdout_fd () with
      | Some s -> Some s
      | None -> (
          match
            sys.run_command ~argv:["stty"; "size"; "-F"; "/dev/tty"] ~cwd:None
          with
          | Ok {stdout; _} -> (
              let trimmed = String.trim stdout in
              match String.split_on_char ' ' trimmed with
              | [r; c] ->
                  let rows = int_of_string r in
                  let cols = int_of_string c in
                  Some {LTerm_geom.rows; cols}
              | _ -> None)
          | Error _ -> (
              match sys.run_command ~argv:["stty"; "size"] ~cwd:None with
              | Ok {stdout; _} -> (
                  let trimmed = String.trim stdout in
                  match String.split_on_char ' ' trimmed with
                  | [r; c] ->
                      let rows = int_of_string r in
                      let cols = int_of_string c in
                      Some {LTerm_geom.rows; cols}
                  | _ -> None)
              | Error _ -> None))
    with _ -> None
  in
  let try_tput () =
    try
      let sys = Miaou_interfaces.System.require () in
      match sys.run_command ~argv:["tput"; "lines"] ~cwd:None with
      | Ok {stdout = l; _} -> (
          match sys.run_command ~argv:["tput"; "cols"] ~cwd:None with
          | Ok {stdout = c; _} ->
              let rows = int_of_string (String.trim l) in
              let cols = int_of_string (String.trim c) in
              Some {LTerm_geom.rows; cols}
          | Error _ -> None)
      | Error _ -> None
    with _ -> None
  in
  let try_stty_a () =
    let parse_rows_cols s =
      let open Str in
      let rgx1 = regexp ".*rows \\([0-9]+\\); columns \\([0-9]+\\).*" in
      let rgx2 = regexp ".*columns \\([0-9]+\\); rows \\([0-9]+\\).*" in
      if string_match rgx1 s 0 then
        let rows = int_of_string (matched_group 1 s) in
        let cols = int_of_string (matched_group 2 s) in
        Some {LTerm_geom.rows; cols}
      else if string_match rgx2 s 0 then
        let cols = int_of_string (matched_group 1 s) in
        let rows = int_of_string (matched_group 2 s) in
        Some {LTerm_geom.rows; cols}
      else None
    in
    try
      let sys = Miaou_interfaces.System.require () in
      match
        sys.run_command ~argv:["stty"; "-a"; "-F"; "/dev/tty"] ~cwd:None
      with
      | Ok {stdout; _} -> (
          match parse_rows_cols stdout with
          | Some s -> Some s
          | None -> (
              match sys.run_command ~argv:["stty"; "-a"] ~cwd:None with
              | Ok {stdout; _} -> parse_rows_cols stdout
              | Error _ -> None))
      | Error _ -> None
    with _ -> None
  in
  match try_env_override () with
  | Some s -> s
  | None -> (
      match try_lterm () with
      | Some s -> s
      | None -> (
          match try_stty () with
          | Some s -> s
          | None -> (
              match try_tput () with
              | Some s -> s
              | None -> (
                  match try_stty_a () with
                  | Some s -> s
                  | None -> {LTerm_geom.rows = 24; cols = 80}))))
