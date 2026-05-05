(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

module Arcade_kit = Demo_shared.Arcade_kit

(** TUI page wiring for MIAOU Crypt. Step-based input model: arrow /
    WASD keys are discrete tile actions, no held-key continuous motion. *)

module Inner = struct
  let tutorial_title = "MIAOU Crypt"

  let tutorial_markdown = [%blob "README.md"]

  type state = {
    model : Model.t;
    mutable view_cache : string;
    mutable view_cache_t : float;
  }

  type msg = unit

  let init () = {model = Model.init (); view_cache = ""; view_cache_t = -1.0}

  let update s _ = s

  let view s ~focus:_ ~size =
    let t = s.model.mode_t in
    let dt = t -. s.view_cache_t in
    if s.view_cache <> "" && dt > 0.0 && dt < 0.100 then s.view_cache
    else begin
      let result = View.render s.model ~size in
      s.view_cache <- result ;
      s.view_cache_t <- t ;
      result
    end

  let go_back (s : state) =
    s.model.next_page <- Some Demo_shared.Demo_config.launcher_page_name ;
    s

  let handle_key_title (s : state) key =
    (match key with
    | "Enter" | " " | "Space" -> Model.begin_game s.model
    | "Escape" | "Esc" -> ignore (go_back s)
    | _ -> ()) ;
    s

  let handle_key_exploring (s : state) key =
    (match key with
    | "Up" | "w" | "W" -> Model.step_forward s.model
    | "Down" | "s" | "S" -> Model.step_back s.model
    | "Left" -> Model.turn_left s.model
    | "Right" -> Model.turn_right s.model
    | "a" | "A" -> Model.strafe_left s.model
    | "d" | "D" -> Model.strafe_right s.model
    | "Space" | " " -> Model.try_interact s.model
    | "e" | "E" -> ignore (Model.try_spin_attack s.model)
    | "f" | "F" -> Model.use_bomb s.model
    | "m" | "M" -> s.model.show_minimap <- not s.model.show_minimap
    | "i" | "I" -> s.model.show_inventory <- not s.model.show_inventory
    | "n" -> Model.debug_step1 s.model
    | "N" -> Model.debug_step10 s.model
    | "b" | "B" -> Model.debug_step60 s.model
    | "Escape" | "Esc" ->
        s.model.mode <- Model.Title ;
        s.model.mode_t <- 0.0
    | _ -> ()) ;
    s

  let handle_key_cinematic (s : state) key =
    (match key with
    | "Enter" | " " | "Space" | "Escape" | "Esc" ->
        s.model.mode <- Model.Floor_clear ;
        s.model.mode_t <- 0.0
    | _ -> ()) ;
    s

  let handle_key_game_over (s : state) key =
    (match key with
    | "Enter" | " " | "Space" -> Model.begin_game s.model
    | "Escape" | "Esc" -> ignore (go_back s)
    | _ -> ()) ;
    s

  let handle_key_floor_clear (s : state) key =
    (match key with
    | "Enter" | " " | "Space" ->
        if s.model.player.floor >= Floors.count then begin
          s.model.best_floor <-
            Arcade_kit.Score_store.record
              ~demo:"miaou_crypt"
              s.model.deepest_reached ;
          s.model.mode <- Model.Title ;
          s.model.mode_t <- 0.0
        end
        else begin
          let next = s.model.player.floor + 1 in
          Model.load_floor s.model ~n:next ;
          s.model.mode <- Model.Exploring ;
          s.model.mode_t <- 0.0
        end
    | "Escape" | "Esc" -> ignore (go_back s)
    | _ -> ()) ;
    s

  let handle_key (s : state) key ~size:_ =
    match s.model.mode with
    | Model.Title -> handle_key_title s key
    | Model.Exploring -> handle_key_exploring s key
    | Model.Game_over -> handle_key_game_over s key
    | Model.Floor_clear -> handle_key_floor_clear s key
    | Model.Boss_kill_cinematic -> handle_key_cinematic s key
    | Model.Descending_anim _ -> s (* no input during transition *)

  let move (s : state) _ = s

  let refresh (s : state) =
    let dt =
      match Miaou_interfaces.Clock.get () with
      | Some c -> c.dt ()
      | None -> 1.0 /. 30.0
    in
    Model.tick s.model ~dt ;
    s

  let enter (s : state) = s

  let service_select (s : state) _ = s

  let service_cycle (s : state) _ = s

  let handle_modal_key (s : state) _ ~size:_ = s

  let next_page (s : state) = s.model.next_page

  let keymap (_ : state) = []

  let handled_keys () = []

  let back (s : state) = go_back s

  let has_modal _ = false
end

include Demo_shared.Demo_page.MakeSimple (Inner)
