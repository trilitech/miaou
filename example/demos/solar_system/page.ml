(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

module Inner = struct
  let tutorial_title = "Solar System"

  let tutorial_markdown = [%blob "README.md"]

  type state = Model.state

  type msg = unit

  let init () = Model.init ()

  let update s _ = s

  let view (s : state) ~focus:_ ~size = View.render s ~size

  let go_back (s : state) =
    {
      s with
      Model.next_page = Some Demo_shared.Demo_config.launcher_page_name;
    }

  let handle_key (s : state) key ~size:_ =
    match Model.speed_of_digit key with
    | Some sp -> {s with Model.speed = sp; paused = false}
    | None -> (
        match key with
        | "p" | "Space" | " " -> {s with Model.paused = not s.paused}
        | "o" -> {s with Model.show_orbits = not s.show_orbits}
        | "l" -> {s with Model.show_labels = not s.show_labels}
        | "r" -> {s with Model.t_days = 0.0}
        | "Tab" -> {s with Model.show_panel = not s.show_panel}
        | "Escape" | "Esc" -> go_back s
        | _ -> s)

  let move (s : state) _ = s

  let refresh (s : state) =
    let dt =
      match Miaou_interfaces.Clock.get () with
      | Some c -> c.dt ()
      | None -> 1.0 /. 30.0
    in
    Model.advance s ~dt_real:dt

  let enter (s : state) = s

  let service_select (s : state) _ = s

  let service_cycle (s : state) _ = s

  let handle_modal_key (s : state) _ ~size:_ = s

  let next_page (s : state) = s.Model.next_page

  let keymap (_ : state) = []

  let handled_keys () = []

  let back (s : state) = go_back s

  let has_modal _ = false
end

include Demo_shared.Demo_page.MakeSimple (Inner)
