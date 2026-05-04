(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

module Arcade_kit = Demo_shared.Arcade_kit

(** TUI page wiring for MIAOU Force.

    Continuous-input model: the page records the time of each "press"
    of an arrow key and treats the key as held for ~120 ms after the
    last press. With most terminals delivering arrow autorepeat at
    20–40 Hz, this gives smooth analog-feeling motion without needing
    keyup events. *)

module Inner = struct
  let tutorial_title = "MIAOU Force"

  let tutorial_markdown = [%blob "README.md"]

  module FB = Miaou_widgets_display.Framebuffer_widget

  type state = {
    model : Model.t;
    mutable input : input_buffer;
    fb : FB.t;
    mutable view_cache : string;
    mutable view_cache_t : float;
  }

  and input_buffer = {
    mutable t_left : float;
    mutable t_right : float;
    mutable t_up : float;
    mutable t_down : float;
    mutable t_fire : float;
    mutable last_now : float;
    (* one-shots consumed exactly once per tick *)
    mutable toggle_force : bool;
    (* Turn-based step requests: number of 16-ms frames to advance on the
       next refresh. The page's [refresh] consumes this counter. The
       buffered fire flag below makes Space work in turn-based mode even
       though it was pressed on a different frame than the step key. *)
    mutable step_frames : int;
    mutable buffered_fire : int; (* >0: fire for that many simulated frames *)
  }

  type msg = unit

  let key_hold_window = 0.14

  let now () =
    match Miaou_interfaces.Clock.get () with
    | Some c -> c.now ()
    | None -> Unix.gettimeofday ()

  let init_input () =
    {
      t_left = 0.;
      t_right = 0.;
      t_up = 0.;
      t_down = 0.;
      t_fire = 0.;
      last_now = 0.;
      toggle_force = false;
      step_frames = 0;
      buffered_fire = 0;
    }

  let init () =
    {
      model = Model.init ();
      input = init_input ();
      fb = FB.create ();
      view_cache = "";
      view_cache_t = -1.0;
    }

  let update (s : state) _ = s

  (* Throttle to ~15 fps. The game loop runs at 60 Hz but rendering the
     framebuffer at every tick saturates the terminal write buffer. *)
  let view (s : state) ~focus:_ ~size =
    let t = s.model.mode_t in
    let dt = t -. s.view_cache_t in
    if s.view_cache <> "" && dt > 0.0 && dt < 0.067 then s.view_cache
    else begin
      let result = View.render s.model ~fb:s.fb ~size in
      s.view_cache <- result ;
      s.view_cache_t <- t ;
      result
    end

  let go_back (s : state) =
    s.model.next_page <- Some Demo_shared.Demo_config.launcher_page_name ;
    s

  (* Helper: start a specific level, preserving current score and weapons. *)
  let start_level_n (s : state) level =
    let events, palette = Levels.get_level level in
    Model.start_level s.model ~level ~events ~palette ;
    s.model.mode <- Model.Playing ;
    s.model.mode_t <- 0.0

  (* Build an [Model.input] from the input buffer for this frame.

     In turn-based mode, we ignore the wall-clock-derived hold window
     (since wall time isn't advancing simulation time) and instead use
     directional flags refreshed each step. We also drive [fire] from
     the [buffered_fire] counter so charge-then-release beam works:
     while buffered_fire > 1 the player is "holding fire"; on the last
     frame of the buffer the flag becomes false, mimicking a release. *)
  let snapshot_input s ~now ~turn_based =
    if turn_based then begin
      let dx =
        let l = if now -. s.input.t_left < 0.5 then -1.0 else 0.0 in
        let r = if now -. s.input.t_right < 0.5 then 1.0 else 0.0 in
        l +. r
      in
      let dy =
        let u = if now -. s.input.t_up < 0.5 then -1.0 else 0.0 in
        let d = if now -. s.input.t_down < 0.5 then 1.0 else 0.0 in
        u +. d
      in
      let fire = s.input.buffered_fire > 0 in
      if s.input.buffered_fire > 0 then
        s.input.buffered_fire <- s.input.buffered_fire - 1 ;
      let toggle_force = s.input.toggle_force in
      s.input.toggle_force <- false ;
      (* In turn-based, key timestamps decay one step at a time. Push them
         back so a single arrow press only counts for one step. *)
      s.input.t_left <- 0. ;
      s.input.t_right <- 0. ;
      s.input.t_up <- 0. ;
      s.input.t_down <- 0. ;
      {Model.dx; dy; fire; toggle_force}
    end
    else begin
      let dx =
        let l = if now -. s.input.t_left < key_hold_window then -1.0 else 0.0 in
        let r = if now -. s.input.t_right < key_hold_window then 1.0 else 0.0 in
        l +. r
      in
      let dy =
        let u = if now -. s.input.t_up < key_hold_window then -1.0 else 0.0 in
        let d = if now -. s.input.t_down < key_hold_window then 1.0 else 0.0 in
        u +. d
      in
      let fire = now -. s.input.t_fire < key_hold_window in
      let toggle_force = s.input.toggle_force in
      s.input.toggle_force <- false ;
      {Model.dx; dy; fire; toggle_force}
    end

  let handle_key_playing (s : state) key =
    let n = now () in
    let tb = s.model.turn_based in
    (match key with
    | "Left" -> s.input.t_left <- n
    | "Right" -> s.input.t_right <- n
    | "Up" -> s.input.t_up <- n
    | "Down" -> s.input.t_down <- n
    | "Space" | " " ->
        s.input.t_fire <- n ;
        if tb then
          (* In turn-based, buffer fire for a chunk of simulated frames.
             Consecutive Space presses accumulate so the player can charge
             the beam across many [n]/[N]/[b] steps. *)
          s.input.buffered_fire <- s.input.buffered_fire + 8
    | "d" | "D" -> s.input.toggle_force <- true
    | "f" | "F" -> Model.flip_force s.model
    | "n" when tb -> s.input.step_frames <- s.input.step_frames + 1
    | "N" when tb -> s.input.step_frames <- s.input.step_frames + 10
    | ("b" | "B") when tb -> s.input.step_frames <- s.input.step_frames + 60
    | "Escape" | "Esc" ->
        s.model.mode <- Model.Title ;
        s.model.mode_t <- 0.0
    | _ -> ()) ;
    s

  let handle_key_title (s : state) key =
    (match key with
    | "Enter" | " " | "Space" ->
        let events, palette = Levels.get_level 1 in
        Model.begin_game s.model ~level:1 ~events ~palette
    | "s" | "S" ->
        s.model.mode <- Model.Level_select ;
        s.model.mode_t <- 0.0 ;
        s.model.level_select_cursor <- 0
    | "Escape" | "Esc" -> ignore (go_back s)
    | _ -> ()) ;
    s

  let handle_key_game_over (s : state) key =
    (match key with
    | "Enter" | " " | "Space" ->
        s.model.mode <- Model.Title ;
        s.model.mode_t <- 0.0
    | "s" | "S" ->
        s.model.mode <- Model.Level_select ;
        s.model.mode_t <- 0.0 ;
        s.model.level_select_cursor <- 0
    | "Escape" | "Esc" -> ignore (go_back s)
    | _ -> ()) ;
    s

  let handle_key_level_clear (s : state) key =
    (match key with
    | "Enter" | " " | "Space" ->
        let next = s.model.level + 1 in
        if next <= Levels.max_level then begin
          (* Advance to next level. Carry score and weapons. *)
          start_level_n s next
        end
        else begin
          (* All levels cleared: record best and go to title. *)
          s.model.best <-
            Arcade_kit.Score_store.record ~demo:"miaou_force" s.model.score ;
          s.model.mode <- Model.Title ;
          s.model.mode_t <- 0.0
        end
    | "Escape" | "Esc" ->
        s.model.best <-
          Arcade_kit.Score_store.record ~demo:"miaou_force" s.model.score ;
        ignore (go_back s)
    | _ -> ()) ;
    s

  let handle_key_level_select (s : state) key =
    (match key with
    | "Up" ->
        if s.model.level_select_cursor > 0 then
          s.model.level_select_cursor <- s.model.level_select_cursor - 1
    | "Down" ->
        if s.model.level_select_cursor < Levels.max_level - 1 then
          s.model.level_select_cursor <- s.model.level_select_cursor + 1
    | "Enter" | " " | "Space" ->
        let lvl = s.model.level_select_cursor + 1 in
        let events, palette = Levels.get_level lvl in
        Model.begin_game s.model ~level:lvl ~events ~palette
    | "Escape" | "Esc" ->
        s.model.mode <- Model.Title ;
        s.model.mode_t <- 0.0
    | _ -> ()) ;
    s

  let handle_key_level_clear_anim (s : state) key =
    (* Space or Enter skips the cinematic and jumps straight to Level_clear. *)
    (match key with
    | "Enter" | " " | "Space" ->
        s.model.mode <- Model.Level_clear ;
        s.model.mode_t <- 0.0
    | "Escape" | "Esc" ->
        s.model.mode <- Model.Level_clear ;
        s.model.mode_t <- 0.0
    | _ -> ()) ;
    s

  let handle_key (s : state) key ~size:_ =
    match s.model.mode with
    | Model.Title -> handle_key_title s key
    | Model.Playing -> handle_key_playing s key
    | Model.Game_over -> handle_key_game_over s key
    | Model.Level_clear -> handle_key_level_clear s key
    | Model.Level_clear_anim _ -> handle_key_level_clear_anim s key
    | Model.Level_select -> handle_key_level_select s key

  let move (s : state) _ = s

  let refresh (s : state) =
    let n = now () in
    if s.model.turn_based then begin
      (* Turn-based: only advance when the user has queued steps. Each
         step advances exactly one simulated 16-ms frame. *)
      let frame_dt = 1.0 /. 60.0 in
      let pending = s.input.step_frames in
      if pending > 0 then begin
        for _ = 1 to pending do
          let input = snapshot_input s ~now:n ~turn_based:true in
          Model.tick s.model ~input ~dt:frame_dt ;
          s.model.frame_counter <- s.model.frame_counter + 1
        done ;
        s.input.step_frames <- 0
      end ;
      s
    end
    else begin
      let dt =
        match Miaou_interfaces.Clock.get () with
        | Some c -> c.dt ()
        | None -> 1.0 /. 30.0
      in
      let input = snapshot_input s ~now:n ~turn_based:false in
      Model.tick s.model ~input ~dt ;
      s
    end

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
