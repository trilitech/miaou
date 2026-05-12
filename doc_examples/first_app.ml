(******************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(******************************************************************************)

module Direct_page = Miaou_core.Direct_page

(* docs:start:first-app-page *)
module Counter = Direct_page.Make (Direct_page.With_defaults (struct
  type state = {count : int}

  let init () = {count = 0}

  let render_count count =
    Printf.sprintf
      {|+------------------------+
| Miaou counter          |
+------------------------+
| Count: %-15d |
|                        |
| Up: increment          |
| Down: decrement        |
| q: quit                |
+------------------------+|}
      count

  let view state ~focus:_ ~size:_ =
    render_count state.count

  let on_key state key ~size:_ =
    match key with
    | "Up" -> {count = state.count + 1}
    | "Down" -> {count = max 0 (state.count - 1)}
    | "q" | "Esc" | "Escape" ->
        Direct_page.quit () ;
        state
    | _ -> state
end))
(* docs:end:first-app-page *)

let render_initial () =
  let size = LTerm_geom.{rows = 24; cols = 80} in
  Counter.view (Counter.init ()) ~focus:true ~size

let render_after keys =
  let size = LTerm_geom.{rows = 24; cols = 80} in
  let state =
    List.fold_left
      (fun state key -> Counter.handle_key state key ~size)
      (Counter.init ())
      keys
  in
  Counter.view state ~focus:true ~size
