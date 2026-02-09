(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

module Anim = Miaou_helpers.Animation
open Model

let move_projectiles dt (bullets : projectile list) ~field_h =
  let max_y = Float.of_int field_h in
  List.filter_map
    (fun (b : projectile) ->
      if not b.active then None
      else
        let age' = b.age +. dt in
        let lateral =
          if b.wave_amp = 0.0 then 0.0
          else Float.sin (age' *. b.wave_freq) *. b.wave_amp
        in
        let x' = b.ppos.x +. ((b.vx +. lateral) *. dt) in
        let y' = b.ppos.y +. (b.vy *. dt) in
        if y' < 0.0 || y' > max_y || x' < 0.0 || x' > 200.0 then None
        else Some {b with ppos = {x = x'; y = y'}; age = age'})
    bullets

let move_bonuses dt bonuses ~field_h =
  let max_y = Float.of_int field_h in
  List.filter_map
    (fun (b : bonus) ->
      if not b.active then None
      else
        let x' = b.bpos.x +. (Float.sin b.phase *. 0.25) in
        let y' = b.bpos.y +. (b.vy *. dt) in
        let phase' = b.phase +. (dt *. 9.0) in
        if y' > max_y then None
        else Some {b with bpos = {x = x'; y = y'}; phase = phase'})
    bonuses

let apply_powerup s color =
  let shot_color, shot_power =
    match s.shot_color with
    | Some c when c = color -> (Some color, min 6 (s.shot_power + 1))
    | _ -> (Some color, 1)
  in
  let lucky_seed =
    (s.frame * 13) + (s.level * 17) + s.score
    + match color with Ruby -> 3 | Emerald -> 7 | Sapphire -> 11
  in
  let bonus_life = if s.lives < 6 && lucky_seed mod 61 = 0 then 1 else 0 in
  let life_popups =
    if bonus_life = 0 then s.life_popups
    else
      {
        lpos = {x = s.ship_x; y = Float.of_int (s.field_h - 3)};
        lanim = Anim.create ~duration:0.9 ~easing:Ease_out ();
      }
      :: s.life_popups
  in
  {
    s with
    shot_color;
    shot_power;
    lives = s.lives + bonus_life;
    life_popups;
    ship_morph = Some (Anim.create ~duration:0.45 ~easing:Ease_in_out ());
    explosions =
      s.explosions
      @ spawn_explosion ~x:s.ship_x ~y:(Float.of_int (s.field_h - 3)) ~big:false;
  }

let collect_bonuses s =
  let ship_y = Float.of_int (s.field_h - 2) in
  let grab_x = float_of_int (ship_half_width s + 1) in
  let rec loop bonuses kept st =
    match bonuses with
    | [] -> {st with bonuses = List.rev kept}
    | b :: rest ->
        if
          Float.abs (b.bpos.x -. st.ship_x) < grab_x
          && Float.abs (b.bpos.y -. ship_y) < 1.2
        then loop rest kept (apply_powerup st b.color)
        else loop rest (b :: kept) st
  in
  loop s.bonuses [] s

let maybe_drop_bonus s alien =
  let base =
    (s.frame * 17) + (Float.to_int alien.pos.x * 19) + (s.level * 11) + s.score
  in
  let roll = base mod 100 in
  let chance =
    match alien.kind with Boss -> 100 | Grunt -> min 35 (7 + (s.level * 2))
  in
  if roll >= chance then None
  else
    let color =
      match base mod 3 with 0 -> Ruby | 1 -> Emerald | _ -> Sapphire
    in
    Some
      {
        bpos = alien.pos;
        color;
        vy = 4.0 +. (float_of_int s.level *. 0.2);
        phase = float_of_int (base mod 10);
        active = true;
      }

let check_bullet_alien_collisions s =
  let aliens = ref s.aliens in
  let gained = ref 0 in
  let extra_lives = ref 0 in
  let spawned_explosions = ref [] in
  let spawned_bonuses = ref [] in
  let update_bullet (b : projectile) =
    if not b.active then b
    else
      let target_opt =
        List.find_opt
          (fun a ->
            if not a.alive then false
            else
              let hit_x = match a.kind with Boss -> 3.5 | Grunt -> 2.2 in
              let hit_y = match a.kind with Boss -> 1.5 | Grunt -> 1.0 in
              Float.abs (b.ppos.x -. a.pos.x) < hit_x
              && Float.abs (b.ppos.y -. a.pos.y) < hit_y)
          !aliens
      in
      match target_opt with
      | None -> b
      | Some target ->
          let hp' = target.hp - b.dmg in
          let killed = hp' <= 0 in
          aliens :=
            List.map
              (fun (a : alien) ->
                if a.aid <> target.aid then a
                else if killed then {a with alive = false; hp = 0}
                else {a with hp = hp'})
              !aliens ;
          if killed then begin
            let pts = match target.kind with Boss -> 150 | Grunt -> 10 in
            gained := !gained + pts ;
            let life_seed =
              (s.frame * 29) + (s.level * 13) + s.score + (target.aid * 7)
            in
            let life_drop =
              match target.kind with
              | Boss -> s.lives < 6 && life_seed mod 4 = 0
              | Grunt -> s.lives < 6 && life_seed mod 91 = 0
            in
            if life_drop then extra_lives := !extra_lives + 1 ;
            spawned_explosions :=
              spawn_explosion
                ~x:target.pos.x
                ~y:target.pos.y
                ~big:(target.kind = Boss)
              @ !spawned_explosions ;
            match maybe_drop_bonus s target with
            | Some bonus -> spawned_bonuses := bonus :: !spawned_bonuses
            | None -> ()
          end
          else
            spawned_explosions :=
              spawn_explosion ~x:target.pos.x ~y:target.pos.y ~big:false
              @ !spawned_explosions ;
          if b.pierce > 0 then {b with pierce = b.pierce - 1}
          else {b with active = false}
  in
  let bullets =
    List.map update_bullet s.bullets
    |> List.filter (fun (b : projectile) -> b.active)
  in
  {
    s with
    aliens = !aliens;
    bullets;
    score = s.score + !gained;
    lives = min 6 (s.lives + !extra_lives);
    life_popups =
      (if !extra_lives > 0 then
         {
           lpos = {x = s.ship_x; y = Float.of_int (s.field_h - 3)};
           lanim = Anim.create ~duration:0.9 ~easing:Ease_out ();
         }
         :: s.life_popups
       else s.life_popups);
    explosions = s.explosions @ !spawned_explosions;
    bonuses = s.bonuses @ !spawned_bonuses;
  }

let check_alien_bullet_ship s =
  let ship_y = Float.of_int (s.field_h - 2) in
  let hit =
    List.exists
      (fun (b : projectile) ->
        Float.abs (b.ppos.x -. s.ship_x) < 2.2
        && Float.abs (b.ppos.y -. ship_y) < 1.0)
      s.alien_bullets
  in
  if not hit then s
  else
    let alien_bullets =
      List.filter
        (fun (b : projectile) ->
          not
            (Float.abs (b.ppos.x -. s.ship_x) < 2.2
            && Float.abs (b.ppos.y -. ship_y) < 1.0))
        s.alien_bullets
    in
    let lives = s.lives - 1 in
    let explosions =
      s.explosions @ spawn_explosion ~x:s.ship_x ~y:ship_y ~big:true
    in
    if lives <= 0 then
      {
        s with
        alien_bullets;
        lives;
        explosions;
        shake = 0.35;
        phase = Game_over (Anim.create ~duration:1.2 ~easing:Ease_in_out ());
      }
    else {s with alien_bullets; lives; explosions; shake = 0.3}

let step_aliens s =
  let h_step =
    if is_boss_level s.level then 1.3 +. (float_of_int s.level *. 0.05)
    else 1.0 +. (float_of_int s.level *. 0.09)
  in
  let hit_edge =
    List.exists
      (fun a ->
        if not a.alive then false
        else
          let edge = match a.kind with Boss -> 5 | Grunt -> 3 in
          (s.alien_dir > 0.0 && a.pos.x >= Float.of_int (s.field_w - edge))
          || (s.alien_dir < 0.0 && a.pos.x <= Float.of_int edge))
      s.aliens
  in
  let drop =
    if is_boss_level s.level then 1.0
    else 1.0 +. (float_of_int (s.level / 8) *. 0.2)
  in
  let aliens, new_dir =
    if hit_edge then
      ( List.map
          (fun a ->
            if a.alive then {a with pos = {x = a.pos.x; y = a.pos.y +. drop}}
            else a)
          s.aliens,
        -.s.alien_dir )
    else
      ( List.map
          (fun a ->
            if a.alive then
              {
                a with
                pos = {x = a.pos.x +. (s.alien_dir *. h_step); y = a.pos.y};
              }
            else a)
          s.aliens,
        s.alien_dir )
  in
  let reached_bottom =
    List.exists
      (fun a -> a.alive && a.pos.y >= Float.of_int (s.field_h - 3))
      aliens
  in
  if reached_bottom then
    {
      s with
      aliens;
      alien_dir = new_dir;
      phase = Game_over (Anim.create ~duration:1.0 ~easing:Ease_in_out ());
    }
  else {s with aliens; alien_dir = new_dir}

let alien_shoot s =
  let alive = List.filter (fun a -> a.alive) s.aliens in
  match alive with
  | [] -> s
  | _ ->
      let idx = (s.frame + s.score + s.level) mod List.length alive in
      let shooter = List.nth alive idx in
      let speed = enemy_bullet_speed_for s.level in
      let bullets =
        match shooter.kind with
        | Boss ->
            [
              {
                ppos = shooter.pos;
                vx = -6.0;
                vy = speed *. 0.9;
                wave_amp = 1.5;
                wave_freq = 9.0;
                age = 0.0;
                dmg = 1;
                pierce = 0;
                active = true;
                glyph = ".";
                fg = 196;
              };
              {
                ppos = shooter.pos;
                vx = 0.0;
                vy = speed;
                wave_amp = 0.0;
                wave_freq = 0.0;
                age = 0.0;
                dmg = 1;
                pierce = 0;
                active = true;
                glyph = ".";
                fg = 203;
              };
              {
                ppos = shooter.pos;
                vx = 6.0;
                vy = speed *. 0.9;
                wave_amp = 1.5;
                wave_freq = 9.0;
                age = 0.0;
                dmg = 1;
                pierce = 0;
                active = true;
                glyph = ".";
                fg = 196;
              };
            ]
        | Grunt ->
            [
              {
                ppos = {x = shooter.pos.x; y = shooter.pos.y +. 1.0};
                vx = 0.0;
                vy = speed;
                wave_amp = 0.0;
                wave_freq = 0.0;
                age = 0.0;
                dmg = 1;
                pierce = 0;
                active = true;
                glyph = ".";
                fg = 196;
              };
            ]
      in
      {s with alien_bullets = bullets @ s.alien_bullets}

let tick_explosions dt explosions =
  List.filter_map
    (fun e ->
      let anim = Anim.tick e.anim ~dt in
      if Anim.finished anim then None
      else
        let epos =
          {
            x = e.epos.x +. (e.evx *. dt);
            y = e.epos.y +. (e.evy *. dt) +. (0.5 *. e.egravity *. dt *. dt);
          }
        in
        let evy = e.evy +. (e.egravity *. dt) in
        Some {e with epos; evy; anim})
    explosions

let tick_phase dt phase =
  match phase with
  | Playing -> Playing
  | Paused -> Paused
  | Wave_clear a -> Wave_clear (Anim.tick a ~dt)
  | Game_over a -> Game_over (Anim.tick a ~dt)

let tick_boss_intro dt = function
  | None -> None
  | Some a ->
      let a' = Anim.tick a ~dt in
      if Anim.finished a' then None else Some a'

let tick_anim_opt dt = function
  | None -> None
  | Some a ->
      let a' = Anim.tick a ~dt in
      if Anim.finished a' then None else Some a'

let tick_life_popups dt popups =
  List.filter_map
    (fun p ->
      let lanim = Anim.tick p.lanim ~dt in
      if Anim.finished lanim then None
      else Some {lpos = {x = p.lpos.x; y = p.lpos.y -. (dt *. 5.0)}; lanim})
    popups

let next_level s =
  let lvl = s.level + 1 in
  let lives = if lvl mod 3 = 0 then min 5 (s.lives + 1) else s.lives in
  {
    s with
    level = lvl;
    lives;
    phase = Playing;
    aliens = make_wave ~field_w:s.field_w ~level:lvl;
    bullets = [];
    alien_bullets = [];
    bonuses = [];
    step_acc = 0.0;
    shoot_acc = 0.0;
    boss_intro =
      (if is_boss_level lvl then
         Some (Anim.create ~duration:1.8 ~easing:Ease_in_out ())
       else None);
    shake = 0.0;
    explosions =
      s.explosions
      @ spawn_explosion
          ~x:(Float.of_int (s.field_w / 2))
          ~y:(Float.of_int (s.field_h / 2))
          ~big:true;
  }
