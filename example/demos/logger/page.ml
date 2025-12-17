(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

let _tutorial_markdown = [%blob "README.md"]

type state = {lines : string list; next_page : string option}

type msg = unit

let base_lines =
  [
    "Logger demo";
    "i => info, w => warn, e => error, c => clear";
    "Esc returns to the launcher";
  ]

let init () = {lines = base_lines; next_page = None}

let update s _ = s

let add_line line s =
  let rec take n lst =
    match (n, lst) with
    | 0, _ | _, [] -> []
    | _, x :: xs -> x :: take (n - 1) xs
  in
  let lines = take 12 (line :: s.lines) in
  {s with lines}

let emit level text s =
  (match level with
  | `Info -> Logs.info (fun m -> m "%s" text)
  | `Warn -> Logs.warn (fun m -> m "%s" text)
  | `Error -> Logs.err (fun m -> m "%s" text)) ;
  add_line text s

let view s ~focus:_ ~size:_ = s.lines |> List.rev |> String.concat "\n"

let go_back s = {s with next_page = Some Demo_shared.Demo_config.launcher_page_name}

let handle_key s key_str ~size:_ =
  match Miaou.Core.Keys.of_string key_str with
  | Some (Miaou.Core.Keys.Char "Esc") | Some (Miaou.Core.Keys.Char "Escape") ->
      go_back s
  | Some (Miaou.Core.Keys.Char "i") -> emit `Info "[info] demo message" s
  | Some (Miaou.Core.Keys.Char "w") -> emit `Warn "[warn] demo message" s
  | Some (Miaou.Core.Keys.Char "e") -> emit `Error "[error] demo message" s
  | Some (Miaou.Core.Keys.Char "c") -> {s with lines = base_lines}
  | _ -> s

let move s _ = s
let refresh s = s
let enter s = s
let service_select s _ = s
let service_cycle s _ = s
let handle_modal_key s _ ~size:_ = s
let next_page s = s.next_page
let keymap (_ : state) = []
let handled_keys () = []
let back s = go_back s
let has_modal _ = false
