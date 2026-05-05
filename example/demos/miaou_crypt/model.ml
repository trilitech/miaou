(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

module Arcade_kit = Demo_shared.Arcade_kit

(** Game model for MIAOU Crypt — a pseudo-3-D first-person dungeon
    crawler. The world is a tile grid; the player has a continuous
    (x, y) position and a discrete cardinal facing (one of N / E / S /
    W). Tile movement is one-tile-at-a-time, gated by walls and doors.

    Polish round 2 adds: Archer monster kind with grid-level ranged
    projectiles, per-monster wait_t yielding to reduce monster walls,
    strafe behaviour for distant monsters, a Descending_anim transition
    mode, Map_scroll item with full-floor fog reveal, and speed-run
    score bonuses.

    Polish round 3 adds: attack_flash_t for 0.3 s slash animation,
    Ring_of_speed item with speed_ring_timer countdown, per-floor
    monster taunts, and persistent best_score tracking.

    Polish round 4 adds: monster knockback + stun_t on melee hit,
    footstep_t dust-puff flash, show_inventory toggle, secret room on
    floor 4, Dragon phase-2 breath cone with boss_warning, dragon_phase
    tracking.

    Polish round 5 adds: torch increased view distance (16 tiles), warm
    wall tint when torch active, health vignette pulsing at low HP,
    corpse markers on minimap, stairway yellow glow, floor-2 improvements,
    better game-over screen with death cause.

    Polish round 6 adds: bat random-direction AI with per-bat direction
    timer, faster bat movement (0.15 s interval), spin special attack
    (key e) costing one charge and hitting all 8 adjacent tiles, special
    charge HUD display, player trail on minimap (last 5 positions),
    visited-tile brightness contrast, tile-grid mortar/seam shading in
    the raycaster, alternate floor layouts for floors 1-2, and an ASCII
    corridor art block on the title screen.

    Polish round 7 adds: Armor item (reduces incoming damage by 1 while
    held, shown as [A] in HUD), Speed_scroll item (15 s speed boost),
    Wraith phase-teleport (every 5 s jumps to tile in front of player),
    per-floor star ratings (1–3) shown on game-over, Dragon phase-3
    movement (advances one tile toward player every 3 s when HP ≤ 25%),
    and a minimap legend line.

    Polish round 8 adds: Zombie monster (HP 8, dmg 3, very slow, immune
    to stun, drops a Healing_rune on death that restores +3 HP when
    stepped on); passive HP regen (1 HP every 4 s of standing still,
    reset on damage); Healing_rune tile type; improved game-over screen
    with total kills, floor ratings, and a gravestone ASCII panel; torch
    particle burst on pickup; torch HUD flicker when expiring; secret
    alcove on floor 5 accessible through a fake-wall gap; floor 2B and
    floor 4 gain Zombies.

    Polish round 9 adds: Bomb_scroll item (key f — blast radius-3 burst
    damaging all nearby enemies for 5 HP, orange particle shower and
    screen shake); monster alert state (first detection triggers faster
    movement for Spider/Skeleton/Zombie and a 1.5 s "!" billboard
    display); floor 3 variant B (crossroads with locked doors and new
    enemy placement, random selection matching floors 1–2); experience
    point and level-up system (XP per kill, level bonuses: +5 max HP,
    +2 current HP, +1 attack bonus, golden particle burst, LEVEL UP!
    banner); enhanced title-screen ASCII 3-D corridor art. *)

(* ---------- tiles ---------- *)

type tile =
  | Wall
  | Floor
  | Door of {open_ : bool; locked : bool}
  | Stairs
  | Key
  | Exit
  | Potion
  | Torch
  | Sword
  | Map_scroll
  | Ring_of_speed
  | Armor
  | Speed_scroll
  | Healing_rune
  | Bomb_scroll

(* ---------- monsters ---------- *)

type monster_kind =
  | Spider
  | Skeleton
  | Bat
  | Wraith
  | Lich
  | Dragon
  | Archer
  | Zombie

type monster = {
  mutable alive : bool;
  mutable kind : monster_kind;
  mutable mx : int;
  mutable my : int;
  (* Continuous render-position used for smooth wraith drift. Equals
     (mx + 0.5, my + 0.5) for grid-locked monsters. *)
  mutable rx : float;
  mutable ry : float;
  mutable hp : int;
  mutable hp_max : int;
  mutable cooldown : float;
  mutable hit_flash : float;
  (* Lich/Dragon fireball state — when > 0, a projectile is in flight
     from (proj_x, proj_y) toward player along (proj_dx, proj_dy). *)
  mutable proj_active : bool;
  mutable proj_x : float;
  mutable proj_y : float;
  mutable proj_dx : float;
  mutable proj_dy : float;
  mutable proj_life : float;
  (* Yield timer: when a monster wants to move but finds another monster
     in the target tile, it sets wait_t = 0.5 and waits before retrying. *)
  mutable wait_t : float;
  (* Stun timer: set to 0.4 s after knockback from a melee hit. While > 0
     the monster skips all AI (does not move or attack). *)
  mutable stun_t : float;
  (* Bat direction timer: when 0 a new random cardinal direction is chosen.
     Only meaningful for Bat kind; ignored for all others. *)
  mutable bat_dir_t : float;
  mutable bat_dx : int;
  mutable bat_dy : int;
  (* Wraith phase-teleport countdown: when it reaches 0 the wraith jumps
     to the tile directly in front of the player (if passable). Reset to 5 s. *)
  mutable phase_t : float;
  (* Alert state: set true the first time this monster detects the player
     within 4 Manhattan tiles and begins moving toward them.  While true,
     Spider / Skeleton / Zombie use half their normal cooldown. *)
  mutable alerted : bool;
  (* Alert display timer: set to 1.5 when first alerted.  Decremented each
     tick.  While > 0, view.ml draws a bright yellow "!" above the billboard. *)
  mutable alert_display_t : float;
}

let dead_monster () =
  {
    alive = false;
    kind = Spider;
    mx = 0;
    my = 0;
    rx = 0.0;
    ry = 0.0;
    hp = 0;
    hp_max = 0;
    cooldown = 0.0;
    hit_flash = 0.0;
    proj_active = false;
    proj_x = 0.0;
    proj_y = 0.0;
    proj_dx = 0.0;
    proj_dy = 0.0;
    proj_life = 0.0;
    wait_t = 0.0;
    stun_t = 0.0;
    bat_dir_t = 0.0;
    bat_dx = 1;
    bat_dy = 0;
    phase_t = 5.0;
    alerted = false;
    alert_display_t = 0.0;
  }

let monster_max_hp = function
  | Spider -> 2
  | Skeleton -> 4
  | Bat -> 1
  | Wraith -> 5
  | Lich -> 16
  | Dragon -> 30
  | Archer -> 3
  | Zombie -> 8

let monster_damage = function
  | Spider -> 1
  | Skeleton -> 3
  | Bat -> 1
  | Wraith -> 2
  | Lich -> 4
  | Dragon -> 6
  | Archer -> 1
  | Zombie -> 3

let monster_score = function
  | Spider -> 10
  | Skeleton -> 25
  | Bat -> 5
  | Wraith -> 50
  | Lich -> 500
  | Dragon -> 1500
  | Archer -> 30
  | Zombie -> 30

let monster_name = function
  | Spider -> "spider"
  | Skeleton -> "skeleton"
  | Bat -> "bat"
  | Wraith -> "wraith"
  | Lich -> "lich"
  | Dragon -> "dragon"
  | Archer -> "archer"
  | Zombie -> "zombie"

let is_boss = function Lich | Dragon -> true | _ -> false

(* ---------- player ---------- *)

(* Facing as a cardinal vector. Player position is in tile coordinates
   and stays aligned to tile centres after each step. *)

type facing = {dx : int; dy : int}

let facing_east = {dx = 1; dy = 0}

let facing_west = {dx = -1; dy = 0}

let facing_north = {dx = 0; dy = -1}

let facing_south = {dx = 0; dy = 1}

(* Turn 90° clockwise (right). *)
let turn_right f = {dx = -f.dy; dy = f.dx}

(* Turn 90° counter-clockwise (left). *)
let turn_left f = {dx = f.dy; dy = -f.dx}

let facing_angle f =
  match (f.dx, f.dy) with
  | 1, 0 -> 0.0 (* east *)
  | 0, 1 -> Float.pi /. 2.0 (* south *)
  | -1, 0 -> Float.pi
  | 0, -1 -> -.Float.pi /. 2.0
  | _ -> 0.0

type player = {
  mutable x : float; (* tile-centre x *)
  mutable y : float; (* tile-centre y *)
  mutable facing : facing;
  mutable hp : int;
  mutable hp_max : int;
  mutable keys : int;
  mutable potions : int;
  mutable torches : int;
  (* Active torch effect remaining time (s). When > 0, view widens. *)
  mutable torch_timer : float;
  (* Per-run sword damage bonus; persists across floor descents. *)
  mutable sword_bonus : int;
  mutable floor : int;
  (* Total monsters killed this run. *)
  mutable monsters_killed : int;
  (* Ring of Speed: when > 0 the player moves at 1.5× speed (effectively
     allows two consecutive actions per tick by stepping past monsters'
     AI reactions). Visual indicator shown in HUD. *)
  mutable speed_ring_timer : float;
  (* Special ability charges. Key e triggers a spin attack (3 damage to all
     8 adjacent tiles, screen shake) for 1 charge. Max 3. Players start with
     1 charge; gain +1 per 5 floors descended and when picking up a Sword. *)
  mutable special_charges : int;
  (* Armor: set to true when an Armor item is picked up. Reduces all incoming
     damage by 1 (minimum 1) while true. Shown as [A] in the HUD. *)
  mutable has_armor : bool;
  (* Passive regen timer: accumulates while the player stands still. When it
     reaches 4.0 s and HP < max_hp, restore 1 HP and reset to 0.0.
     Reset to 0.0 whenever the player takes damage. *)
  mutable rest_t : float;
  (* Bomb scrolls: each use damages all enemies within radius 3 for 5 HP
     with an orange particle burst and screen shake. *)
  mutable bomb_count : int;
  (* Experience points and player level. *)
  mutable xp : int;
  mutable player_level : int;
  mutable xp_to_next : int;
  (* Per-level cumulative attack bonus earned from levelling up. *)
  mutable level_attack_bonus : int;
}

(* ---------- damage popups ---------- *)

(* Tiny floating "-3"/"+5" labels rendered with a 3×5 hand-rolled
   pixel-digit font, identical pattern to the Force demo. *)

type popup = {
  mutable alive : bool;
  mutable wx : float;
  (* world coords (tile-space) *)
  mutable wy : float;
  mutable life : float;
  mutable life0 : float;
  mutable text : string;
  mutable r : int;
  mutable g : int;
  mutable b : int;
}

let dead_popup () =
  {
    alive = false;
    wx = 0.0;
    wy = 0.0;
    life = 0.0;
    life0 = 0.0;
    text = "";
    r = 0;
    g = 0;
    b = 0;
  }

let max_popups = 24

(* ---------- ranged projectiles (archer arrows) ---------- *)

(* Grid-level projectiles fired by Archer monsters. Each projectile
   advances one tile per 0.25 s. On hitting the player tile or a wall,
   it is removed. *)

type projectile = {
  mutable px : int;
  mutable py : int;
  mutable pdx : int;
  mutable pdy : int;
  (* Countdown until next tile advance (starts at 0.25, resets each
     tile move). *)
  mutable tick_t : float;
  mutable alive : bool;
}

let max_projectiles = 16

let dead_projectile () =
  {px = 0; py = 0; pdx = 0; pdy = 0; tick_t = 0.25; alive = false}

(* ---------- floor (parsed from ascii layout) ---------- *)

type floor = {
  width : int;
  height : int;
  tiles : tile array; (* row-major, length = width * height *)
  visited : bool array; (* fog of war: true once player adjacent *)
  has_boss : bool;
  boss_name : string;
}

let max_monsters_per_floor = 24

(* ---------- top-level state ---------- *)

type mode =
  | Title
  | Exploring
  | Descending_anim of {mutable anim_t : float}
  | Floor_clear
  | Boss_kill_cinematic
  | Game_over

type t = {
  mutable mode : mode;
  mutable mode_t : float;
  mutable floor : floor;
  player : player;
  monsters : monster array;
  projectiles : projectile array;
  popups : popup array;
  particles : Arcade_kit.Particles.t;
  fx : Arcade_kit.Screen_fx.t;
  rng : Random.State.t;
  mutable score : int;
  mutable best_floor : int;
  (* Best score ever recorded this session (persisted via Score_store). *)
  mutable best_score : int;
  mutable show_minimap : bool;
  mutable last_action : string;
  mutable next_page : string option;
  (* deepest floor reached this run *)
  mutable deepest_reached : int;
  (* Animation clock — only advances when the simulation should
     animate (always in normal mode, gated in debug mode). *)
  mutable anim_t : float;
  (* Debug / turn-based step controls. When [debug_mode] is true,
     [anim_t] only advances when [pending_steps] is non-zero. *)
  mutable debug_mode : bool;
  mutable pending_steps : int;
  mutable frame_no : int;
  (* Cinematic timer for boss kills. *)
  mutable cinematic_msg : string;
  (* Whether the current floor's map has been fully revealed. *)
  mutable has_full_map : bool;
  (* Steps taken on the current floor (reset when loading a new floor). *)
  mutable steps_on_floor : int;
  (* Speed-bonus multiplier applied to kills on the current floor.
     Set to 2 when floor cleared in ≤ 12 steps; otherwise 1. *)
  mutable speed_mult : int;
  (* Attack flash: set to 0.3 when player lands a melee hit, ticked down
     each frame. [view.ml] draws the slash overlay while > 0. *)
  mutable attack_flash_t : float;
  (* Footstep dust-puff: set to 0.1 each time the player takes a step.
     [view.ml] draws a dim umber strip at the bottom of the view while > 0. *)
  mutable footstep_t : float;
  (* Inventory overlay: toggled by pressing 'i'. *)
  mutable show_inventory : bool;
  (* Dragon phase 2 (HP ≤ 50%): breath cone fires instead of single shot. *)
  mutable dragon_phase : int;
  (* Boss breath-cone warning: set 0.5 s before cone fires. [view.ml]
     draws an "INCOMING!" banner while true. Cleared when bullets spawn. *)
  mutable boss_warning : bool;
  (* Countdown until the next breath-cone fires (Dragon phase 2 only). *)
  mutable breath_cone_t : float;
  (* Corpse positions left by defeated monsters on the current floor.
     Rendered as dark-red × markers on the minimap. Reset on floor load. *)
  mutable corpses : (int * int) list;
  (* What killed the player — shown on the game-over screen.
     Set when HP drops to 0. Empty at the start of each run. *)
  mutable last_death_cause : string;
  (* Last 5 tile positions visited by the player, newest first.
     Rendered as fading-grey dots on the minimap. Reset on floor load. *)
  mutable player_trail : (int * int) list;
  (* Per-floor star ratings (1–3). Indexed 0-based by floor number.
     Set when the player clears or passes each floor. 0 = not yet reached. *)
  mutable floor_stars : int array;
  (* Dragon phase-3 move timer: when Dragon HP ≤ 25% the dragon advances
     one tile toward the player every 3 s. Reset to 3.0 on each step. *)
  mutable boss_move_t : float;
  (* Set to true inside move handlers whenever the player moves a tile.
     Reset to false at the start of each tick.  Used by the passive regen
     logic: regen only accumulates when this is false (player standing still). *)
  mutable player_moved : bool;
  (* Total monsters killed across all floors in the current run. *)
  mutable total_kills : int;
  (* Level-up flash timer: set to 1.5 s when the player levels up.
     While > 0, view.ml draws a bright gold "LEVEL UP!" banner. *)
  mutable levelup_flash_t : float;
}

let particle_capacity = 256

(* ---------- ascii-layout parsing ---------- *)

(* Boss tile codes:
   - 'L' = Lich, 'g' = Dragon (g = "great wyrm"; uppercase 'G' clashes
     with future generics so we use lowercase). 'P' = potion, 'T' =
     torch, 'W' = sword upgrade, 'w' = wraith, 'A' = archer,
     'M' = map scroll, 'R' = ring of speed. *)

let parse_layout (rows : string array) =
  let h = Array.length rows in
  let w = if h = 0 then 0 else String.length rows.(0) in
  let tiles = Array.make (w * h) Wall in
  let visited = Array.make (w * h) false in
  let player_spawn = ref (1, 1) in
  let monsters_spawn = ref [] in
  let has_boss = ref false in
  let boss_name = ref "" in
  for y = 0 to h - 1 do
    let row = rows.(y) in
    let row_w = String.length row in
    for x = 0 to w - 1 do
      let c = if x < row_w then row.[x] else '#' in
      let i = (y * w) + x in
      match c with
      | '#' -> tiles.(i) <- Wall
      | '.' -> tiles.(i) <- Floor
      | 'K' -> tiles.(i) <- Key
      | 'D' -> tiles.(i) <- Door {open_ = false; locked = true}
      | 'd' -> tiles.(i) <- Door {open_ = false; locked = false}
      | 'S' -> tiles.(i) <- Stairs
      | 'X' -> tiles.(i) <- Exit
      | 'P' -> tiles.(i) <- Potion
      | 'T' -> tiles.(i) <- Torch
      | 'W' -> tiles.(i) <- Sword
      | 'M' -> tiles.(i) <- Map_scroll
      | 'R' -> tiles.(i) <- Ring_of_speed
      | 'V' -> tiles.(i) <- Armor
      | 'Q' -> tiles.(i) <- Speed_scroll
      | 'B' -> tiles.(i) <- Bomb_scroll
      | '@' ->
          tiles.(i) <- Floor ;
          player_spawn := (x, y)
      | 's' ->
          tiles.(i) <- Floor ;
          monsters_spawn := (Spider, x, y) :: !monsters_spawn
      | 'k' ->
          tiles.(i) <- Floor ;
          monsters_spawn := (Skeleton, x, y) :: !monsters_spawn
      | 'b' ->
          tiles.(i) <- Floor ;
          monsters_spawn := (Bat, x, y) :: !monsters_spawn
      | 'w' ->
          tiles.(i) <- Floor ;
          monsters_spawn := (Wraith, x, y) :: !monsters_spawn
      | 'A' ->
          tiles.(i) <- Floor ;
          monsters_spawn := (Archer, x, y) :: !monsters_spawn
      | 'Z' ->
          tiles.(i) <- Floor ;
          monsters_spawn := (Zombie, x, y) :: !monsters_spawn
      | 'L' ->
          tiles.(i) <- Floor ;
          monsters_spawn := (Lich, x, y) :: !monsters_spawn ;
          has_boss := true ;
          boss_name := "the Lich"
      | 'g' ->
          tiles.(i) <- Floor ;
          monsters_spawn := (Dragon, x, y) :: !monsters_spawn ;
          has_boss := true ;
          boss_name := "the Dragon"
      | _ -> tiles.(i) <- Floor
    done
  done ;
  ( {
      width = w;
      height = h;
      tiles;
      visited;
      has_boss = !has_boss;
      boss_name = !boss_name;
    },
    !player_spawn,
    List.rev !monsters_spawn )

(* ---------- helpers ---------- *)

let tile_at f ~x ~y =
  if x < 0 || y < 0 || x >= f.width || y >= f.height then Wall
  else f.tiles.((y * f.width) + x)

let set_tile f ~x ~y t =
  if x >= 0 && y >= 0 && x < f.width && y < f.height then
    f.tiles.((y * f.width) + x) <- t

let mark_visited f ~x ~y =
  if x >= 0 && y >= 0 && x < f.width && y < f.height then
    f.visited.((y * f.width) + x) <- true

let is_visited f ~x ~y =
  if x < 0 || y < 0 || x >= f.width || y >= f.height then false
  else f.visited.((y * f.width) + x)

let is_blocking = function
  | Wall -> true
  | Door {open_ = false; _} -> true
  | _ -> false

(* Reveal the player's tile and all 8 adjacent tiles (cardinal + diagonal). *)
let reveal_around (s : t) =
  let px = int_of_float s.player.x in
  let py = int_of_float s.player.y in
  let f = s.floor in
  mark_visited f ~x:px ~y:py ;
  mark_visited f ~x:(px + 1) ~y:py ;
  mark_visited f ~x:(px - 1) ~y:py ;
  mark_visited f ~x:px ~y:(py + 1) ;
  mark_visited f ~x:px ~y:(py - 1) ;
  mark_visited f ~x:(px + 1) ~y:(py + 1) ;
  mark_visited f ~x:(px + 1) ~y:(py - 1) ;
  mark_visited f ~x:(px - 1) ~y:(py + 1) ;
  mark_visited f ~x:(px - 1) ~y:(py - 1)

(* Reveal every tile on the entire floor (used by Map_scroll pickup). *)
let reveal_all (s : t) =
  let f = s.floor in
  for y = 0 to f.height - 1 do
    for x = 0 to f.width - 1 do
      mark_visited f ~x ~y
    done
  done

(* ---------- popup pool ---------- *)

let alloc_popup s =
  let n = Array.length s.popups in
  let rec loop i =
    if i >= n then None
    else if not s.popups.(i).alive then Some s.popups.(i)
    else loop (i + 1)
  in
  loop 0

let spawn_popup s ~wx ~wy ~text ~r ~g ~b =
  match alloc_popup s with
  | None -> ()
  | Some p ->
      p.alive <- true ;
      p.wx <- wx ;
      p.wy <- wy ;
      p.life <- 1.1 ;
      p.life0 <- 1.1 ;
      p.text <- text ;
      p.r <- r ;
      p.g <- g ;
      p.b <- b

let advance_popups s ~dt =
  Array.iter
    (fun (p : popup) ->
      if p.alive then begin
        p.life <- p.life -. dt ;
        if p.life <= 0.0 then p.alive <- false
      end)
    s.popups

(* ---------- init ---------- *)

let init () =
  let layout, _, _ = parse_layout Floors.floor_1 in
  let best = Arcade_kit.Score_store.load ~demo:"miaou_crypt" in
  let best_score_v = Arcade_kit.Score_store.load ~demo:"miaou_crypt_score" in
  let debug =
    match Sys.getenv_opt "MIAOU_CRYPT_DEBUG" with
    | Some s when s = "1" || s = "true" -> true
    | _ -> false
  in
  {
    mode = Title;
    mode_t = 0.0;
    floor = layout;
    player =
      {
        x = 1.5;
        y = 1.5;
        facing = facing_east;
        hp = 20;
        hp_max = 20;
        keys = 0;
        potions = 0;
        torches = 0;
        torch_timer = 0.0;
        sword_bonus = 0;
        floor = 1;
        monsters_killed = 0;
        speed_ring_timer = 0.0;
        special_charges = 1;
        has_armor = false;
        rest_t = 0.0;
        bomb_count = 0;
        xp = 0;
        player_level = 1;
        xp_to_next = 30;
        level_attack_bonus = 0;
      };
    monsters = Array.init max_monsters_per_floor (fun _ -> dead_monster ());
    projectiles = Array.init max_projectiles (fun _ -> dead_projectile ());
    popups = Array.init max_popups (fun _ -> dead_popup ());
    particles = Arcade_kit.Particles.create ~capacity:particle_capacity;
    fx = Arcade_kit.Screen_fx.create ();
    rng = Random.State.make [|0xC2071|];
    score = 0;
    best_floor = best;
    best_score = best_score_v;
    show_minimap = true;
    last_action = "";
    next_page = None;
    deepest_reached = 1;
    anim_t = 0.0;
    debug_mode = debug;
    pending_steps = 0;
    frame_no = 0;
    cinematic_msg = "";
    has_full_map = false;
    steps_on_floor = 0;
    speed_mult = 1;
    attack_flash_t = 0.0;
    footstep_t = 0.0;
    show_inventory = false;
    dragon_phase = 1;
    boss_warning = false;
    breath_cone_t = 2.5;
    corpses = [];
    last_death_cause = "";
    player_trail = [];
    floor_stars = Array.make Floors.count 0;
    boss_move_t = 3.0;
    player_moved = false;
    total_kills = 0;
    levelup_flash_t = 0.0;
  }

(* Load floor [n] into the model and reset transient state. *)
let load_floor (s : t) ~n =
  let layout, (px, py), monsters = parse_layout (Floors.get n) in
  s.floor <- layout ;
  s.player.x <- float_of_int px +. 0.5 ;
  s.player.y <- float_of_int py +. 0.5 ;
  s.player.facing <- facing_east ;
  s.player.floor <- n ;
  if n > s.deepest_reached then s.deepest_reached <- n ;
  (* Grant +1 special charge every 5 floors (floors 5, 10, …), max 3. *)
  if n > 1 && (n - 1) mod 5 = 0 then
    s.player.special_charges <- min 3 (s.player.special_charges + 1) ;
  Array.iter (fun (m : monster) -> m.alive <- false) s.monsters ;
  let n_slots = Array.length s.monsters in
  List.iteri
    (fun i (kind, mx, my) ->
      if i < n_slots then begin
        let m = s.monsters.(i) in
        m.alive <- true ;
        m.kind <- kind ;
        m.mx <- mx ;
        m.my <- my ;
        m.rx <- float_of_int mx +. 0.5 ;
        m.ry <- float_of_int my +. 0.5 ;
        m.hp <- monster_max_hp kind ;
        m.hp_max <- monster_max_hp kind ;
        m.cooldown <- 0.5 +. Random.State.float s.rng 1.0 ;
        m.hit_flash <- 0.0 ;
        m.proj_active <- false ;
        m.wait_t <- 0.0 ;
        m.stun_t <- 0.0 ;
        m.bat_dir_t <- 0.0 ;
        m.bat_dx <- 1 ;
        m.bat_dy <- 0 ;
        m.phase_t <- 5.0 ;
        m.alerted <- false ;
        m.alert_display_t <- 0.0
      end)
    monsters ;
  Array.iter (fun (p : projectile) -> p.alive <- false) s.projectiles ;
  Arcade_kit.Particles.clear s.particles ;
  Array.iter (fun (p : popup) -> p.alive <- false) s.popups ;
  s.last_action <- "" ;
  s.has_full_map <- false ;
  s.steps_on_floor <- 0 ;
  s.speed_mult <- 1 ;
  s.dragon_phase <- 1 ;
  s.boss_warning <- false ;
  s.breath_cone_t <- 2.5 ;
  s.corpses <- [] ;
  s.player_trail <- [] ;
  s.boss_move_t <- 3.0 ;
  reveal_around s

let begin_game (s : t) =
  s.mode <- Exploring ;
  s.mode_t <- 0.0 ;
  s.player.hp <- s.player.hp_max ;
  s.player.keys <- 0 ;
  s.player.potions <- 0 ;
  s.player.torches <- 0 ;
  s.player.torch_timer <- 0.0 ;
  s.player.sword_bonus <- 0 ;
  s.player.monsters_killed <- 0 ;
  s.player.speed_ring_timer <- 0.0 ;
  s.player.special_charges <- 1 ;
  s.player.has_armor <- false ;
  s.player.rest_t <- 0.0 ;
  s.player.bomb_count <- 0 ;
  s.player.xp <- 0 ;
  s.player.player_level <- 1 ;
  s.player.xp_to_next <- 30 ;
  s.player.level_attack_bonus <- 0 ;
  s.player.hp_max <- 20 ;
  s.score <- 0 ;
  s.deepest_reached <- 1 ;
  s.attack_flash_t <- 0.0 ;
  s.footstep_t <- 0.0 ;
  s.show_inventory <- false ;
  s.dragon_phase <- 1 ;
  s.boss_warning <- false ;
  s.breath_cone_t <- 2.5 ;
  s.last_death_cause <- "" ;
  Array.fill s.floor_stars 0 (Array.length s.floor_stars) 0 ;
  s.boss_move_t <- 3.0 ;
  s.player_moved <- false ;
  s.total_kills <- 0 ;
  s.levelup_flash_t <- 0.0 ;
  load_floor s ~n:1

(* ---------- monster lookup ---------- *)

let monster_at (s : t) ~x ~y =
  let n = Array.length s.monsters in
  let rec loop i =
    if i >= n then None
    else
      let m = s.monsters.(i) in
      if m.alive && m.mx = x && m.my = y then Some m else loop (i + 1)
  in
  loop 0

(* ---------- step / strafe ---------- *)

(* Internal: try to move the player onto (nx, ny). Returns whether the
   move happened. Pickups are consumed in place. *)
let try_step (s : t) ~dx ~dy =
  let nx = int_of_float s.player.x + dx in
  let ny = int_of_float s.player.y + dy in
  let t = tile_at s.floor ~x:nx ~y:ny in
  if is_blocking t then false
  else
    match monster_at s ~x:nx ~y:ny with
    | Some _ -> false (* monsters block *)
    | None ->
        (* Record previous tile position in the trail (max 5). *)
        let prev_tx = int_of_float s.player.x in
        let prev_ty = int_of_float s.player.y in
        s.player.x <- float_of_int nx +. 0.5 ;
        s.player.y <- float_of_int ny +. 0.5 ;
        s.steps_on_floor <- s.steps_on_floor + 1 ;
        s.footstep_t <- 0.1 ;
        s.player_moved <- true ;
        let trail =
          (prev_tx, prev_ty) :: List.filteri (fun i _ -> i < 4) s.player_trail
        in
        s.player_trail <- trail ;
        reveal_around s ;
        (* React to the tile we just stepped onto. *)
        (match t with
        | Stairs ->
            s.score <- s.score + 100 ;
            (* Speed run bonus: clear in ≤ 12 steps *)
            if s.steps_on_floor <= 12 then begin
              s.speed_mult <- 2 ;
              spawn_popup
                s
                ~wx:s.player.x
                ~wy:(s.player.y -. 0.5)
                ~text:"+SPEED"
                ~r:255
                ~g:240
                ~b:60
            end ;
            (* Floor star rating (1-3). *)
            let fl = s.player.floor in
            let stars =
              if s.score > fl * 200 then 3
              else if s.score > fl * 100 then 2
              else 1
            in
            if fl >= 1 && fl <= Array.length s.floor_stars then
              s.floor_stars.(fl - 1) <- stars ;
            s.mode <- Descending_anim {anim_t = 0.0} ;
            s.mode_t <- 0.0 ;
            s.last_action <- "Descending..."
        | Exit ->
            s.score <- s.score + 1000 ;
            (* Floor star rating for the final floor. *)
            let fl = s.player.floor in
            let stars =
              if s.score > fl * 200 then 3
              else if s.score > fl * 100 then 2
              else 1
            in
            if fl >= 1 && fl <= Array.length s.floor_stars then
              s.floor_stars.(fl - 1) <- stars ;
            s.mode <- Floor_clear ;
            s.mode_t <- 0.0 ;
            s.last_action <- "ARTIFACT FOUND — press Enter"
        | Key ->
            s.player.keys <- s.player.keys + 1 ;
            set_tile s.floor ~x:nx ~y:ny Floor ;
            s.last_action <- "+1 key"
        | Potion ->
            s.player.potions <- s.player.potions + 1 ;
            set_tile s.floor ~x:nx ~y:ny Floor ;
            s.last_action <- "+1 potion"
        | Torch ->
            s.player.torches <- s.player.torches + 1 ;
            set_tile s.floor ~x:nx ~y:ny Floor ;
            (* Warm orange celebration burst when picking up a torch. *)
            Arcade_kit.Particles.spawn_burst
              s.particles
              ~x:s.player.x
              ~y:s.player.y
              ~n:8
              ~speed:4.0
              ~life:0.5
              ~hue:25
              ~rng:s.rng ;
            s.last_action <- "+1 torch"
        | Sword ->
            s.player.sword_bonus <- s.player.sword_bonus + 1 ;
            (* Sword upgrade grants +1 special charge (max 3). *)
            s.player.special_charges <- min 3 (s.player.special_charges + 1) ;
            set_tile s.floor ~x:nx ~y:ny Floor ;
            s.last_action <- "Sword +1  ⚡+1"
        | Map_scroll ->
            set_tile s.floor ~x:nx ~y:ny Floor ;
            s.has_full_map <- true ;
            reveal_all s ;
            s.last_action <- "Map revealed!"
        | Ring_of_speed ->
            set_tile s.floor ~x:nx ~y:ny Floor ;
            s.player.speed_ring_timer <- 30.0 ;
            spawn_popup
              s
              ~wx:s.player.x
              ~wy:(s.player.y -. 0.5)
              ~text:"+SPD"
              ~r:255
              ~g:240
              ~b:60 ;
            s.last_action <- "Ring of Speed! (30s)"
        | Armor ->
            set_tile s.floor ~x:nx ~y:ny Floor ;
            s.player.has_armor <- true ;
            spawn_popup
              s
              ~wx:s.player.x
              ~wy:(s.player.y -. 0.5)
              ~text:"+ARM"
              ~r:160
              ~g:220
              ~b:255 ;
            s.last_action <- "Armor equipped! [-1 dmg]"
        | Speed_scroll ->
            set_tile s.floor ~x:nx ~y:ny Floor ;
            s.player.speed_ring_timer <- 15.0 ;
            spawn_popup
              s
              ~wx:s.player.x
              ~wy:(s.player.y -. 0.5)
              ~text:"+SPD"
              ~r:200
              ~g:255
              ~b:180 ;
            s.last_action <- "Speed Scroll! (15s)"
        | Healing_rune ->
            set_tile s.floor ~x:nx ~y:ny Floor ;
            let heal = 3 in
            s.player.hp <- min s.player.hp_max (s.player.hp + heal) ;
            spawn_popup
              s
              ~wx:s.player.x
              ~wy:(s.player.y -. 0.5)
              ~text:"+3HP"
              ~r:120
              ~g:255
              ~b:160 ;
            s.last_action <- "+3 HP (healing rune)"
        | Bomb_scroll ->
            set_tile s.floor ~x:nx ~y:ny Floor ;
            s.player.bomb_count <- s.player.bomb_count + 1 ;
            spawn_popup
              s
              ~wx:s.player.x
              ~wy:(s.player.y -. 0.5)
              ~text:"+BOM"
              ~r:255
              ~g:140
              ~b:40 ;
            s.last_action <- "Bomb scroll! (press f)"
        | _ -> ()) ;
        true

let step_forward s =
  ignore (try_step s ~dx:s.player.facing.dx ~dy:s.player.facing.dy)

let step_back s =
  ignore (try_step s ~dx:(-s.player.facing.dx) ~dy:(-s.player.facing.dy))

let strafe_left s =
  let f = turn_left s.player.facing in
  ignore (try_step s ~dx:f.dx ~dy:f.dy)

let strafe_right s =
  let f = turn_right s.player.facing in
  ignore (try_step s ~dx:f.dx ~dy:f.dy)

let turn_left s = s.player.facing <- turn_left s.player.facing

let turn_right s = s.player.facing <- turn_right s.player.facing

(* ---------- combat / interact ---------- *)

let damage_burst (s : t) ~x ~y ~hue =
  Arcade_kit.Particles.spawn_burst
    s.particles
    ~x
    ~y
    ~n:8
    ~speed:6.0
    ~life:0.6
    ~hue
    ~rng:s.rng

(* Boss-kill cinematic: massive flash + huge particle burst + state
   transition into the cinematic mode. *)
let trigger_boss_cinematic s ~x ~y ~name =
  Arcade_kit.Screen_fx.flash s.fx ~intensity:1.0 ~duration:1.0 ;
  Arcade_kit.Screen_fx.shake s.fx ~magnitude:1.5 ~duration:0.6 ;
  Arcade_kit.Particles.spawn_burst
    s.particles
    ~x
    ~y
    ~n:96
    ~speed:14.0
    ~life:1.4
    ~hue:9
    ~rng:s.rng ;
  s.cinematic_msg <- Printf.sprintf "%s SLAIN — ARTIFACT FOUND" name ;
  s.mode <- Boss_kill_cinematic ;
  s.mode_t <- 0.0

(* Give the player [amount] XP. If the new total meets the threshold,
   trigger a level-up: +5 max HP, +2 current HP, +1 attack bonus.
   Spawn golden particles and set the level-up banner timer. *)
let give_xp s amount =
  if amount <= 0 then ()
  else begin
    s.player.xp <- s.player.xp + amount ;
    if s.player.xp >= s.player.xp_to_next then begin
      s.player.xp <- s.player.xp - s.player.xp_to_next ;
      s.player.xp_to_next <- s.player.xp_to_next + 20 ;
      s.player.player_level <- s.player.player_level + 1 ;
      s.player.hp_max <- s.player.hp_max + 5 ;
      s.player.hp <- min s.player.hp_max (s.player.hp + 2) ;
      s.player.level_attack_bonus <- s.player.level_attack_bonus + 1 ;
      Arcade_kit.Particles.spawn_burst
        s.particles
        ~x:s.player.x
        ~y:s.player.y
        ~n:12
        ~speed:6.0
        ~life:1.0
        ~hue:35
        ~rng:s.rng ;
      s.levelup_flash_t <- 1.5 ;
      s.last_action <- Printf.sprintf "LEVEL UP! %d" s.player.player_level
    end
  end

(* Apply [dmg] points of damage to monster [m]. Spawns popups, kills
   it, and triggers boss cinematics. *)
let damage_monster s (m : monster) ~dmg =
  m.hp <- m.hp - dmg ;
  m.hit_flash <- 0.18 ;
  let mx_f = float_of_int m.mx +. 0.5 in
  let my_f = float_of_int m.my +. 0.5 in
  spawn_popup
    s
    ~wx:mx_f
    ~wy:my_f
    ~text:(Printf.sprintf "-%d" dmg)
    ~r:255
    ~g:200
    ~b:90 ;
  damage_burst s ~x:mx_f ~y:my_f ~hue:9 ;
  if m.hp <= 0 then begin
    m.alive <- false ;
    s.player.monsters_killed <- s.player.monsters_killed + 1 ;
    s.total_kills <- s.total_kills + 1 ;
    let pts = monster_score m.kind * s.speed_mult in
    s.score <- s.score + pts ;
    (* XP = kill score / 5, rounded down, minimum 1 for non-bosses. *)
    let xp_gain = max 1 (monster_score m.kind / 5) in
    give_xp s xp_gain ;
    (* Leave a corpse marker on the minimap at this tile position. *)
    s.corpses <- (m.mx, m.my) :: s.corpses ;
    (* Zombie drops a Healing_rune on its tile on death. *)
    if m.kind = Zombie then set_tile s.floor ~x:m.mx ~y:m.my Healing_rune ;
    Arcade_kit.Particles.spawn_burst
      s.particles
      ~x:mx_f
      ~y:my_f
      ~n:14
      ~speed:8.0
      ~life:0.8
      ~hue:10
      ~rng:s.rng ;
    if is_boss m.kind then
      trigger_boss_cinematic
        s
        ~x:mx_f
        ~y:my_f
        ~name:(String.uppercase_ascii (monster_name m.kind))
    else s.last_action <- Printf.sprintf "Killed %s" (monster_name m.kind)
  end

(* Player-side damage with HP clamp and game-over transition.
   [cause] is a short string describing what dealt the damage (e.g.
   "Killed by spider") — stored in [last_death_cause] if HP reaches 0. *)
let player_take_damage s ~dmg ?(cause = "") () =
  let dmg = if s.player.has_armor then max 1 (dmg - 1) else dmg in
  s.player.hp <- s.player.hp - dmg ;
  s.player.rest_t <- 0.0 ;
  Arcade_kit.Screen_fx.flash s.fx ~intensity:0.55 ~duration:0.2 ;
  spawn_popup
    s
    ~wx:s.player.x
    ~wy:(s.player.y -. 0.3)
    ~text:(Printf.sprintf "-%d" dmg)
    ~r:255
    ~g:80
    ~b:80 ;
  if s.player.hp <= 0 then begin
    s.player.hp <- 0 ;
    if cause <> "" then s.last_death_cause <- cause ;
    let final = s.deepest_reached in
    s.best_floor <- Arcade_kit.Score_store.record ~demo:"miaou_crypt" final ;
    s.best_score <-
      Arcade_kit.Score_store.record ~demo:"miaou_crypt_score" s.score ;
    s.mode <- Game_over ;
    s.mode_t <- 0.0
  end

(* Attack damage formula: 1 + sword_bonus + level_attack_bonus + small random roll.
   Wraiths take half (rounded up) — ghostly. *)
let attack_damage s (kind : monster_kind) =
  let base =
    1 + s.player.sword_bonus + s.player.level_attack_bonus
    + Random.State.int s.rng 2
  in
  match kind with Wraith -> max 1 ((base + 1) / 2) | _ -> base

(* Knockback: push monster one tile away from the player, if that tile
   is passable and unoccupied. Also set stun_t = 0.4. Bosses (Lich /
   Dragon) are not knocked back — they are too heavy. *)
let apply_knockback (s : t) (m : monster) =
  if is_boss m.kind then begin
    m.stun_t <- 0.25
  end
  else begin
    let dx = m.mx - int_of_float s.player.x in
    let dy = m.my - int_of_float s.player.y in
    (* Pick the dominant direction away from the player. *)
    let kbdx, kbdy =
      if abs dx >= abs dy then ((if dx >= 0 then 1 else -1), 0)
      else (0, if dy >= 0 then 1 else -1)
    in
    let nx = m.mx + kbdx in
    let ny = m.my + kbdy in
    let t = tile_at s.floor ~x:nx ~y:ny in
    if (not (is_blocking t)) && monster_at s ~x:nx ~y:ny = None then begin
      m.mx <- nx ;
      m.my <- ny ;
      m.rx <- float_of_int nx +. 0.5 ;
      m.ry <- float_of_int ny +. 0.5
    end ;
    (* Zombies are immune to stun — they are undead and lumbering. *)
    if m.kind <> Zombie then m.stun_t <- 0.4
  end

(* Player attack: deal damage to monster directly in front. Returns
   [true] if there was a monster to attack. Sets attack_flash_t so
   [view.ml] draws the slash overlay for 0.3 s. Applies knockback + stun
   so hits feel weighty. *)
let try_attack (s : t) =
  let fx = int_of_float s.player.x + s.player.facing.dx in
  let fy = int_of_float s.player.y + s.player.facing.dy in
  match monster_at s ~x:fx ~y:fy with
  | None -> false
  | Some m ->
      let dmg = attack_damage s m.kind in
      let was_alive_before = m.alive in
      s.attack_flash_t <- 0.3 ;
      damage_monster s m ~dmg ;
      s.last_action <- Printf.sprintf "Hit %s for %d" (monster_name m.kind) dmg ;
      (* Knockback + stun only if the monster survived the hit. *)
      if was_alive_before && m.alive then begin
        apply_knockback s m ;
        (* Stunned monsters can't strike back. *)
        if m.stun_t <= 0.0 then begin
          let bite = monster_damage m.kind in
          s.last_action <- s.last_action ^ Printf.sprintf " · took %d" bite ;
          player_take_damage
            s
            ~dmg:bite
            ~cause:(Printf.sprintf "Killed by %s" (monster_name m.kind))
            ()
        end
      end ;
      true

(* Spin attack: spend 1 special charge to deal 3 damage to every
   monster in the 8 surrounding tiles (cardinal + diagonal). Triggers
   a screen shake for impact. Returns [true] if the attack could fire
   (i.e. player had at least 1 charge). *)
let try_spin_attack (s : t) =
  if s.player.special_charges <= 0 then begin
    s.last_action <- "No charges! (⚡×0)" ;
    false
  end
  else begin
    s.player.special_charges <- s.player.special_charges - 1 ;
    s.attack_flash_t <- 0.3 ;
    Arcade_kit.Screen_fx.shake s.fx ~magnitude:0.8 ~duration:0.3 ;
    let px = int_of_float s.player.x in
    let py = int_of_float s.player.y in
    let hit_count = ref 0 in
    for dy = -1 to 1 do
      for dx = -1 to 1 do
        if not (dx = 0 && dy = 0) then begin
          let tx = px + dx in
          let ty = py + dy in
          match monster_at s ~x:tx ~y:ty with
          | None -> ()
          | Some m ->
              incr hit_count ;
              damage_monster s m ~dmg:3
        end
      done
    done ;
    s.last_action <- Printf.sprintf "Spin attack! (%d hit)" !hit_count ;
    true
  end

(* Bomb scroll: damage all monsters within radius 3 tiles for 5 HP.
   Spawns 24 orange/red particles, triggers screen shake. *)
let use_bomb (s : t) =
  if s.player.bomb_count <= 0 then s.last_action <- "No bomb scrolls"
  else begin
    s.player.bomb_count <- s.player.bomb_count - 1 ;
    Arcade_kit.Particles.spawn_burst
      s.particles
      ~x:s.player.x
      ~y:s.player.y
      ~n:24
      ~speed:8.0
      ~life:0.8
      ~hue:8
      ~rng:s.rng ;
    Arcade_kit.Screen_fx.shake s.fx ~magnitude:1.0 ~duration:0.4 ;
    let px = int_of_float s.player.x in
    let py = int_of_float s.player.y in
    let hit_count = ref 0 in
    Array.iter
      (fun (m : monster) ->
        if m.alive then begin
          let dist = abs (m.mx - px) + abs (m.my - py) in
          if dist <= 3 then begin
            incr hit_count ;
            damage_monster s m ~dmg:5
          end
        end)
      s.monsters ;
    s.last_action <- Printf.sprintf "BOMB! (%d hit)" !hit_count
  end

let drink_potion (s : t) =
  if s.player.potions <= 0 then s.last_action <- "No potions"
  else begin
    s.player.potions <- s.player.potions - 1 ;
    let heal = 5 in
    s.player.hp <- min s.player.hp_max (s.player.hp + heal) ;
    spawn_popup
      s
      ~wx:s.player.x
      ~wy:(s.player.y -. 0.3)
      ~text:(Printf.sprintf "+%d" heal)
      ~r:120
      ~g:240
      ~b:150 ;
    s.last_action <- Printf.sprintf "+%d HP" heal
  end

let light_torch (s : t) =
  if s.player.torches <= 0 then s.last_action <- "No torches"
  else begin
    s.player.torches <- s.player.torches - 1 ;
    s.player.torch_timer <- 30.0 ;
    s.last_action <- "Torch lit"
  end

(* Player interact (Space). Order:
   1. attack monster in front
   2. open door in front (consume key if locked)
   3. otherwise no-op *)
let try_interact (s : t) =
  if try_attack s then ()
  else
    let fx = int_of_float s.player.x + s.player.facing.dx in
    let fy = int_of_float s.player.y + s.player.facing.dy in
    match tile_at s.floor ~x:fx ~y:fy with
    | Door {open_ = false; locked = true} ->
        if s.player.keys > 0 then begin
          s.player.keys <- s.player.keys - 1 ;
          set_tile s.floor ~x:fx ~y:fy (Door {open_ = true; locked = false}) ;
          s.last_action <- "Door unlocked"
        end
        else s.last_action <- "Door is locked"
    | Door {open_ = false; locked = false} ->
        set_tile s.floor ~x:fx ~y:fy (Door {open_ = true; locked = false}) ;
        s.last_action <- "Door opens"
    | _ -> ()

(* ---------- archer projectiles ---------- *)

let alloc_projectile s =
  let n = Array.length s.projectiles in
  let rec loop i =
    if i >= n then None
    else if not s.projectiles.(i).alive then Some s.projectiles.(i)
    else loop (i + 1)
  in
  loop 0

(* Fire a grid-level arrow from (ox, oy) toward the player. The
   direction is the dominant cardinal component. *)
let archer_shoot s ~ox ~oy =
  let dpx = int_of_float s.player.x - ox in
  let dpy = int_of_float s.player.y - oy in
  let pdx, pdy =
    if abs dpx >= abs dpy then ((if dpx > 0 then 1 else -1), 0)
    else (0, if dpy > 0 then 1 else -1)
  in
  match alloc_projectile s with
  | None -> ()
  | Some proj ->
      proj.alive <- true ;
      proj.px <- ox + pdx ;
      proj.py <- oy + pdy ;
      proj.pdx <- pdx ;
      proj.pdy <- pdy ;
      proj.tick_t <- 0.25

let tick_projectiles (s : t) ~dt =
  Array.iter
    (fun (proj : projectile) ->
      if proj.alive then begin
        proj.tick_t <- proj.tick_t -. dt ;
        if proj.tick_t <= 0.0 then begin
          proj.tick_t <- proj.tick_t +. 0.25 ;
          let nx = proj.px + proj.pdx in
          let ny = proj.py + proj.pdy in
          let t = tile_at s.floor ~x:nx ~y:ny in
          let px_tile = int_of_float s.player.x in
          let py_tile = int_of_float s.player.y in
          if nx = px_tile && ny = py_tile then begin
            (* Hit player *)
            proj.alive <- false ;
            let dmg = 2 in
            s.last_action <- Printf.sprintf "Arrow hits! (-%d)" dmg ;
            player_take_damage s ~dmg ~cause:"Killed by archer" () ;
            Arcade_kit.Screen_fx.flash s.fx ~intensity:0.3 ~duration:0.15
          end
          else if is_blocking t then
            (* Hit wall *)
            proj.alive <- false
          else begin
            proj.px <- nx ;
            proj.py <- ny
          end
        end
      end)
    s.projectiles

(* ---------- monster passive logic ---------- *)

(* Spider: stays put. Skeleton: stays put but bites if adjacent (every
   1.5 s). Bat: random walk. Wraith: drifts toward player at 1 tile/s,
   damages on contact tile, but cannot enter walls. Lich: stays put,
   periodically launches a fireball; melee on adjacency. Dragon: same
   pattern, faster fireball cadence + higher damage. Archer: stands
   3+ tiles away and shoots every 2 s; slowly strafes when closer.

   Monsters 2+ tiles away occasionally strafe to avoid bunching up.
   If a monster tries to move and finds another monster occupying the
   target tile, it sets wait_t = 0.5 and yields instead. *)

let manhattan_to_player (s : t) ~x ~y =
  abs (x - int_of_float s.player.x) + abs (y - int_of_float s.player.y)

let player_adjacent (s : t) ~x ~y = manhattan_to_player s ~x ~y = 1

(* Move monster toward player, with strafe logic for distant monsters.
   Returns true if a step happened. Applies wait_t yielding if blocked
   by another monster. *)
let try_move_toward_player (s : t) (m : monster) =
  if m.wait_t > 0.0 then false
  else begin
    let px = int_of_float s.player.x in
    let py = int_of_float s.player.y in
    let dx = if px > m.mx then 1 else if px < m.mx then -1 else 0 in
    let dy = if py > m.my then 1 else if py < m.my then -1 else 0 in
    let dist = manhattan_to_player s ~x:m.mx ~y:m.my in
    (* Choose whether to try a strafe step: 25% chance when 2+ tiles away. *)
    let strafe = dist >= 2 && Random.State.int s.rng 4 = 0 in
    (* Primary direction toward player; perpendicular if strafing. *)
    let sdx, sdy =
      if not strafe then (dx, dy)
      else if dx <> 0 then (0, if Random.State.bool s.rng then 1 else -1)
      else ((if Random.State.bool s.rng then 1 else -1), 0)
    in
    let nx = m.mx + sdx in
    let ny = m.my + sdy in
    let t = tile_at s.floor ~x:nx ~y:ny in
    if is_blocking t then false
    else begin
      let player_there =
        nx = int_of_float s.player.x && ny = int_of_float s.player.y
      in
      if player_there then false
      else
        match monster_at s ~x:nx ~y:ny with
        | Some _ ->
            (* Another monster is in the way: yield and wait. *)
            m.wait_t <- 0.5 ;
            false
        | None ->
            m.mx <- nx ;
            m.my <- ny ;
            true
    end
  end

let try_monster_step (s : t) (m : monster) ~nx ~ny =
  let t = tile_at s.floor ~x:nx ~y:ny in
  if is_blocking t then false
  else
    match monster_at s ~x:nx ~y:ny with
    | Some _ -> false
    | None ->
        let px = int_of_float s.player.x in
        let py = int_of_float s.player.y in
        if nx = px && ny = py then false
        else begin
          m.mx <- nx ;
          m.my <- ny ;
          true
        end

let bite_player_if_adjacent s (m : monster) =
  if player_adjacent s ~x:m.mx ~y:m.my then begin
    let dmg = monster_damage m.kind in
    s.last_action <-
      Printf.sprintf "%s bites you (-%d)" (monster_name m.kind) dmg ;
    player_take_damage
      s
      ~dmg
      ~cause:(Printf.sprintf "Killed by %s" (monster_name m.kind))
      ()
  end

(* Step a wraith continuously toward the player. Collision is sampled
   at the new continuous position; we keep the wraith on its current
   tile if it can't progress. *)
let tick_wraith s (m : monster) ~dt =
  let speed = 1.0 in
  let dxp = s.player.x -. m.rx in
  let dyp = s.player.y -. m.ry in
  let dist = Float.sqrt ((dxp *. dxp) +. (dyp *. dyp)) in
  if dist > 0.001 then begin
    let nx = m.rx +. (dxp /. dist *. speed *. dt) in
    let ny = m.ry +. (dyp /. dist *. speed *. dt) in
    let tx = int_of_float nx in
    let ty = int_of_float ny in
    let t = tile_at s.floor ~x:tx ~y:ty in
    if not (is_blocking t) then begin
      m.rx <- nx ;
      m.ry <- ny ;
      m.mx <- tx ;
      m.my <- ty
    end
  end ;
  (* Phase teleport: every 5 s, jump to the tile directly in front of the player
     if it is passable and within 6 Manhattan tiles. *)
  m.phase_t <- Float.max 0.0 (m.phase_t -. dt) ;
  if m.phase_t <= 0.0 then begin
    m.phase_t <- 5.0 ;
    let tx = int_of_float s.player.x + s.player.facing.dx in
    let ty = int_of_float s.player.y + s.player.facing.dy in
    let dist_to_target = abs (tx - m.mx) + abs (ty - m.my) in
    let t = tile_at s.floor ~x:tx ~y:ty in
    if (not (is_blocking t)) && dist_to_target <= 6 then begin
      m.mx <- tx ;
      m.my <- ty ;
      m.rx <- float_of_int tx +. 0.5 ;
      m.ry <- float_of_int ty +. 0.5 ;
      Arcade_kit.Screen_fx.flash s.fx ~intensity:0.3 ~duration:0.2
    end
  end ;
  if m.cooldown <= 0.0 && manhattan_to_player s ~x:m.mx ~y:m.my <= 1 then begin
    m.cooldown <- 1.4 ;
    bite_player_if_adjacent s m
  end

let tick_boss_projectile s (m : monster) ~dt =
  if m.proj_active then begin
    m.proj_x <- m.proj_x +. (m.proj_dx *. dt) ;
    m.proj_y <- m.proj_y +. (m.proj_dy *. dt) ;
    m.proj_life <- m.proj_life -. dt ;
    let tx = int_of_float m.proj_x in
    let ty = int_of_float m.proj_y in
    let t = tile_at s.floor ~x:tx ~y:ty in
    let hit_player =
      let px = int_of_float s.player.x in
      let py = int_of_float s.player.y in
      tx = px && ty = py
    in
    if hit_player then begin
      m.proj_active <- false ;
      let dmg = monster_damage m.kind in
      s.last_action <-
        Printf.sprintf "%s fireball hits (-%d)" (monster_name m.kind) dmg ;
      player_take_damage
        s
        ~dmg
        ~cause:(Printf.sprintf "Killed by %s fireball" (monster_name m.kind))
        () ;
      Arcade_kit.Particles.spawn_burst
        s.particles
        ~x:m.proj_x
        ~y:m.proj_y
        ~n:18
        ~speed:6.0
        ~life:0.5
        ~hue:8
        ~rng:s.rng
    end
    else if is_blocking t || m.proj_life <= 0.0 then begin
      m.proj_active <- false ;
      Arcade_kit.Particles.spawn_burst
        s.particles
        ~x:m.proj_x
        ~y:m.proj_y
        ~n:8
        ~speed:3.0
        ~life:0.3
        ~hue:6
        ~rng:s.rng
    end
  end

(* Fire a continuous boss projectile from the monster toward the player. *)
let fire_boss_projectile s (m : monster) =
  let mx_f = float_of_int m.mx +. 0.5 in
  let my_f = float_of_int m.my +. 0.5 in
  let dxp = s.player.x -. mx_f in
  let dyp = s.player.y -. my_f in
  let len = Float.sqrt ((dxp *. dxp) +. (dyp *. dyp)) in
  if len > 0.001 && len < 12.0 then begin
    let speed = match m.kind with Dragon -> 5.0 | _ -> 3.5 in
    m.proj_active <- true ;
    m.proj_x <- mx_f ;
    m.proj_y <- my_f ;
    m.proj_dx <- dxp /. len *. speed ;
    m.proj_dy <- dyp /. len *. speed ;
    m.proj_life <- 4.0
  end

(* Dragon phase 2: fire 5 bullets in a ±40° fan from the dragon toward
   the player. Uses the projectile pool for extra bullets. *)
let fire_breath_cone s (m : monster) =
  let mx_f = float_of_int m.mx +. 0.5 in
  let my_f = float_of_int m.my +. 0.5 in
  let dxp = s.player.x -. mx_f in
  let dyp = s.player.y -. my_f in
  let len = Float.sqrt ((dxp *. dxp) +. (dyp *. dyp)) in
  if len > 0.001 && len < 14.0 then begin
    s.boss_warning <- false ;
    let base_angle = Float.atan2 dyp dxp in
    let cone_half = 0.6981 in
    (* ~40° in radians *)
    (* Centre bullet fires as the monster's own projectile. *)
    m.proj_active <- true ;
    m.proj_x <- mx_f ;
    m.proj_y <- my_f ;
    let speed = 4.5 in
    m.proj_dx <- Float.cos base_angle *. speed ;
    m.proj_dy <- Float.sin base_angle *. speed ;
    m.proj_life <- 4.0 ;
    (* Four extra bullets at ±20° and ±40° using the shared projectile pool. *)
    let offsets =
      [|-.cone_half; -.cone_half /. 2.0; cone_half /. 2.0; cone_half|]
    in
    Array.iter
      (fun angle_off ->
        let a = base_angle +. angle_off in
        match alloc_projectile s with
        | None -> ()
        | Some proj ->
            proj.alive <- true ;
            proj.px <- m.mx ;
            proj.py <- m.my ;
            (* Encode continuous direction into discrete step — use the dominant
               cardinal direction of this angle. *)
            let vx = Float.cos a in
            let vy = Float.sin a in
            proj.pdx <-
              (if Float.abs vx >= Float.abs vy then if vx >= 0.0 then 1 else -1
               else 0) ;
            proj.pdy <-
              (if Float.abs vy > Float.abs vx then if vy >= 0.0 then 1 else -1
               else 0) ;
            proj.tick_t <- 0.2)
      offsets
  end

let tick_boss s (m : monster) ~dt =
  tick_boss_projectile s m ~dt ;
  (* Dragon phase tracking: phase 2 at HP ≤ 50%; phase 3 at HP ≤ 25%. *)
  if m.kind = Dragon then begin
    let phase =
      if m.hp * 4 <= m.hp_max then 3 else if m.hp * 2 <= m.hp_max then 2 else 1
    in
    if phase <> s.dragon_phase then begin
      s.dragon_phase <- phase ;
      if phase = 2 then begin
        s.last_action <- "DRAGON ENRAGES!" ;
        Arcade_kit.Screen_fx.shake s.fx ~magnitude:1.0 ~duration:0.3
      end
      else if phase = 3 then begin
        s.last_action <- "DRAGON ADVANCES!" ;
        Arcade_kit.Screen_fx.shake s.fx ~magnitude:1.4 ~duration:0.4
      end
    end ;
    (* Phase 3: boss advances one tile toward player every 3 s. *)
    if s.dragon_phase >= 3 then begin
      s.boss_move_t <- s.boss_move_t -. dt ;
      if s.boss_move_t <= 0.0 then begin
        s.boss_move_t <- 3.0 ;
        let px = int_of_float s.player.x in
        let py = int_of_float s.player.y in
        let dx = if px > m.mx then 1 else if px < m.mx then -1 else 0 in
        let dy = if py > m.my then 1 else if py < m.my then -1 else 0 in
        (* Try the dominant direction first. *)
        let nx, ny =
          if abs (px - m.mx) >= abs (py - m.my) then (m.mx + dx, m.my)
          else (m.mx, m.my + dy)
        in
        let t = tile_at s.floor ~x:nx ~y:ny in
        if
          (not (is_blocking t))
          && monster_at s ~x:nx ~y:ny = None
          && not (nx = px && ny = py)
        then begin
          m.mx <- nx ;
          m.my <- ny ;
          m.rx <- float_of_int nx +. 0.5 ;
          m.ry <- float_of_int ny +. 0.5
        end
      end
    end
  end ;
  if m.kind = Dragon && s.dragon_phase = 2 then begin
    (* Phase 2: breath cone every 2.5 s instead of aimed single shot. *)
    s.breath_cone_t <- s.breath_cone_t -. dt ;
    (* Warning banner 0.5 s before fire. *)
    if s.breath_cone_t <= 0.5 && s.breath_cone_t > 0.0 then
      s.boss_warning <- true ;
    if s.breath_cone_t <= 0.0 then begin
      s.breath_cone_t <- 2.5 ;
      fire_breath_cone s m
    end ;
    (* Still allow melee on adjacency. *)
    if m.cooldown <= 0.0 && player_adjacent s ~x:m.mx ~y:m.my then begin
      m.cooldown <- 1.2 ;
      bite_player_if_adjacent s m
    end
  end
  else begin
    if m.cooldown <= 0.0 then begin
      let cadence =
        match m.kind with Lich -> 2.5 | Dragon -> 1.6 | _ -> 3.0
      in
      m.cooldown <- cadence ;
      if player_adjacent s ~x:m.mx ~y:m.my then bite_player_if_adjacent s m
      else if not m.proj_active then fire_boss_projectile s m
    end
  end

(* Archer AI: stand 3+ tiles away and shoot every 2 s.
   When closer, strafe sideways slowly. Never moves toward the player. *)
let tick_archer s (m : monster) ~dt =
  ignore dt ;
  let dist = manhattan_to_player s ~x:m.mx ~y:m.my in
  if m.cooldown <= 0.0 then begin
    if dist >= 3 then begin
      m.cooldown <- 2.0 ;
      archer_shoot s ~ox:m.mx ~oy:m.my
    end
    else begin
      (* Too close: strafe sideways to regain distance. *)
      m.cooldown <- 0.8 ;
      let px = int_of_float s.player.x in
      let py = int_of_float s.player.y in
      let dx = if px > m.mx then 1 else if px < m.mx then -1 else 0 in
      let _dy = if py > m.my then 1 else if py < m.my then -1 else 0 in
      (* Perpendicular strafe direction. *)
      let sdx, sdy =
        if dx <> 0 then (0, if Random.State.bool s.rng then 1 else -1)
        else ((if Random.State.bool s.rng then 1 else -1), 0)
      in
      ignore (try_monster_step s m ~nx:(m.mx + sdx) ~ny:(m.my + sdy))
    end
  end

let tick_monsters (s : t) ~dt =
  Array.iter
    (fun (m : monster) ->
      if m.alive then begin
        m.cooldown <- Float.max 0.0 (m.cooldown -. dt) ;
        m.hit_flash <- Float.max 0.0 (m.hit_flash -. dt) ;
        m.wait_t <- Float.max 0.0 (m.wait_t -. dt) ;
        (* Alert display timer: count down independently of stun. *)
        if m.alert_display_t > 0.0 then
          m.alert_display_t <- Float.max 0.0 (m.alert_display_t -. dt) ;
        (* Alert detection: first time player is within 4 Manhattan tiles,
           set alerted and halve current cooldown for fast-movers. *)
        if not m.alerted then begin
          let dist = manhattan_to_player s ~x:m.mx ~y:m.my in
          if dist <= 4 then begin
            m.alerted <- true ;
            m.alert_display_t <- 1.5 ;
            (* Halve the remaining cooldown for Spider/Skeleton/Zombie. *)
            match m.kind with
            | Spider | Skeleton | Zombie -> m.cooldown <- m.cooldown /. 2.0
            | _ -> ()
          end
        end ;
        (* Stun: decrement and skip AI while stunned. *)
        if m.stun_t > 0.0 then begin m.stun_t <- Float.max 0.0 (m.stun_t -. dt)
          (* no AI this frame *)
        end
        else begin
          (* Keep grid-locked monsters' continuous coords in sync. *)
          if m.kind <> Wraith then begin
            m.rx <- float_of_int m.mx +. 0.5 ;
            m.ry <- float_of_int m.my +. 0.5
          end ;
          match m.kind with
          | Bat ->
              (* Bats use a persistent direction that changes every ~0.5 s.
                 They move faster than other monsters (0.15 s interval). *)
              m.bat_dir_t <- Float.max 0.0 (m.bat_dir_t -. dt) ;
              if m.bat_dir_t <= 0.0 then begin
                m.bat_dir_t <- 0.4 +. Random.State.float s.rng 0.2 ;
                let dirs = [|(1, 0); (-1, 0); (0, 1); (0, -1)|] in
                let pick = dirs.(Random.State.int s.rng 4) in
                m.bat_dx <- fst pick ;
                m.bat_dy <- snd pick
              end ;
              if m.cooldown <= 0.0 then begin
                m.cooldown <- 0.15 ;
                ignore
                  (try_monster_step
                     s
                     m
                     ~nx:(m.mx + m.bat_dx)
                     ~ny:(m.my + m.bat_dy))
              end
          | Spider ->
              (* Spider moves toward player; bites when adjacent.
                 Alerted spiders move at half the normal cooldown. *)
              if m.cooldown <= 0.0 then begin
                let dist = manhattan_to_player s ~x:m.mx ~y:m.my in
                if dist > 1 then begin
                  m.cooldown <- (if m.alerted then 0.35 else 0.7) ;
                  ignore (try_move_toward_player s m)
                end
                else begin
                  m.cooldown <- (if m.alerted then 1.25 else 2.5) ;
                  bite_player_if_adjacent s m
                end
              end
          | Skeleton ->
              (* Skeleton moves toward player slowly; harder bite.
                 Alerted skeletons move at half the normal cooldown. *)
              if m.cooldown <= 0.0 then begin
                let dist = manhattan_to_player s ~x:m.mx ~y:m.my in
                if dist > 1 then begin
                  m.cooldown <- (if m.alerted then 0.6 else 1.2) ;
                  ignore (try_move_toward_player s m)
                end
                else begin
                  m.cooldown <- (if m.alerted then 1.0 else 2.0) ;
                  bite_player_if_adjacent s m
                end
              end
          | Archer -> tick_archer s m ~dt
          | Zombie ->
              (* Zombie: very slow (3.0 s between moves), shambles toward
                 player; bites when adjacent.  Immune to stun (handled in
                 apply_knockback).  Drops a Healing_rune on death.
                 Alerted zombies move at half the normal cooldown. *)
              if m.cooldown <= 0.0 then begin
                let dist = manhattan_to_player s ~x:m.mx ~y:m.my in
                if dist > 1 then begin
                  m.cooldown <- (if m.alerted then 1.5 else 3.0) ;
                  ignore (try_move_toward_player s m)
                end
                else begin
                  m.cooldown <- (if m.alerted then 1.5 else 3.0) ;
                  bite_player_if_adjacent s m
                end
              end
          | Wraith -> tick_wraith s m ~dt
          | Lich | Dragon -> tick_boss s m ~dt
        end (* end else stun_t = 0 branch *)
      end)
    s.monsters

(* ---------- main tick ---------- *)

(* Decide how much animation [dt] to advance. In normal mode, always
   pass through. In debug mode, only advance when a step has been
   requested via [n]/[N]/[b], which decrement [pending_steps]. Each
   step represents one logical 1/60 s frame — but to keep monster
   pacing readable we actually advance 1/30 s per step. *)
let consume_dt (s : t) ~real_dt =
  if not s.debug_mode then real_dt
  else if s.pending_steps > 0 then begin
    s.pending_steps <- s.pending_steps - 1 ;
    1.0 /. 30.0
  end
  else 0.0

let tick (s : t) ~dt =
  s.frame_no <- s.frame_no + 1 ;
  s.mode_t <- s.mode_t +. dt ;
  let game_dt = consume_dt s ~real_dt:dt in
  s.anim_t <- s.anim_t +. game_dt ;
  match s.mode with
  | Title -> ()
  | Game_over -> Arcade_kit.Screen_fx.tick s.fx ~dt
  | Floor_clear -> Arcade_kit.Screen_fx.tick s.fx ~dt
  | Boss_kill_cinematic ->
      Arcade_kit.Particles.tick s.particles ~dt:game_dt ~ax:0.0 ~ay:(-1.0) ;
      Arcade_kit.Screen_fx.tick s.fx ~dt ;
      if s.mode_t > 2.5 then begin
        s.mode <- Floor_clear ;
        s.mode_t <- 0.0
      end
  | Descending_anim anim ->
      Arcade_kit.Screen_fx.tick s.fx ~dt ;
      anim.anim_t <- anim.anim_t +. dt ;
      if anim.anim_t >= 0.8 then begin
        s.mode <- Floor_clear ;
        s.mode_t <- 0.0
      end
  | Exploring ->
      (* Reset per-tick movement flag before processing input-driven state. *)
      s.player_moved <- false ;
      tick_monsters s ~dt:game_dt ;
      tick_projectiles s ~dt:game_dt ;
      Arcade_kit.Particles.tick s.particles ~dt:game_dt ~ax:0.0 ~ay:(-1.0) ;
      advance_popups s ~dt:game_dt ;
      Arcade_kit.Screen_fx.tick s.fx ~dt ;
      if s.player.torch_timer > 0.0 then
        s.player.torch_timer <- Float.max 0.0 (s.player.torch_timer -. game_dt) ;
      if s.attack_flash_t > 0.0 then
        s.attack_flash_t <- Float.max 0.0 (s.attack_flash_t -. dt) ;
      if s.footstep_t > 0.0 then
        s.footstep_t <- Float.max 0.0 (s.footstep_t -. dt) ;
      if s.levelup_flash_t > 0.0 then
        s.levelup_flash_t <- Float.max 0.0 (s.levelup_flash_t -. dt) ;
      if s.player.speed_ring_timer > 0.0 then
        s.player.speed_ring_timer <-
          Float.max 0.0 (s.player.speed_ring_timer -. game_dt) ;
      (* Passive HP regen: accumulate rest_t while standing still.
         When it reaches 4.0 s and HP is below max, restore 1 HP. *)
      if not s.player_moved then begin
        if game_dt > 0.0 then begin
          s.player.rest_t <- s.player.rest_t +. game_dt ;
          if s.player.rest_t >= 4.0 && s.player.hp < s.player.hp_max then begin
            s.player.rest_t <- 0.0 ;
            s.player.hp <- s.player.hp + 1 ;
            spawn_popup
              s
              ~wx:s.player.x
              ~wy:(s.player.y -. 0.5)
              ~text:"+1"
              ~r:120
              ~g:240
              ~b:150
          end
        end
      end
      else s.player.rest_t <- 0.0

(* ---------- debug step entry points (called from page) ---------- *)

let debug_step1 s = if s.debug_mode then s.pending_steps <- s.pending_steps + 1

let debug_step10 s =
  if s.debug_mode then s.pending_steps <- s.pending_steps + 10

let debug_step60 s =
  if s.debug_mode then s.pending_steps <- s.pending_steps + 60
