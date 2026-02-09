(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

(** Space Invaders mini-game demo.

    Showcases Canvas, Canvas_widget, Animation, Clock, and Timer
    capabilities working together. *)

module C = Miaou_canvas.Canvas
module Cw = Miaou_widgets_layout.Canvas_widget
module Anim = Miaou_helpers.Animation

module Inner = struct
  let tutorial_title = "Space Invaders"

  let tutorial_markdown = [%blob "README.md"]

  (* -- Game constants ----------------------------------------------------- *)

  let ship_char = "\xe2\x96\xb2" (* ▲ *)

  let alien_chars = [|"\xe2\x99\xa0"; "\xe2\x99\xa3"; "\xe2\x97\x86"|]

  let bullet_char = "\xe2\x94\x83" (* ┃ *)

  let alien_bullet_char = "\xc2\xb7" (* · *)

  let explosion_char = "\xe2\x9c\xb3" (* ✳ *)

  let alien_cols = 8

  let alien_rows = 3

  let alien_step_interval = 0.6

  let alien_shoot_interval = 1.2

  let bullet_speed = 30.0

  let alien_bullet_speed = 12.0

  (* -- Types -------------------------------------------------------------- *)

  type pos = {x : float; y : float}

  type alien = {pos : pos; alive : bool; row : int}

  type bullet = {bpos : pos; active : bool}

  type explosion = {epos : pos; anim : Anim.t}

  type game_phase = Playing | Game_over of Anim.t | Victory of Anim.t

  type state = {
    ship_x : float;
    aliens : alien list;
    bullets : bullet list;
    alien_bullets : bullet list;
    explosions : explosion list;
    alien_dir : float;
    score : int;
    lives : int;
    phase : game_phase;
    field_w : int;
    field_h : int;
    cw : Cw.t;
    timers_registered : bool;
    next_page : string option;
  }

  type msg = unit

  (* -- Helpers ------------------------------------------------------------ *)

  let clamp_f lo hi v = Float.max lo (Float.min hi v)

  let make_aliens ~field_w =
    let start_x = max 2 ((field_w - (alien_cols * 3)) / 2) in
    List.init (alien_rows * alien_cols) (fun i ->
        let r = i / alien_cols in
        let c = i mod alien_cols in
        {
          pos =
            {
              x = Float.of_int (start_x + (c * 3));
              y = Float.of_int (2 + (r * 2));
            };
          alive = true;
          row = r;
        })

  let init_state ~field_w ~field_h =
    {
      ship_x = Float.of_int (field_w / 2);
      aliens = make_aliens ~field_w;
      bullets = [];
      alien_bullets = [];
      explosions = [];
      alien_dir = 1.0;
      score = 0;
      lives = 3;
      phase = Playing;
      field_w;
      field_h;
      cw = Cw.create ();
      timers_registered = false;
      next_page = None;
    }

  let default_w = 50

  let default_h = 24

  let init () = init_state ~field_w:default_w ~field_h:default_h

  let update s (_ : msg) = s

  (* -- Update logic ------------------------------------------------------- *)

  let move_bullets dt bullets speed dir =
    List.filter_map
      (fun b ->
        if not b.active then None
        else
          let y' = b.bpos.y +. (dir *. speed *. dt) in
          if y' < 0.0 || y' > 200.0 then None
          else Some {b with bpos = {x = b.bpos.x; y = y'}})
      bullets

  let check_bullet_alien_collisions s =
    let new_explosions = ref [] in
    let score_gain = ref 0 in
    let aliens =
      List.map
        (fun a ->
          if not a.alive then a
          else
            let hit =
              List.exists
                (fun b ->
                  b.active
                  && Float.abs (b.bpos.x -. a.pos.x) < 1.5
                  && Float.abs (b.bpos.y -. a.pos.y) < 1.0)
                s.bullets
            in
            if hit then begin
              new_explosions :=
                {
                  epos = a.pos;
                  anim = Anim.create ~duration:0.4 ~easing:Ease_out ();
                }
                :: !new_explosions ;
              score_gain := !score_gain + 10 ;
              {a with alive = false}
            end
            else a)
        s.aliens
    in
    let bullets =
      List.map
        (fun b ->
          if not b.active then b
          else
            let hit =
              List.exists
                (fun a ->
                  a.alive
                  && Float.abs (b.bpos.x -. a.pos.x) < 1.5
                  && Float.abs (b.bpos.y -. a.pos.y) < 1.0)
                s.aliens
            in
            if hit then {b with active = false} else b)
        s.bullets
    in
    {
      s with
      aliens;
      bullets;
      score = s.score + !score_gain;
      explosions = s.explosions @ !new_explosions;
    }

  let check_alien_bullet_ship s =
    let ship_y = Float.of_int (s.field_h - 2) in
    let hit =
      List.exists
        (fun b ->
          b.active
          && Float.abs (b.bpos.x -. s.ship_x) < 1.5
          && Float.abs (b.bpos.y -. ship_y) < 1.0)
        s.alien_bullets
    in
    if hit then
      let alien_bullets =
        List.map
          (fun b ->
            if
              b.active
              && Float.abs (b.bpos.x -. s.ship_x) < 1.5
              && Float.abs (b.bpos.y -. ship_y) < 1.0
            then {b with active = false}
            else b)
          s.alien_bullets
      in
      let lives = s.lives - 1 in
      let explosions =
        s.explosions
        @ [
            {
              epos = {x = s.ship_x; y = ship_y};
              anim = Anim.create ~duration:0.5 ~easing:Ease_out ();
            };
          ]
      in
      if lives <= 0 then
        {
          s with
          alien_bullets;
          lives;
          explosions;
          phase = Game_over (Anim.create ~duration:1.0 ~easing:Ease_in_out ());
        }
      else {s with alien_bullets; lives; explosions}
    else s

  let step_aliens s =
    let hit_edge =
      List.exists
        (fun a ->
          a.alive
          && ((s.alien_dir > 0.0 && a.pos.x >= Float.of_int (s.field_w - 3))
             || (s.alien_dir < 0.0 && a.pos.x <= 1.0)))
        s.aliens
    in
    let aliens, new_dir =
      if hit_edge then
        ( List.map
            (fun a ->
              if a.alive then {a with pos = {x = a.pos.x; y = a.pos.y +. 1.0}}
              else a)
            s.aliens,
          -.s.alien_dir )
      else
        ( List.map
            (fun a ->
              if a.alive then
                {
                  a with
                  pos = {x = a.pos.x +. (s.alien_dir *. 2.0); y = a.pos.y};
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
    let live_aliens = List.filter (fun a -> a.alive) s.aliens in
    match live_aliens with
    | [] -> s
    | _ ->
        let idx =
          (s.score + List.length s.alien_bullets) mod List.length live_aliens
        in
        let shooter = List.nth live_aliens idx in
        let b =
          {bpos = {x = shooter.pos.x; y = shooter.pos.y +. 1.0}; active = true}
        in
        {s with alien_bullets = b :: s.alien_bullets}

  let check_victory s =
    let all_dead = List.for_all (fun a -> not a.alive) s.aliens in
    if all_dead then
      {
        s with
        phase = Victory (Anim.create ~duration:1.5 ~easing:Ease_in_out ());
      }
    else s

  let tick_explosions dt explosions =
    List.filter_map
      (fun e ->
        let anim = Anim.tick e.anim ~dt in
        if Anim.finished anim then None else Some {e with anim})
      explosions

  let tick_phase dt phase =
    match phase with
    | Playing -> Playing
    | Game_over a -> Game_over (Anim.tick a ~dt)
    | Victory a -> Victory (Anim.tick a ~dt)

  (* -- Rendering ---------------------------------------------------------- *)

  let style_of fg = {C.default_style with fg}

  let bold_style_of fg = {C.default_style with fg; bold = true}

  let draw_game s c =
    let rows = C.rows c in
    let cols = C.cols c in
    C.clear c ;

    (* Border *)
    C.draw_box
      c
      ~row:0
      ~col:0
      ~width:cols
      ~height:rows
      ~border:Single
      ~style:(style_of 240) ;

    (* Score and lives *)
    let hud = Printf.sprintf " Score: %d  Lives: %d " s.score s.lives in
    C.draw_text c ~row:0 ~col:2 ~style:(bold_style_of 81) hud ;

    (* Phase overlay *)
    (match s.phase with
    | Playing -> ()
    | Game_over anim ->
        let v = Anim.value anim in
        let fg = if v > 0.5 then 196 else 203 in
        let msg = "GAME OVER" in
        let col = max 1 ((cols - String.length msg) / 2) in
        let row = rows / 2 in
        C.draw_text c ~row ~col ~style:(bold_style_of fg) msg ;
        let sub = "Press 'r' to restart" in
        let sub_col = max 1 ((cols - String.length sub) / 2) in
        C.draw_text c ~row:(row + 1) ~col:sub_col ~style:(style_of 245) sub
    | Victory anim ->
        let v = Anim.value anim in
        let fg = if v > 0.5 then 46 else 82 in
        let msg = "YOU WIN!" in
        let col = max 1 ((cols - String.length msg) / 2) in
        let row = rows / 2 in
        C.draw_text c ~row ~col ~style:(bold_style_of fg) msg ;
        let sub = Printf.sprintf "Score: %d  Press 'r' to restart" s.score in
        let sub_col = max 1 ((cols - String.length sub) / 2) in
        C.draw_text c ~row:(row + 1) ~col:sub_col ~style:(style_of 245) sub) ;

    (* Aliens *)
    List.iter
      (fun a ->
        if a.alive then begin
          let col = Float.to_int a.pos.x in
          let row = Float.to_int a.pos.y in
          let ch = alien_chars.(a.row mod Array.length alien_chars) in
          let fg = match a.row with 0 -> 196 | 1 -> 208 | _ -> 226 in
          C.draw_text c ~row ~col ~style:(bold_style_of fg) ch
        end)
      s.aliens ;

    (* Player bullets *)
    List.iter
      (fun b ->
        if b.active then begin
          let col = Float.to_int b.bpos.x in
          let row = Float.to_int b.bpos.y in
          C.draw_text c ~row ~col ~style:(bold_style_of 51) bullet_char
        end)
      s.bullets ;

    (* Alien bullets *)
    List.iter
      (fun b ->
        if b.active then begin
          let col = Float.to_int b.bpos.x in
          let row = Float.to_int b.bpos.y in
          C.draw_text c ~row ~col ~style:(bold_style_of 196) alien_bullet_char
        end)
      s.alien_bullets ;

    (* Explosions *)
    List.iter
      (fun e ->
        let v = Anim.value e.anim in
        let fg = Anim.lerp_int 226 196 e.anim in
        let ch = if v < 0.5 then explosion_char else " " in
        let col = Float.to_int e.epos.x in
        let row = Float.to_int e.epos.y in
        C.draw_text c ~row ~col ~style:(bold_style_of fg) ch)
      s.explosions ;

    (* Ship *)
    (match s.phase with
    | Game_over _ -> ()
    | _ ->
        let ship_col = Float.to_int s.ship_x in
        let ship_row = rows - 2 in
        C.draw_text
          c
          ~row:ship_row
          ~col:ship_col
          ~style:(bold_style_of 46)
          ship_char) ;

    (* Controls hint *)
    let hint = "h/l:move  Space:fire  r:restart  Esc:back" in
    let hint_col = max 1 ((cols - String.length hint) / 2) in
    C.draw_text c ~row:(rows - 1) ~col:hint_col ~style:(style_of 240) hint

  (* -- Page callbacks ----------------------------------------------------- *)

  let register_timers () =
    match Miaou_interfaces.Timer.get () with
    | None -> ()
    | Some timer ->
        timer.set_interval ~id:"alien_step" alien_step_interval ;
        timer.set_interval ~id:"alien_shoot" alien_shoot_interval

  let view s ~focus:_ ~size =
    let rows = max 10 (size.LTerm_geom.rows - 1) in
    let cols = max 20 (min size.LTerm_geom.cols 80) in
    let s =
      if s.field_w <> cols || s.field_h <> rows then
        let s = {s with field_w = cols; field_h = rows} in
        if s.score = 0 && s.lives = 3 then
          {s with aliens = make_aliens ~field_w:cols}
        else s
      else s
    in
    let cw = Cw.ensure s.cw ~rows ~cols in
    (match Cw.canvas cw with Some c -> draw_game s c | None -> ()) ;
    Cw.render cw ~size:{LTerm_geom.rows; cols}

  let go_back s =
    {s with next_page = Some Demo_shared.Demo_config.launcher_page_name}

  let fire s =
    match s.phase with
    | Playing ->
        let ship_y = Float.of_int (s.field_h - 3) in
        let b = {bpos = {x = s.ship_x; y = ship_y}; active = true} in
        {s with bullets = b :: s.bullets}
    | _ -> s

  let handle_key s key_str ~size:_ =
    match Miaou.Core.Keys.of_string key_str with
    | Some (Miaou.Core.Keys.Char "Esc") | Some (Miaou.Core.Keys.Char "Escape")
      ->
        go_back s
    | Some (Miaou.Core.Keys.Char " ") | Some (Miaou.Core.Keys.Char "Space") ->
        fire s
    | Some (Miaou.Core.Keys.Char k) when String.lowercase_ascii k = "r" ->
        let s' = init_state ~field_w:s.field_w ~field_h:s.field_h in
        register_timers () ;
        {s' with cw = s.cw; timers_registered = true}
    | _ -> s

  let move s delta =
    match s.phase with
    | Playing ->
        let dx = Float.of_int delta *. 2.0 in
        let ship_x =
          clamp_f 1.0 (Float.of_int (s.field_w - 2)) (s.ship_x +. dx)
        in
        {s with ship_x}
    | _ -> s

  let refresh s =
    let s =
      if not s.timers_registered then begin
        register_timers () ;
        {s with timers_registered = true}
      end
      else s
    in
    let dt =
      match Miaou_interfaces.Clock.get () with
      | Some clock -> clock.dt ()
      | None -> 1.0 /. 60.0
    in
    match s.phase with
    | Game_over _ | Victory _ ->
        {
          s with
          phase = tick_phase dt s.phase;
          explosions = tick_explosions dt s.explosions;
        }
    | Playing ->
        let s =
          match Miaou_interfaces.Timer.get () with
          | None -> s
          | Some timer ->
              let fired = timer.drain_fired () in
              let s =
                if List.mem "alien_step" fired then step_aliens s else s
              in
              if List.mem "alien_shoot" fired then alien_shoot s else s
        in
        let bullets = move_bullets dt s.bullets bullet_speed (-1.0) in
        let alien_bullets =
          move_bullets dt s.alien_bullets alien_bullet_speed 1.0
        in
        let s = {s with bullets; alien_bullets} in
        let s = check_bullet_alien_collisions s in
        let s = check_alien_bullet_ship s in
        let s = check_victory s in
        let explosions = tick_explosions dt s.explosions in
        {s with explosions}

  let enter s =
    register_timers () ;
    {s with timers_registered = true}

  let service_select s _ = s

  let service_cycle s _ = s

  let handle_modal_key s _ ~size:_ = s

  let next_page s = s.next_page

  let keymap _ = []

  let handled_keys () = []

  let back s = go_back s

  let has_modal _ = false
end

include Demo_shared.Demo_page.MakeSimple (Inner)
