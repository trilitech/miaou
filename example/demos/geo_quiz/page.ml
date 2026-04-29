(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

module Inner = struct
  let tutorial_title = "Geo Quiz"

  let tutorial_markdown = [%blob "README.md"]

  type state = Game.state

  type msg = unit

  let init () = Game.init ()

  let update s _ = s

  let view (s : state) ~focus:_ ~size = View.render s ~size

  let go_back (s : state) =
    {s with Game.next_page = Some Demo_shared.Demo_config.launcher_page_name}

  (* A short step in lat/lon for arrow keys; can be tuned per-tier later. *)
  let lat_step = 5.0

  let lon_step = 5.0

  let big_factor = 4.0

  let try_mouse_to_cursor (s : state) ~size key =
    match Miaou_helpers.Mouse.parse_click key with
    | None -> None
    | Some {Miaou_helpers.Mouse.row; col} ->
        let top, origin, mc, mr = View.map_geometry ~size in
        (* mouse coords are 1-indexed *)
        let map_col = col - 1 - origin in
        let map_row = row - 1 - top in
        if map_col < 0 || map_col >= mc || map_row < 0 || map_row >= mr then
          Some s
        else
          let lat, lon =
            View.cell_to_latlon ~map_cols:mc ~map_rows:mr ~map_col ~map_row
          in
          Some {s with Game.cursor_lat = lat; cursor_lon = lon}

  let handle_round_key (s : state) key ~size =
    match try_mouse_to_cursor s ~size key with
    | Some s' -> s'
    | None -> (
        match key with
        | "Up" -> Game.move_cursor s ~dlat:lat_step ~dlon:0.0
        | "Down" -> Game.move_cursor s ~dlat:(-.lat_step) ~dlon:0.0
        | "Left" -> Game.move_cursor s ~dlat:0.0 ~dlon:(-.lon_step)
        | "Right" -> Game.move_cursor s ~dlat:0.0 ~dlon:lon_step
        | "Shift-Up" | "S-Up" ->
            Game.move_cursor s ~dlat:(lat_step *. big_factor) ~dlon:0.0
        | "Shift-Down" | "S-Down" ->
            Game.move_cursor s ~dlat:(-.lat_step *. big_factor) ~dlon:0.0
        | "Shift-Left" | "S-Left" ->
            Game.move_cursor s ~dlat:0.0 ~dlon:(-.lon_step *. big_factor)
        | "Shift-Right" | "S-Right" ->
            Game.move_cursor s ~dlat:0.0 ~dlon:(lon_step *. big_factor)
        | "Enter" -> Game.lock_in s ~timed_out:false
        | "Escape" | "Esc" -> Game.reset_to_menu s
        | _ -> s)

  let handle_menu_key (s : state) key =
    match key with
    | "Left" -> Game.cycle_difficulty s ~delta:(-1)
    | "Right" -> Game.cycle_difficulty s ~delta:1
    | "Enter" ->
        let s = Game.start_round {s with round_idx = 0; results = []} in
        let () = Game.register_round_timer ~deadline_s:s.round_deadline_s in
        s
    | "Escape" | "Esc" -> go_back s
    | _ -> s

  let handle_round_end_key (s : state) key =
    match key with
    | "Enter" ->
        let s' = Game.next_or_finish s in
        if s'.mode = Game.Round then
          let () = Game.register_round_timer ~deadline_s:s'.round_deadline_s in
          s'
        else s'
    | "Escape" | "Esc" -> Game.reset_to_menu s
    | _ -> s

  let handle_game_over_key (s : state) key =
    match key with
    | "Enter" -> Game.reset_to_menu s
    | "Escape" | "Esc" -> go_back s
    | _ -> s

  let handle_key (s : state) key_str ~size =
    match s.mode with
    | Game.Menu -> handle_menu_key s key_str
    | Game.Round -> handle_round_key s key_str ~size
    | Game.Round_end -> handle_round_end_key s key_str
    | Game.Game_over -> handle_game_over_key s key_str

  let move (s : state) _ = s

  let refresh (s : state) =
    let dt =
      match Miaou_interfaces.Clock.get () with
      | Some c -> c.dt ()
      | None -> 1.0 /. 30.0
    in
    let s =
      match s.mode with Game.Menu -> Game.tick_menu_globe s ~dt | _ -> s
    in
    if s.mode = Game.Round && Game.drain_deadline () then
      Game.lock_in s ~timed_out:true
    else s

  let enter (s : state) = s

  let service_select (s : state) _ = s

  let service_cycle (s : state) _ = s

  let handle_modal_key (s : state) _ ~size:_ = s

  let next_page (s : state) = s.next_page

  let keymap (_ : state) = []

  let handled_keys () = []

  let back (s : state) = go_back s

  let has_modal _ = false
end

include Demo_shared.Demo_page.MakeSimple (Inner)
