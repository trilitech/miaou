(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

module Inner = struct
  let tutorial_title = "Inline CLI"

  let tutorial_markdown = [%blob "README.md"]

  module W = Miaou_widgets_display.Widgets

  let max_entries = 10

  let read_dir () =
    let cwd = Sys.getcwd () in
    let entries =
      try Sys.readdir "." |> Array.to_list with Sys_error _ -> []
    in
    let entries = List.sort String.compare entries in
    let truncated, total =
      let n = List.length entries in
      let kept =
        let rec take k = function
          | _ when k <= 0 -> []
          | [] -> []
          | x :: rest -> x :: take (k - 1) rest
        in
        take max_entries entries
      in
      (kept, n)
    in
    (cwd, truncated, total)

  type state = {
    cwd : string;
    entries : string list;
    total : int;
    quit : bool;
    next_page : string option;
  }

  type msg = unit

  let init () =
    let cwd, entries, total = read_dir () in
    {cwd; entries; total; quit = false; next_page = None}

  let update s _ = s

  let format_entry name =
    let is_dir =
      try Sys.is_directory (Filename.concat (Sys.getcwd ()) name)
      with Sys_error _ -> false
    in
    if is_dir then W.themed_emphasis (name ^ "/") else W.themed_text name

  let view s ~focus:_ ~size:_ =
    let header = W.titleize "What's in this directory?" in
    let path_line = W.themed_text "cwd: " ^ W.themed_emphasis s.cwd in
    let count_line =
      W.themed_muted
        (Printf.sprintf
           "Showing %d of %d entries (sorted)."
           (List.length s.entries)
           s.total)
    in
    let entry_lines = List.map (fun e -> "  " ^ format_entry e) s.entries in
    let hint = W.themed_muted "Keys: r refresh · q/Esc quit · t tutorial" in
    String.concat
      "\n"
      ([header; path_line; count_line; ""] @ entry_lines @ [""; hint])

  let go_back s =
    {s with next_page = Some Demo_shared.Demo_config.launcher_page_name}

  let handle_key s key_str ~size:_ =
    match key_str with
    | "Esc" | "Escape" | "q" | "Q" -> go_back s
    | "r" | "R" ->
        let cwd, entries, total = read_dir () in
        {s with cwd; entries; total}
    | _ -> s

  let move s _ = s

  let refresh s =
    let cwd, entries, total = read_dir () in
    {s with cwd; entries; total}

  let enter s = s

  let service_select s _ = s

  let service_cycle s _ = s

  let handle_modal_key s _ ~size:_ = s

  let next_page s = s.next_page

  let keymap (_ : state) = []

  let handled_keys () = []

  let back s = go_back s

  let has_modal _ = false
end

include Demo_shared.Demo_page.MakeSimple (Inner)
