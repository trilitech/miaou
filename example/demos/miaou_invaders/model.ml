(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

module C = Miaou_canvas.Canvas
module Cw = Miaou_widgets_layout.Canvas_widget
module Anim = Miaou_helpers.Animation

let base_ship_char = "/^\\"

let alien_chars = [|"<O>"; "{X}"; "[M]"|]

let boss_char = "[###]"

let bullet_speed = 30.0

let base_enemy_bullet_speed = 11.0

let max_cols = 80

type bonus_color = Ruby | Emerald | Sapphire

type alien_kind = Grunt | Boss

type shot_kind = Basic | Flame | Burst | Pierce

type background_theme = {
  name : string;
  bg : int;
  dust_a : int;
  dust_b : int;
  accent : int;
}

let backgrounds =
  [|
    {name = "Nebula"; bg = 17; dust_a = 24; dust_b = 31; accent = 81};
    {name = "Deep Sea"; bg = 18; dust_a = 25; dust_b = 32; accent = 45};
    {name = "Volcanic"; bg = 52; dust_a = 88; dust_b = 130; accent = 209};
    {name = "Emerald"; bg = 22; dust_a = 28; dust_b = 34; accent = 120};
    {name = "Noir"; bg = 235; dust_a = 239; dust_b = 243; accent = 250};
  |]

type pos = {x : float; y : float}

type alien = {
  aid : int;
  pos : pos;
  alive : bool;
  row : int;
  hp : int;
  hp_max : int;
  kind : alien_kind;
}

type projectile = {
  ppos : pos;
  vx : float;
  vy : float;
  wave_amp : float;
  wave_freq : float;
  age : float;
  dmg : int;
  pierce : int;
  active : bool;
  glyph : string;
  fg : int;
}

type bonus = {
  bpos : pos;
  color : bonus_color;
  vy : float;
  phase : float;
  active : bool;
}

type explosion = {
  epos : pos;
  evx : float;
  evy : float;
  egravity : float;
  echar : string;
  efg_start : int;
  efg_end : int;
  anim : Anim.t;
}

type life_popup = {lpos : pos; lanim : Anim.t}

type game_phase =
  | Playing
  | Paused
  | Wave_clear of Anim.t
  | Game_over of Anim.t

type state = {
  ship_x : float;
  aliens : alien list;
  bullets : projectile list;
  alien_bullets : projectile list;
  bonuses : bonus list;
  explosions : explosion list;
  life_popups : life_popup list;
  alien_dir : float;
  score : int;
  lives : int;
  level : int;
  phase : game_phase;
  field_w : int;
  field_h : int;
  step_acc : float;
  shoot_acc : float;
  fire_cd : float;
  shot_color : bonus_color option;
  shot_power : int;
  boss_intro : Anim.t option;
  ship_morph : Anim.t option;
  ai_mode : bool;
  shake : float;
  frame : int;
  show_title : bool;
  cw : Cw.t;
  timers_registered : bool;
  next_page : string option;
}

type msg = unit

let clamp_f lo hi v = Float.max lo (Float.min hi v)

let theme_for_level level =
  backgrounds.((level - 1) mod Array.length backgrounds)

let bonus_fg = function Ruby -> 203 | Emerald -> 120 | Sapphire -> 45

let shot_kind_of = function
  | Some Ruby -> Flame
  | Some Emerald -> Burst
  | Some Sapphire -> Pierce
  | None -> Basic

let shot_name = function
  | Basic -> "Basic"
  | Flame -> "Flame"
  | Burst -> "Burst"
  | Pierce -> "Pierce"

let ship_sprite shot_color shot_power =
  let p = max 1 shot_power in
  match shot_color with
  | None -> base_ship_char
  | Some Ruby ->
      if p <= 1 then "/!\\"
      else if p = 2 then "<A>"
      else if p = 3 then "<A=>"
      else if p = 4 then "<==A==>"
      else if p = 5 then "<===A===>"
      else "<<==A==>>"
  | Some Emerald ->
      if p <= 1 then "<^>"
      else if p = 2 then "<#>"
      else if p = 3 then "[###]"
      else if p = 4 then "[#####]"
      else if p = 5 then "[[###]]"
      else "[[#####]]"
  | Some Sapphire ->
      if p <= 1 then "/:\\"
      else if p = 2 then "<:>"
      else if p = 3 then "{:X:}"
      else if p = 4 then "{::X::}"
      else if p = 5 then "<:===:>"
      else "<<:===:>>"

let ship_half_width s =
  max 1 (String.length (ship_sprite s.shot_color s.shot_power) / 2)

let is_boss_level level = level mod 5 = 0

let boss_hp_for level = 18 + (level * 4)

let step_interval_for level =
  max 0.12 (0.62 -. (float_of_int (level - 1) *. 0.035))

let shoot_interval_for level =
  max 0.22 (1.1 -. (float_of_int (level - 1) *. 0.05))

let enemy_bullet_speed_for level =
  base_enemy_bullet_speed +. (float_of_int level *. 0.7)

let alien_hp_for level = min 3 (1 + ((level - 1) / 4))

let make_wave ~field_w ~level =
  if is_boss_level level then
    let hp = boss_hp_for level in
    [
      {
        aid = 1;
        pos = {x = Float.of_int (field_w / 2); y = 3.0};
        alive = true;
        row = 0;
        hp;
        hp_max = hp;
        kind = Boss;
      };
    ]
  else
    let cols = min 10 (6 + (level / 2)) in
    let rows = min 5 (3 + (level / 3)) in
    let spacing = if cols >= 9 then 4 else 5 in
    let start_x = max 2 ((field_w - ((cols - 1) * spacing)) / 2) in
    let hp = alien_hp_for level in
    List.init (rows * cols) (fun i ->
        let r = i / cols in
        let c = i mod cols in
        {
          aid = i + 1;
          pos =
            {
              x = Float.of_int (start_x + (c * spacing));
              y = Float.of_int (2 + (r * 2));
            };
          alive = true;
          row = r;
          hp;
          hp_max = hp;
          kind = Grunt;
        })

let spawn_explosion ~x ~y ~big =
  let specs =
    if big then
      [
        (-9.0, -11.0, 17.0, "*", 226, 196, 0.55);
        (-7.0, -8.0, 15.0, "x", 220, 202, 0.50);
        (-5.0, -9.0, 14.0, "*", 214, 203, 0.48);
        (-3.0, -6.0, 13.0, "+", 215, 196, 0.46);
        (0.0, -10.0, 16.0, "*", 229, 196, 0.58);
        (3.0, -6.0, 13.0, "+", 215, 196, 0.46);
        (5.0, -9.0, 14.0, "*", 214, 203, 0.48);
        (7.0, -8.0, 15.0, "x", 220, 202, 0.50);
        (9.0, -11.0, 17.0, "*", 226, 196, 0.55);
        (-4.0, -3.0, 10.0, ".", 250, 240, 0.42);
        (4.0, -3.0, 10.0, ".", 250, 240, 0.42);
        (0.0, -4.0, 11.0, "+", 253, 244, 0.44);
      ]
    else
      [
        (-5.0, -7.0, 14.0, "*", 220, 196, 0.42);
        (-3.0, -4.0, 12.0, "+", 214, 202, 0.38);
        (0.0, -8.0, 15.0, "*", 226, 196, 0.44);
        (3.0, -4.0, 12.0, "+", 214, 202, 0.38);
        (5.0, -7.0, 14.0, "*", 220, 196, 0.42);
        (0.0, -3.0, 10.0, ".", 250, 240, 0.34);
      ]
  in
  List.map
    (fun (vx, vy, gravity, ch, fg0, fg1, duration) ->
      {
        epos = {x; y};
        evx = vx;
        evy = vy;
        egravity = gravity;
        echar = ch;
        efg_start = fg0;
        efg_end = fg1;
        anim = Anim.create ~duration ~easing:Ease_out ();
      })
    specs

let init_state ~field_w ~field_h =
  {
    ship_x = Float.of_int (field_w / 2);
    aliens = make_wave ~field_w ~level:1;
    bullets = [];
    alien_bullets = [];
    bonuses = [];
    explosions = [];
    life_popups = [];
    alien_dir = 1.0;
    score = 0;
    lives = 3;
    level = 1;
    phase = Playing;
    field_w;
    field_h;
    step_acc = 0.0;
    shoot_acc = 0.0;
    fire_cd = 0.0;
    shot_color = None;
    shot_power = 0;
    boss_intro = None;
    ship_morph = None;
    ai_mode = false;
    shake = 0.0;
    frame = 0;
    show_title = true;
    cw = Cw.create ();
    timers_registered = false;
    next_page = None;
  }

let default_w = 56

let default_h = 22

let init () = init_state ~field_w:default_w ~field_h:default_h

let update s (_ : msg) = s
