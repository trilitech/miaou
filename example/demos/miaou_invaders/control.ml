(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

module Cw = Miaou_widgets_layout.Canvas_widget
module Anim = Miaou_helpers.Animation
open Model
open Logic
open Render

let register_timers () =
  match Miaou_interfaces.Timer.get () with
  | None -> ()
  | Some timer ->
      timer.set_interval ~id:"alien_step" 0.5 ;
      timer.set_interval ~id:"alien_shoot" 0.8

let view s ~focus:_ ~size =
  let rows = max 22 (min 36 (size.LTerm_geom.rows - 1)) in
  let game_rows = max 16 (rows - 5) in
  let cols = max 24 (min size.LTerm_geom.cols max_cols) in
  let s =
    if s.field_w <> cols || s.field_h <> game_rows then
      {s with field_w = cols; field_h = game_rows}
    else s
  in
  let cw = Cw.ensure s.cw ~rows ~cols in
  (match Cw.canvas cw with Some c -> draw_game s c | None -> ()) ;
  Cw.render cw ~size:{LTerm_geom.rows; cols}

let go_back s =
  {s with next_page = Some Demo_shared.Demo_config.launcher_page_name}

let start_run_with_mode s ai_mode =
  let s' = init_state ~field_w:s.field_w ~field_h:s.field_h in
  {
    s' with
    cw = s.cw;
    timers_registered = s.timers_registered;
    show_title = false;
    ai_mode;
    frame = s.frame;
  }

let start_run s = start_run_with_mode s false

let fire s =
  if s.show_title then s
  else
    match s.phase with
    | Playing ->
        if s.fire_cd > 0.0 then s
        else
          let ship_y = muzzle_y_for s.field_h in
          let kind = shot_kind_of s.shot_color in
          let p = max 1 s.shot_power in
          let mk ?(vx = 0.0) ?(vy = -.bullet_speed) ?(wave_amp = 0.0)
              ?(wave_freq = 0.0) ?(dmg = 1) ?(pierce = 0) ?(glyph = "|")
              ?(fg = 51) () =
            {
              ppos = {x = s.ship_x; y = ship_y};
              vx;
              vy;
              wave_amp;
              wave_freq;
              age = 0.0;
              dmg;
              pierce;
              active = true;
              glyph;
              fg;
            }
          in
          let spawned, fire_cd =
            match kind with
            | Basic -> ([mk ~dmg:(1 + (p / 2)) ()], 0.16)
            | Flame ->
                let main =
                  [
                    mk
                      ~vy:(-.(bullet_speed +. (float_of_int p *. 3.0)))
                      ~wave_amp:(0.6 +. (float_of_int p *. 0.2))
                      ~wave_freq:(10.0 +. (float_of_int p *. 1.2))
                      ~dmg:(1 + (p * 2))
                      ~pierce:(max 0 (p - 1))
                      ~glyph:"!"
                      ~fg:203
                      ();
                  ]
                in
                let side =
                  if p >= 2 then
                    [
                      mk
                        ~vx:(-3.0 -. float_of_int p)
                        ~vy:(-.(bullet_speed *. 0.95))
                        ~glyph:"/"
                        ~fg:209
                        ();
                      mk
                        ~vx:(3.0 +. float_of_int p)
                        ~vy:(-.(bullet_speed *. 0.95))
                        ~glyph:"\\"
                        ~fg:209
                        ();
                    ]
                  else
                    []
                    @
                    if p >= 5 then
                      [
                        mk
                          ~vx:(-8.0)
                          ~vy:(-.(bullet_speed *. 0.9))
                          ~glyph:"/"
                          ~fg:214
                          ~dmg:2
                          ();
                        mk
                          ~vx:8.0
                          ~vy:(-.(bullet_speed *. 0.9))
                          ~glyph:"\\"
                          ~fg:214
                          ~dmg:2
                          ();
                      ]
                    else []
                in
                (main @ side, 0.13 -. (float_of_int (p - 1) *. 0.015))
            | Burst ->
                let angles =
                  if p = 1 then [(-3.0, -0.92)]
                  else if p = 2 then [(-5.0, -0.88); (0.0, -1.0); (5.0, -0.88)]
                  else if p = 3 then
                    [
                      (-7.0, -0.84);
                      (-3.5, -0.92);
                      (0.0, -1.0);
                      (3.5, -0.92);
                      (7.0, -0.84);
                    ]
                  else if p = 4 then
                    [
                      (-9.0, -0.8);
                      (-6.0, -0.86);
                      (-3.0, -0.93);
                      (0.0, -1.0);
                      (3.0, -0.93);
                      (6.0, -0.86);
                      (9.0, -0.8);
                    ]
                  else
                    [
                      (-10.0, -0.78);
                      (-7.0, -0.84);
                      (-4.0, -0.9);
                      (-2.0, -0.95);
                      (0.0, -1.0);
                      (2.0, -0.95);
                      (4.0, -0.9);
                      (7.0, -0.84);
                      (10.0, -0.78);
                    ]
                in
                ( List.map
                    (fun (vx, vf) ->
                      mk
                        ~vx
                        ~vy:(bullet_speed *. vf)
                        ~glyph:"|"
                        ~fg:120
                        ~dmg:(1 + (p / 2))
                        ())
                    angles,
                  0.21 -. (float_of_int (p - 1) *. 0.02) )
            | Pierce ->
                let main =
                  [
                    mk
                      ~vy:(-.(bullet_speed *. 1.08))
                      ~wave_amp:(0.9 +. (float_of_int p *. 0.3))
                      ~wave_freq:(8.0 +. (float_of_int p *. 1.3))
                      ~dmg:(2 + p)
                      ~pierce:(p + 2)
                      ~glyph:":"
                      ~fg:45
                      ();
                  ]
                in
                let side =
                  if p >= 3 then
                    [
                      mk
                        ~vx:(-4.0)
                        ~vy:(-.(bullet_speed *. 1.0))
                        ~pierce:1
                        ~glyph:"/"
                        ~fg:39
                        ();
                      mk
                        ~vx:4.0
                        ~vy:(-.(bullet_speed *. 1.0))
                        ~pierce:1
                        ~glyph:"\\"
                        ~fg:39
                        ();
                    ]
                  else []
                in
                (main @ side, 0.18 -. (float_of_int (p - 1) *. 0.015))
          in
          {s with bullets = spawned @ s.bullets; fire_cd = max 0.06 fire_cd}
    | _ -> s

let move s delta =
  if s.show_title then s
  else
    match s.phase with
    | Playing | Wave_clear _ ->
        let dx = float_of_int delta *. 2.0 in
        let half = float_of_int (ship_half_width s) in
        let ship_x =
          clamp_f
            (1.0 +. half)
            (float_of_int (s.field_w - 2) -. half)
            (s.ship_x +. dx)
        in
        {s with ship_x}
    | Paused -> s
    | Game_over _ -> s

let ai_target_x s =
  match
    List.find_opt (fun (a : alien) -> a.alive && a.kind = Boss) s.aliens
  with
  | Some boss -> boss.pos.x
  | None -> (
      let best =
        List.fold_left
          (fun acc (a : alien) ->
            if not a.alive then acc
            else
              match acc with
              | None -> Some a
              | Some cur -> if a.pos.y > cur.pos.y then Some a else acc)
          None
          s.aliens
      in
      match best with Some a -> a.pos.x | None -> s.ship_x)

let ai_danger s =
  let ship_y = ship_y_for s.field_h in
  List.fold_left
    (fun acc (b : projectile) ->
      if b.vy <= 0.0 then acc
      else
        let dy = ship_y -. b.ppos.y in
        if dy < 0.0 then acc
        else
          let t_hit = dy /. (b.vy +. 0.001) in
          if t_hit > 1.2 then acc
          else
            let x_pred = b.ppos.x +. (b.vx *. t_hit) in
            let near = Float.abs (x_pred -. s.ship_x) < 3.6 in
            if not near then acc
            else
              match acc with
              | None -> Some (x_pred, t_hit)
              | Some (_, best_t) ->
                  if t_hit < best_t then Some (x_pred, t_hit) else acc)
    None
    s.alien_bullets

let ai_bonus_target s =
  let ship_y = ship_y_for s.field_h in
  let near_bonus =
    List.filter
      (fun (b : bonus) -> b.bpos.y > ship_y -. 8.0 && b.bpos.y < ship_y +. 0.8)
      s.bonuses
  in
  match near_bonus with
  | [] -> None
  | _ ->
      let best =
        List.fold_left
          (fun acc (b : bonus) ->
            let d = Float.abs (b.bpos.x -. s.ship_x) in
            match acc with
            | None -> Some (b.bpos.x, d)
            | Some (_, d0) -> if d < d0 then Some (b.bpos.x, d) else acc)
          None
          near_bonus
      in
      Option.map fst best

let ai_control s =
  if not s.ai_mode then s
  else
    let danger = ai_danger s in
    let target_x =
      match danger with
      | Some (x_pred, _) ->
          let dir = if x_pred <= s.ship_x then 1.0 else -1.0 in
          clamp_f 2.0 (float_of_int (s.field_w - 3)) (s.ship_x +. (dir *. 4.0))
      | None -> (
          match ai_bonus_target s with Some bx -> bx | None -> ai_target_x s)
    in
    let s =
      if target_x > s.ship_x +. 0.8 then move s 1
      else if target_x < s.ship_x -. 0.8 then move s (-1)
      else s
    in
    let kind = shot_kind_of s.shot_color in
    let fire_tol =
      match kind with
      | Burst -> 3.3
      | Flame -> 2.6
      | Pierce -> 2.8
      | Basic -> 1.7
    in
    let target_x = ai_target_x s in
    let aligned = Float.abs (target_x -. s.ship_x) <= fire_tol in
    let emergency =
      match danger with Some (_, t) -> t < 0.35 | None -> false
    in
    if aligned && not emergency then fire s else s

let handle_key s key_str ~size:_ =
  match Miaou.Core.Keys.of_string key_str with
  | Some Miaou.Core.Keys.Escape -> go_back s
  | Some Miaou.Core.Keys.Enter when s.show_title -> start_run s
  | Some (Miaou.Core.Keys.Char "d") when s.show_title ->
      start_run_with_mode s true
  | Some (Miaou.Core.Keys.Char "D") when s.show_title ->
      start_run_with_mode s true
  | Some (Miaou.Core.Keys.Char " ") when s.show_title -> start_run s
  | Some (Miaou.Core.Keys.Char " ") | Some (Miaou.Core.Keys.Char "Space") ->
      fire s
  | Some (Miaou.Core.Keys.Char "p") | Some (Miaou.Core.Keys.Char "P") -> (
      if s.show_title then s
      else
        match s.phase with
        | Playing -> {s with phase = Paused}
        | Paused -> {s with phase = Playing}
        | _ -> s)
  | Some Miaou.Core.Keys.Left | Some (Miaou.Core.Keys.Char "h") -> move s (-1)
  | Some Miaou.Core.Keys.Right | Some (Miaou.Core.Keys.Char "l") -> move s 1
  | Some (Miaou.Core.Keys.Char k) when String.lowercase_ascii k = "r" ->
      let s' = start_run s in
      register_timers () ;
      {s' with timers_registered = true}
  | _ -> s

let refresh s =
  let s =
    if not s.timers_registered then begin
      register_timers () ;
      {s with timers_registered = true}
    end
    else s
  in
  let s =
    let canvas_rows = Cw.rows s.cw in
    let canvas_cols = Cw.cols s.cw in
    let field_h =
      if canvas_rows > 0 then max 16 (canvas_rows - 5) else s.field_h
    in
    let field_w = if canvas_cols > 0 then max 24 canvas_cols else s.field_w in
    if s.field_w <> field_w || s.field_h <> field_h then
      {s with field_w; field_h}
    else s
  in
  let dt =
    match Miaou_interfaces.Clock.get () with
    | Some clock -> clamp_f (1.0 /. 240.0) (1.0 /. 15.0) (clock.dt ())
    | None -> 1.0 /. 60.0
  in
  if s.show_title then
    {
      s with
      frame = s.frame + 1;
      shake = max 0.0 (s.shake -. dt);
      ship_morph = tick_anim_opt dt s.ship_morph;
      life_popups = tick_life_popups dt s.life_popups;
      explosions = tick_explosions dt s.explosions;
    }
  else
    let s =
      match s.phase with
      | Paused ->
          {
            s with
            frame = s.frame + 1;
            boss_intro = tick_boss_intro dt s.boss_intro;
            ship_morph = tick_anim_opt dt s.ship_morph;
            life_popups = tick_life_popups dt s.life_popups;
            shake = max 0.0 (s.shake -. dt);
          }
      | _ ->
          {
            s with
            frame = s.frame + 1;
            fire_cd = max 0.0 (s.fire_cd -. dt);
            boss_intro = tick_boss_intro dt s.boss_intro;
            ship_morph = tick_anim_opt dt s.ship_morph;
            life_popups = tick_life_popups dt s.life_popups;
            shake = max 0.0 (s.shake -. dt);
            bullets = move_projectiles dt s.bullets ~field_h:s.field_h;
            alien_bullets =
              move_projectiles dt s.alien_bullets ~field_h:s.field_h;
            bonuses = move_bonuses dt s.bonuses ~field_h:s.field_h;
            explosions = tick_explosions dt s.explosions;
            phase = tick_phase dt s.phase;
          }
    in
    match s.phase with
    | Paused -> s
    | Game_over anim ->
        if s.ai_mode && Anim.finished anim then (
          let s' = start_run_with_mode s true in
          register_timers () ;
          {s' with timers_registered = true})
        else s
    | Wave_clear anim -> if Anim.finished anim then next_level s else s
    | Playing ->
        let s = ai_control s in
        let step_acc = s.step_acc +. dt in
        let shoot_acc = s.shoot_acc +. dt in
        let s =
          if step_acc >= step_interval_for s.level then
            let s' = step_aliens s in
            {s' with step_acc = 0.0}
          else {s with step_acc}
        in
        let s =
          if shoot_acc >= shoot_interval_for s.level then
            let s' = alien_shoot s in
            {s' with shoot_acc = 0.0}
          else {s with shoot_acc}
        in
        let s = check_bullet_alien_collisions s in
        let s = check_alien_bullet_ship s in
        let s = collect_bonuses s in
        let alive = List.exists (fun a -> a.alive) s.aliens in
        if not alive then
          {
            s with
            phase =
              Wave_clear (Anim.create ~duration:0.9 ~easing:Ease_in_out ());
          }
        else s

let enter s =
  register_timers () ;
  {s with timers_registered = true}

let service_select s _ = s

let service_cycle s _ = s

let handle_modal_key s _ ~size:_ = s

let next_page s = s.next_page

let keymap _ = []

let handled_keys () =
  Miaou.Core.Keys.
    [
      Left;
      Right;
      Enter;
      Char "h";
      Char "l";
      Char " ";
      Char "p";
      Char "P";
      Char "d";
      Char "D";
      Char "r";
      Escape;
    ]

let back s = go_back s

let has_modal _ = false
