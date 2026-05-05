(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(** TUI page wiring for MIAOU Links — chill golf. *)

module Inner = struct
  let tutorial_title = "MIAOU Links"

  let tutorial_markdown = [%blob "README.md"]

  module FB = Miaou_widgets_display.Framebuffer_widget

  type state = {
    model : Model.t;
    fb : FB.t;
    mutable view_cache : string;
    mutable view_cache_t : float;
  }

  type msg = unit

  let init () =
    {
      model = Model.init ();
      fb = FB.create ();
      view_cache = "";
      view_cache_t = -1.0;
    }

  let update s _ = s

  (* Throttle the expensive FB encode to ~10 fps.  Text-only screens are
     cheap anyway; for gameplay screens this prevents write-buffer saturation
     (exit-137 / SIGKILL) from 10+ MB/s of ANSI output.
     We use model.mode_t (which resets to 0 on state transitions) so the
     condition dt > 0 naturally forces a fresh render after every mode switch. *)
  let view s ~focus:_ ~size =
    let t = s.model.mode_t in
    let dt = t -. s.view_cache_t in
    if s.view_cache <> "" && dt > 0.0 && dt < 0.100 then s.view_cache
    else begin
      let result = View.render s.model ~fb:s.fb ~size in
      s.view_cache <- result ;
      s.view_cache_t <- t ;
      result
    end

  let go_back (s : state) =
    s.model.next_page <- Some Demo_shared.Demo_config.launcher_page_name ;
    s

  (* ---------- key handlers per state ---------- *)

  let handle_key_title (s : state) key =
    (match key with
    | "Enter" | " " | "Space" -> Model.begin_new_run s.model
    | "o" | "O" ->
        (* Classic 18-hole tour (legacy round flow). [t] is reserved by
           the demo-page wrapper for the tutorial modal. *)
        Model.begin_round s.model
    | "Escape" | "Esc" -> ignore (go_back s)
    | _ -> ()) ;
    s

  let handle_key_shop (s : state) (sd : Model.shop_data) key =
    (* n_options items + 1 SKIP entry at the bottom. *)
    let n_total = Array.length sd.s_options + 1 in
    (match key with
    | "Up" | "k" | "K" -> if sd.s_cursor > 0 then sd.s_cursor <- sd.s_cursor - 1
    | "Down" | "j" | "J" ->
        if sd.s_cursor < n_total - 1 then sd.s_cursor <- sd.s_cursor + 1
    | "Enter" | " " | "Space" ->
        if sd.s_cursor = n_total - 1 then
          (* SKIP selected: start the run immediately. *)
          Model.leave_shop s.model
        else Model.buy_from_shop s.model sd
    | "s" | "S" -> Model.leave_shop s.model
    | "Escape" | "Esc" -> Model.leave_shop s.model
    | _ -> ()) ;
    s

  let handle_key_perk_pick (s : state) (pp : Model.perk_pick_data) key =
    (match key with
    | "Up" | "k" | "K" ->
        if pp.pp_cursor > 0 then pp.pp_cursor <- pp.pp_cursor - 1
    | "Down" | "j" | "J" ->
        if pp.pp_cursor < Array.length pp.pp_options - 1 then
          pp.pp_cursor <- pp.pp_cursor + 1
    | "Enter" | " " | "Space" -> Model.pick_perk s.model pp
    | "Escape" | "Esc" ->
        (* Skip and continue. *)
        Model.begin_run_hole s.model
    | _ -> ()) ;
    s

  let handle_key_run_end (s : state) key =
    (match key with
    | "Enter" | " " | "Space" | "Escape" | "Esc" ->
        s.model.run <- None ;
        s.model.mode <- Model.Title ;
        s.model.mode_t <- 0.0
    | _ -> ()) ;
    s

  let handle_key_course_select (s : state) (cs : Model.t) key =
    (match s.model.mode with
    | Model.Course_select sel -> begin
        match key with
        | "Up" | "k" | "K" ->
            if sel.cursor > 0 then sel.cursor <- sel.cursor - 1
        | "Down" | "j" | "J" ->
            if sel.cursor < Courses.count - 1 then sel.cursor <- sel.cursor + 1
        | "Enter" | " " | "Space" -> Model.begin_hole s.model ~idx:sel.cursor
        | "Escape" | "Esc" ->
            s.model.mode <- Model.Title ;
            s.model.mode_t <- 0.0
        | _ -> ()
      end
    | _ -> ()) ;
    let _ = cs in
    s

  let handle_key_aiming (s : state) (a : Model.aiming_data) key =
    (match key with
    | "Left" -> Model.rotate_aim a ~step:(-.Model.aim_step_big)
    | "Right" -> Model.rotate_aim a ~step:Model.aim_step_big
    | "[" -> Model.rotate_aim a ~step:(-.Model.aim_step_small)
    | "]" -> Model.rotate_aim a ~step:Model.aim_step_small
    | "c" | "C" -> Model.cycle_club a.a_game
    | " " | "Space" | "Enter" -> s.model.mode <- Model.aim_to_powering a
    | "Escape" | "Esc" ->
        if s.model.run <> None then begin
          s.model.run <- None ;
          s.model.mode <- Model.Title ;
          s.model.mode_t <- 0.0
        end
        else begin
          s.model.mode <- Model.Course_select {cursor = a.a_game.hole_idx} ;
          s.model.mode_t <- 0.0
        end
    | _ -> ()) ;
    s

  let handle_key_powering (s : state) (p : Model.powering_data) key =
    (match key with
    | "Left" -> Model.rotate_aim_powering p ~step:(-.Model.aim_step_big)
    | "Right" -> Model.rotate_aim_powering p ~step:Model.aim_step_big
    | "[" -> Model.rotate_aim_powering p ~step:(-.Model.aim_step_small)
    | "]" -> Model.rotate_aim_powering p ~step:Model.aim_step_small
    | " " | "Space" | "Enter" ->
        Model.swing s.model p ;
        s.model.mode <- Model.In_flight {f_game = p.game; f_t = 0.0}
    | "Escape" | "Esc" ->
        s.model.mode <- Model.Aiming {a_game = p.game; a_aim = p.aim_angle}
    | _ -> ()) ;
    s

  let handle_key_in_flight (s : state) _ key =
    (match key with
    | "Escape" | "Esc" ->
        (* Allow esc-out even mid-flight — back to course select. *)
        ()
    | _ -> ()) ;
    let _ = s in
    s

  let handle_key_hole_clear (s : state) (c : Model.clear_data) key =
    (match key with
    | "Enter" | " " | "Space" ->
        if s.model.run <> None then
          Model.advance_after_run_hole s.model c.c_game
        else Model.advance_after_hole s.model c.c_game
    | "Escape" | "Esc" ->
        s.model.run <- None ;
        s.model.mode <- Model.Title ;
        s.model.mode_t <- 0.0
    | _ -> ()) ;
    s

  let handle_key_card_summary (s : state) _ key =
    (match key with
    | "Enter" | " " | "Space" ->
        s.model.mode <- Model.Title ;
        s.model.mode_t <- 0.0
    | "Escape" | "Esc" -> ignore (go_back s)
    | _ -> ()) ;
    s

  let handle_key_hole_preview (s : state) (hp : Model.hole_preview_data) key =
    (match key with
    | " " | "Space" | "Enter" ->
        (* Skip the preview and go immediately to Aiming. *)
        s.model.mode <- Model.Aiming {a_game = hp.hp_game; a_aim = 0.0} ;
        s.model.mode_t <- 0.0
    | "Escape" | "Esc" ->
        s.model.run <- None ;
        s.model.mode <- Model.Title ;
        s.model.mode_t <- 0.0
    | _ -> ()) ;
    s

  let handle_key (s : state) key ~size:_ =
    match s.model.mode with
    | Model.Title -> handle_key_title s key
    | Model.New_run_intro -> handle_key_title s key
    | Model.In_shop sd -> handle_key_shop s sd key
    | Model.Course_select _ -> handle_key_course_select s s.model key
    | Model.Hole_preview hp -> handle_key_hole_preview s hp key
    | Model.Aiming a -> handle_key_aiming s a key
    | Model.Powering p -> handle_key_powering s p key
    | Model.In_flight f -> handle_key_in_flight s f key
    | Model.Hole_clear c -> handle_key_hole_clear s c key
    | Model.Perk_pick pp -> handle_key_perk_pick s pp key
    | Model.Boss_intro _ ->
        (* Skippable boss intro — Enter advances faster. *)
        (match key with
        | "Enter" | " " | "Space" -> (
            match s.model.run with
            | None -> ()
            | Some r ->
                let idx = r.hole_seq.(r.run_pos) in
                let g = Model.make_game ~hole_idx:idx in
                s.model.mode <- Model.Aiming {a_game = g; a_aim = 0.0} ;
                s.model.mode_t <- 0.0)
        | "Escape" | "Esc" ->
            s.model.run <- None ;
            s.model.mode <- Model.Title ;
            s.model.mode_t <- 0.0
        | _ -> ()) ;
        s
    | Model.Run_complete _ -> handle_key_run_end s key
    | Model.Run_failed _ -> handle_key_run_end s key
    | Model.Card_summary sd -> handle_key_card_summary s sd key

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
