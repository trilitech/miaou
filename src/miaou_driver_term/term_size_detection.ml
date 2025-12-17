(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

let detect_size () =
  (* Skip LTerm-based detection (requires Lwt) - use fallback methods *)

  (* Direct terminal size detection using stty, bypassing System capability.
     This ensures we get the actual terminal size even when System is mocked. *)
  let try_direct_stty () =
    try
      (* Run stty directly with /dev/tty to get actual terminal size *)
      let (pipe_read, pipe_write) = Unix.pipe () in
      let tty_fd = Unix.openfile "/dev/tty" [Unix.O_RDONLY] 0 in
      let pid = Unix.create_process
        "stty"
        [|"stty"; "size"|]
        tty_fd      (* stdin from /dev/tty so stty can query it *)
        pipe_write  (* capture stdout *)
        Unix.stderr
      in
      Unix.close tty_fd ;
      Unix.close pipe_write ;
      let buf = Buffer.create 32 in
      let tmp = Bytes.create 64 in
      let rec read_all () =
        match Unix.read pipe_read tmp 0 64 with
        | 0 -> ()
        | n -> Buffer.add_subbytes buf tmp 0 n ; read_all ()
      in
      read_all () ;
      Unix.close pipe_read ;
      let _ = Unix.waitpid [] pid in
      let output = String.trim (Buffer.contents buf) in
      match String.split_on_char ' ' output with
      | [r; c] ->
          let rows = int_of_string r in
          let cols = int_of_string c in
          Some {LTerm_geom.rows; cols}
      | _ -> None
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
      (* Try direct stty first - this bypasses System capability and works
         even when System is mocked (e.g., in demo apps) *)
      match try_direct_stty () with
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
