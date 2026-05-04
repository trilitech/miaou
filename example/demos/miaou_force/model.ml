(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

module Arcade_kit = Demo_shared.Arcade_kit

(** Game model for MIAOU Force, an R-Type-style horizontal shoot-em-up.

    Coordinates: world space is in pixels of the framebuffer (Octant 2×4
    sub-cells). The "camera" scrolls rightward over time so the world
    feels infinite while the ship's screen position stays bounded. Most
    entities live in screen-pixel coordinates and are despawned when they
    leave the visible area. *)

(* ---------- constants ---------- *)

let max_enemies = 128

let max_player_bullets = 128

let max_enemy_bullets = 160

let max_score_popups = 48

let particle_capacity = 1024

(* Charge thresholds for charge beam release. *)
let charge_full_threshold = 0.85

let charge_beam_speed = 160.0

(* World scroll rate, pixels-per-second. *)
let scroll_speed = 26.0

(* Ship movement speed in px/s (base). *)
let ship_speed_base = 60.0

let bullet_speed = 110.0

let force_dock_offset = 8.0
(* Pixels in front of ship when docked-front. *)

(* Max mine chain-explosion depth to avoid lag spikes. *)
let mine_chain_max_depth = 8

(* ---------- power-up weapon state ---------- *)

(* The player carries these passive weapon upgrades. They persist across
   lives within a level but are not carried between levels (configurable
   later). Speed stacks up to 3 times. *)
type weapon_state = {
  mutable speed_level : int; (* 0..3: each +25% movement speed *)
  mutable has_missile : bool; (* fires 3 missiles per shot *)
  mutable has_force_upgrade : bool;
      (* Force pod fires 3 bullets, wider hitbox *)
  mutable has_shield : bool; (* absorbs hits (flashes instead of dying) *)
  mutable shield_active : bool; (* true = shield has remaining hits *)
  mutable shield_hits : int;
      (* remaining shield hits; 2 when freshly acquired *)
  mutable flash_t : float; (* > 0 while shield-hit flash is playing *)
  mutable pickup_flash_t : float;
      (* > 0 for 0.2s after picking up any power-up; ship draws white *)
}

let make_weapon_state () =
  {
    speed_level = 0;
    has_missile = false;
    has_force_upgrade = false;
    has_shield = false;
    shield_active = false;
    shield_hits = 0;
    flash_t = 0.0;
    pickup_flash_t = 0.0;
  }

(* ---------- entities ---------- *)

type enemy_kind =
  | Grunt (* horizontal sweeper *)
  | Diver (* dives down then levels *)
  | Turret (* slow, fires bullets *)
  | Strafer (* fast zigzag *)
  | Shielded (* heavily armored, requires multiple hits *)
  | Mine (* stationary; explodes when shot, chains to neighbours *)
  | Splitter (* splits into 2 scatter bullets on death *)
  | Laser_emitter (* charges 1.5s then fires horizontal laser sweep *)
  | Carrier (* large slow ship; periodically spawns Grunt enemies *)
  | Boomerang (* arc-motion enemy, fires spread bullets *)
  | Boss

type enemy = {
  mutable alive : bool;
  mutable kind : enemy_kind;
  mutable x : float;
  mutable y : float;
  mutable y0 : float;
  (* spawn y, used by sinusoidal motion *)
  mutable phase : float;
  mutable hp : int;
  mutable fire_t : float;
  (* time until next shot (turret/boss only) *)
  mutable score : int;
  (* Shield HP for Shielded enemies; counts down before [hp] takes damage. *)
  mutable shield : int;
  (* Hit-flash timer for any enemy after taking damage. *)
  mutable hit_flash : float;
  (* Boss phase: 1, 2, or 3. Other enemies leave at 0. *)
  mutable boss_phase : int;
  (* Mine fuse — when > 0, mine is in chain-explosion countdown. *)
  mutable mine_fuse : float;
  (* Laser emitter charge — counts from 0 to 1.5, then fires. *)
  mutable laser_charge : float;
  (* Laser emitter firing — when > 0, laser is active (sweeping). *)
  mutable laser_fire_t : float;
  (* mine/splitter chain depth guard *)
  mutable chain_depth : int;
  (* Age since spawn in seconds — used for spawn fade-in animation. *)
  mutable age : float;
  (* Facing direction for Turret: 0=right, 1=up, 2=left, 3=down. *)
  mutable face_dir : int;
}

let dead_enemy () =
  {
    alive = false;
    kind = Grunt;
    x = 0.;
    y = 0.;
    y0 = 0.;
    phase = 0.;
    hp = 0;
    fire_t = 0.;
    score = 0;
    shield = 0;
    hit_flash = 0.;
    boss_phase = 0;
    mine_fuse = 0.;
    laser_charge = 0.;
    laser_fire_t = 0.;
    chain_depth = 0;
    age = 0.;
    face_dir = 2;
  }

(* Bullet flavours: regular shots, wide charge beams (player), homing
   bullets used by boss phase 2, diagonal missiles from Missile upgrade,
   enemy laser segment (one-tick wide beams). *)
type bullet_kind =
  | Bullet_normal
  | Bullet_beam
  | Bullet_homing
  | Bullet_missile (* player diagonal missile *)
  | Bullet_laser (* enemy laser sweep segment — wide *)

type bullet = {
  mutable b_alive : bool;
  mutable bx : float;
  mutable by : float;
  mutable bvx : float;
  mutable bvy : float;
  mutable b_kind : bullet_kind;
  mutable b_life : float;
  (* Optional homing target — only used when b_kind = Bullet_homing. *)
  mutable b_home_t : float;
}

let dead_bullet () =
  {
    b_alive = false;
    bx = 0.;
    by = 0.;
    bvx = 0.;
    bvy = 0.;
    b_kind = Bullet_normal;
    b_life = 0.;
    b_home_t = 0.;
  }

type force_state =
  | Force_front
  | Force_back
  | Force_detached of {
      mutable fx : float; (* world x pos *)
      mutable fy : float; (* screen y pos *)
      mutable fvx : float; (* world-space x velocity *)
      mutable recalling : bool; (* true = heading back to ship *)
      mutable force_fire_t : float;
          (* countdown until detached Force auto-fires *)
      mutable recall_t : float;
          (* > 0 for 0.3s after recall triggered — pod moves at 2× speed *)
    }

(* Player. There's a slot for a future second player but only player 0 is
   wired tonight. *)
type player = {
  mutable x : float;
  mutable y : float;
  mutable cooldown : float;
  mutable charge : float;
  (* 0..1 charge meter *)
  mutable invuln : float;
  mutable force : force_state;
  mutable alive : bool;
  weapons : weapon_state;
  (* Speed-burst power-up timer: > 0 while the burst is active. *)
  mutable speed_boost_t : float;
}

(* ---------- spawn events (level data) ---------- *)

(* A spawn event fires when world_x reaches [trigger_x]. Levels are
   hand-authored in [Levels] and passed as parameter to [start_level]
   so the module dep stays Model ← Levels. *)

type pickup =
  | Power_up_speed
  | Power_up_force_repair
  | Power_up_missile (* Missile: diagonal shots *)
  | Power_up_force_upgrade (* Force pod upgrade *)
  | Power_up_shield (* Shield: absorb one hit *)
  | Power_up_speed_burst (* Temporary speed/fire-rate surge *)

(* A score popup floats up briefly when an enemy is killed. We keep a
   fixed-size pool to avoid per-frame allocation. *)
type score_popup = {
  mutable sp_alive : bool;
  mutable sp_x : float;
  mutable sp_y : float;
  mutable sp_vy : float;
  mutable sp_life : float;
  mutable sp_life0 : float;
  mutable sp_text : string;
  mutable sp_hue : int;
}

let dead_score_popup () =
  {
    sp_alive = false;
    sp_x = 0.;
    sp_y = 0.;
    sp_vy = 0.;
    sp_life = 0.;
    sp_life0 = 0.;
    sp_text = "";
    sp_hue = 0;
  }

type spawn =
  | Spawn_enemy of {kind : enemy_kind; y : float; hp : int; score : int}
  | Spawn_pickup of pickup * float (* y *)
  | Spawn_boss of {hp : int; score : int}
  | Spawn_hazard of {world_x : float; y : float; height : int}

type event = {trigger_x : float; spawn : spawn}

(* Visual signature for each level — controls background/terrain colour. *)
type level_palette =
  | Palette_rocky (* Level 1: brown/grey rocky terrain, orange enemies *)
  | Palette_asteroid (* Level 2: dark blue/teal, asteroid chunks *)
  | Palette_core (* Level 3: red-tinted, tight corridors *)

(* ---------- terrain hazards ---------- *)

(* A spike hazard column at a fixed world-x position. The player takes
   damage if they overlap it; it persists until scrolled off screen. *)
type hazard = {
  mutable h_alive : bool;
  mutable h_world_x : float;
      (* world x — convert to screen by subtracting world_x *)
  mutable h_y : float; (* screen y of spike centre *)
  mutable h_height : int; (* number of spike pixels *)
}

let max_hazards = 16

let dead_hazard () = {h_alive = false; h_world_x = 0.; h_y = 0.; h_height = 0}

(* ---------- top-level state ---------- *)

type mode =
  | Title
  | Playing
  | Level_clear_anim of {mutable anim_t : float; level : int}
  | Level_clear
  | Game_over
  | Level_select (* shown after game-over or run-complete *)

type t = {
  mutable mode : mode;
  mutable lives : int;
  mutable level : int;
  mutable score : int;
  mutable best : int;
  (* Per-level score snapshots for level-select display. *)
  mutable level_scores : int array; (* index 0=level1, 1=level2, 2=level3 *)
  (* Score at the start of the current level — used to compute per-level delta. *)
  mutable score_at_level_start : int;
  (* world scrolling distance since level start, pixels *)
  mutable world_x : float;
  (* time since mode entered, used for title / game over animations *)
  mutable mode_t : float;
  (* arena bounds in pixels — set by view each frame *)
  mutable arena_w : int;
  mutable arena_h : int;
  player : player;
  enemies : enemy array;
  player_bullets : bullet array;
  enemy_bullets : bullet array;
  particles : Arcade_kit.Particles.t;
  fx : Arcade_kit.Screen_fx.t;
  rng : Random.State.t;
  (* remaining events for the current level, head = next trigger *)
  mutable events : event list;
  (* pickup state — simple: float in world, despawn off-screen *)
  pickups : pickup_entity array;
  mutable next_page : string option;
  mutable boss_active : bool;
  mutable boss_hp_max : int;
  mutable boss_phase : int;
  (* Time dilation multiplier (1.0 normal, 0.3 during boss-death cinematic). *)
  mutable time_scale : float;
  mutable slow_mo_t : float;
  (* Score popup pool. *)
  popups : score_popup array;
  (* Turn-based debug-mode state: when [turn_based] is true, the page
     refresh ignores wall-clock dt and only advances when the user steps
     via [n], [N], or [b]. The model tracks how many frames have been
     stepped in turn-based mode for HUD overlay. *)
  mutable turn_based : bool;
  mutable frame_counter : int;
  (* Current level visual palette. *)
  mutable palette : level_palette;
  (* Level-select cursor: 0=level1, 1=level2, 2=level3. *)
  mutable level_select_cursor : int;
  (* Combo/multiplier: kills within 1.5s chain; multiplier 1–5× *)
  mutable combo : int;
  mutable combo_t : float;
  (* Highest combo reached during the current level. Reset at level start. *)
  mutable combo_max : int;
  (* Terrain spike hazards — cap 16. *)
  hazards : hazard array;
  (* Animated score display: smoothly tracks [score] via exponential lerp. *)
  mutable display_score : float;
  (* Big-kill announcement: > 0 while overlay is shown. *)
  mutable big_kill_t : float;
  mutable big_kill_text : string;
  (* Difficulty factor per level: 1.0 / 1.2 / 1.4 for levels 1/2/3.
     Scales enemy HP at spawn and enemy bullet speed at fire time. *)
  mutable difficulty_factor : float;
  (* Per-level best score: index 0=level1, 1=level2, 2=level3. Updated when
     a level is cleared. Persists within a session. *)
  mutable best_level : int array;
  (* Boss phase-change warning: > 0 while the banner is shown. *)
  mutable boss_phase_warn_t : float;
  (* Score milestone popup: text shown for milestone_t seconds at top-right. *)
  mutable milestone_t : float;
  mutable milestone_text : string;
  (* Next milestone threshold index (0=5000, 1=10000, 2=20000, 3=50000). *)
  mutable next_milestone : int;
}

and pickup_entity = {
  mutable p_alive : bool;
  mutable p_kind : pickup;
  mutable px : float;
  mutable py : float;
  mutable p_bob : float; (* bob phase for visual animation *)
}

let max_pickups = 16

let dead_pickup () =
  {p_alive = false; p_kind = Power_up_speed; px = 0.; py = 0.; p_bob = 0.}

(* ---------- helpers ---------- *)

let make_player ~arena_w:_ ~arena_h =
  {
    x = 8.0;
    y = float_of_int arena_h /. 2.0;
    cooldown = 0.0;
    charge = 0.0;
    invuln = 0.0;
    force = Force_front;
    alive = true;
    weapons = make_weapon_state ();
    speed_boost_t = 0.0;
  }

let initial_lives () =
  match Sys.getenv_opt "MIAOU_FORCE_HARD" with Some "1" -> 1 | _ -> 3

let init () =
  let best = Arcade_kit.Score_store.load ~demo:"miaou_force" in
  {
    mode = Title;
    lives = initial_lives ();
    level = 1;
    score = 0;
    best;
    level_scores = Array.make 3 0;
    score_at_level_start = 0;
    world_x = 0.0;
    mode_t = 0.0;
    arena_w = 200;
    arena_h = 80;
    player = make_player ~arena_w:200 ~arena_h:80;
    enemies = Array.init max_enemies (fun _ -> dead_enemy ());
    player_bullets = Array.init max_player_bullets (fun _ -> dead_bullet ());
    enemy_bullets = Array.init max_enemy_bullets (fun _ -> dead_bullet ());
    particles = Arcade_kit.Particles.create ~capacity:particle_capacity;
    fx = Arcade_kit.Screen_fx.create ();
    rng = Random.State.make [|0xF0CE|];
    events = [];
    pickups = Array.init max_pickups (fun _ -> dead_pickup ());
    next_page = None;
    boss_active = false;
    boss_hp_max = 0;
    boss_phase = 0;
    time_scale = 1.0;
    slow_mo_t = 0.0;
    popups = Array.init max_score_popups (fun _ -> dead_score_popup ());
    turn_based =
      (match Sys.getenv_opt "MIAOU_FORCE_TURN_BASED" with
      | Some "1" | Some "true" | Some "TRUE" | Some "on" -> true
      | _ -> false);
    frame_counter = 0;
    palette = Palette_rocky;
    level_select_cursor = 0;
    combo = 1;
    combo_t = 0.0;
    combo_max = 1;
    hazards = Array.init max_hazards (fun _ -> dead_hazard ());
    display_score = 0.0;
    big_kill_t = 0.0;
    big_kill_text = "";
    difficulty_factor = 1.0;
    best_level = Array.make 3 0;
    boss_phase_warn_t = 0.0;
    milestone_t = 0.0;
    milestone_text = "";
    next_milestone = 0;
  }

(* Reset a freshly-initialised game and load level [level] events. The
   caller passes the event list rather than letting Model depend on
   Levels — keeps the module dep graph linear. *)
let start_level (s : t) ~level ~events ~palette =
  s.level <- level ;
  s.world_x <- 0.0 ;
  s.mode_t <- 0.0 ;
  s.boss_active <- false ;
  s.boss_hp_max <- 0 ;
  s.palette <- palette ;
  s.score_at_level_start <- s.score ;
  s.difficulty_factor <- (match level with 1 -> 1.0 | 2 -> 1.2 | _ -> 1.4) ;
  s.combo_max <- 1 ;
  Array.iter (fun (e : enemy) -> e.alive <- false) s.enemies ;
  Array.iter (fun (b : bullet) -> b.b_alive <- false) s.player_bullets ;
  Array.iter (fun (b : bullet) -> b.b_alive <- false) s.enemy_bullets ;
  Array.iter (fun (p : pickup_entity) -> p.p_alive <- false) s.pickups ;
  Array.iter (fun (h : hazard) -> h.h_alive <- false) s.hazards ;
  Arcade_kit.Particles.clear s.particles ;
  s.events <- events ;
  s.player.x <- 8.0 ;
  s.player.y <- float_of_int s.arena_h /. 2.0 ;
  s.player.cooldown <- 0.0 ;
  s.player.charge <- 0.0 ;
  s.player.invuln <- 1.0 ;
  s.player.alive <- true ;
  s.player.force <- Force_front ;
  s.player.speed_boost_t <- 0.0 ;
  s.boss_phase_warn_t <- 0.0 ;
  s.milestone_t <- 0.0 ;
  s.milestone_text <- "" ;
  s.next_milestone <- 0
(* Note: weapons are intentionally NOT reset here so upgrades persist
     within a run across levels. *)

let begin_game (s : t) ~level ~events ~palette =
  s.mode <- Playing ;
  s.lives <- initial_lives () ;
  s.score <- 0 ;
  s.frame_counter <- 0 ;
  s.time_scale <- 1.0 ;
  s.slow_mo_t <- 0.0 ;
  s.combo <- 1 ;
  s.combo_t <- 0.0 ;
  s.combo_max <- 1 ;
  s.display_score <- 0.0 ;
  s.big_kill_t <- 0.0 ;
  s.big_kill_text <- "" ;
  s.boss_phase_warn_t <- 0.0 ;
  s.milestone_t <- 0.0 ;
  s.milestone_text <- "" ;
  s.next_milestone <- 0 ;
  Array.iter (fun (sp : score_popup) -> sp.sp_alive <- false) s.popups ;
  Array.fill s.level_scores 0 3 0 ;
  (* Reset weapons on a full new game. *)
  let w = s.player.weapons in
  w.speed_level <- 0 ;
  w.has_missile <- false ;
  w.has_force_upgrade <- false ;
  w.has_shield <- false ;
  w.shield_active <- false ;
  w.flash_t <- 0.0 ;
  w.pickup_flash_t <- 0.0 ;
  start_level s ~level ~events ~palette

(* ---------- entity allocators ---------- *)

let alloc_enemy s =
  let n = Array.length s.enemies in
  let rec find i =
    if i >= n then None
    else if not s.enemies.(i).alive then Some s.enemies.(i)
    else find (i + 1)
  in
  find 0

let alloc_bullet arr =
  let n = Array.length arr in
  let rec find i =
    if i >= n then None
    else if not arr.(i).b_alive then Some arr.(i)
    else find (i + 1)
  in
  find 0

let alloc_pickup s =
  let rec find i =
    if i >= Array.length s.pickups then None
    else if not s.pickups.(i).p_alive then Some s.pickups.(i)
    else find (i + 1)
  in
  find 0

let spawn_enemy s ~kind ~x ~y ~hp ~score =
  match alloc_enemy s with
  | None -> ()
  | Some e ->
      e.alive <- true ;
      e.kind <- kind ;
      e.x <- x ;
      e.y <- y ;
      e.y0 <- y ;
      e.phase <- 0.0 ;
      (* Scale HP by difficulty_factor; minimum 1. Boss HP is not scaled here
         — the level author controls it explicitly via Spawn_boss. *)
      e.hp <-
        (match kind with
        | Boss -> hp
        | _ -> max 1 (int_of_float (float_of_int hp *. s.difficulty_factor))) ;
      e.fire_t <- 1.2 ;
      e.score <- score ;
      e.shield <- (match kind with Shielded -> 3 | _ -> 0) ;
      e.hit_flash <- 0.0 ;
      e.boss_phase <- (match kind with Boss -> 1 | _ -> 0) ;
      e.mine_fuse <- 0.0 ;
      e.laser_charge <- 0.0 ;
      e.laser_fire_t <- 0.0 ;
      e.chain_depth <- 0 ;
      e.age <- 0.0 ;
      e.face_dir <- 2 ;
      (* Carrier starts with a 1.5s initial delay before first spawn. *)
      if kind = Carrier then e.fire_t <- 1.5

let alloc_hazard s =
  let rec find i =
    if i >= Array.length s.hazards then None
    else if not s.hazards.(i).h_alive then Some s.hazards.(i)
    else find (i + 1)
  in
  find 0

let spawn_hazard s ~world_x ~y ~height =
  match alloc_hazard s with
  | None -> ()
  | Some h ->
      h.h_alive <- true ;
      h.h_world_x <- world_x ;
      h.h_y <- y ;
      h.h_height <- height

let spawn_pickup s ~kind ~x ~y =
  match alloc_pickup s with
  | None -> ()
  | Some p ->
      p.p_alive <- true ;
      p.p_kind <- kind ;
      p.px <- x ;
      p.py <- y ;
      p.p_bob <- 0.0

let fire_player_bullet s ~x ~y ~vx ~vy ~kind =
  match alloc_bullet s.player_bullets with
  | None -> ()
  | Some b ->
      b.b_alive <- true ;
      b.bx <- x ;
      b.by <- y ;
      b.bvx <- vx ;
      b.bvy <- vy ;
      b.b_kind <- kind ;
      b.b_life <- 3.0 ;
      b.b_home_t <- 0.0

let fire_enemy_bullet s ~x ~y ~vx ~vy =
  match alloc_bullet s.enemy_bullets with
  | None -> ()
  | Some b ->
      b.b_alive <- true ;
      b.bx <- x ;
      b.by <- y ;
      (* Scale bullet velocity by difficulty_factor; cap speed at 250 px/s. *)
      let scale_vel v =
        let scaled = v *. s.difficulty_factor in
        let spd_in = abs_float v in
        let spd_out = abs_float scaled in
        if spd_out > 250.0 && spd_in > 0.0 then v *. (250.0 /. spd_in)
        else scaled
      in
      b.bvx <- scale_vel vx ;
      b.bvy <- scale_vel vy ;
      b.b_kind <- Bullet_normal ;
      b.b_life <- 3.0 ;
      b.b_home_t <- 0.0

(* ---------- input intent ---------- *)

(* The page collects ephemeral input intents (held keys translated to dx/dy
   plus single-tap flags) and hands them to [tick] each frame. *)

type input = {dx : float; dy : float; fire : bool; toggle_force : bool}

let neutral_input = {dx = 0.; dy = 0.; fire = false; toggle_force = false}

(* ---------- ship ---------- *)

let clamp lo hi v = if v < lo then lo else if v > hi then hi else v

let effective_ship_speed (s : t) =
  let bonus = 1.0 +. (0.25 *. float_of_int s.player.weapons.speed_level) in
  let burst = if s.player.speed_boost_t > 0.0 then 1.6 else 1.0 in
  ship_speed_base *. bonus *. burst

let move_player s ~input ~dt =
  let p = s.player in
  let aw = float_of_int s.arena_w in
  let ah = float_of_int s.arena_h in
  let speed = effective_ship_speed s in
  p.x <- clamp 4.0 (aw -. 6.0) (p.x +. (input.dx *. speed *. dt)) ;
  p.y <- clamp 4.0 (ah -. 6.0) (p.y +. (input.dy *. speed *. dt)) ;
  if p.invuln > 0.0 then p.invuln <- p.invuln -. dt ;
  (* Speed-burst countdown. *)
  if p.speed_boost_t > 0.0 then p.speed_boost_t <- p.speed_boost_t -. dt ;
  (* Shield flash animation. *)
  let w = p.weapons in
  if w.flash_t > 0.0 then w.flash_t <- w.flash_t -. dt ;
  (* Pickup flash: brief white flash on power-up collection. *)
  if w.pickup_flash_t > 0.0 then w.pickup_flash_t <- w.pickup_flash_t -. dt

let force_world_pos s =
  match s.player.force with
  | Force_front ->
      let p = s.player in
      (p.x +. force_dock_offset, p.y)
  | Force_back ->
      let p = s.player in
      (p.x -. force_dock_offset, p.y)
  | Force_detached fd ->
      (* fx is in world coords; convert to screen by subtracting world_x. *)
      (fd.fx -. s.world_x, fd.fy)

(* ---------- shooting ---------- *)

(* Fire a wide charge beam: 5 stacked bullets so the visual feels like a
   thick lance, all flagged Bullet_beam so collisions pierce. *)
let fire_charge_beam s =
  let p = s.player in
  for dy = -2 to 2 do
    match alloc_bullet s.player_bullets with
    | None -> ()
    | Some b ->
        b.b_alive <- true ;
        b.bx <- p.x +. 3.0 ;
        b.by <- p.y +. float_of_int dy ;
        b.bvx <- charge_beam_speed ;
        b.bvy <- 0.0 ;
        b.b_kind <- Bullet_beam ;
        b.b_life <- 1.5 ;
        b.b_home_t <- 0.0
  done

let fire_logic s ~input ~dt =
  let p = s.player in
  (* Charge meter: builds while space is held, releases on release. *)
  let was_full = p.charge >= charge_full_threshold in
  if input.fire then p.charge <- Float.min 1.0 (p.charge +. dt)
  else p.charge <- Float.max 0.0 (p.charge -. (dt *. 1.5)) ;
  let releasing = was_full && not input.fire in
  if releasing then begin
    fire_charge_beam s ;
    p.charge <- 0.0 ;
    Arcade_kit.Particles.spawn_burst
      s.particles
      ~x:(p.x +. 3.0)
      ~y:p.y
      ~n:14
      ~speed:18.0
      ~life:0.4
      ~hue:6
      ~rng:s.rng ;
    p.cooldown <- 0.30
  end ;
  if p.cooldown > 0.0 then p.cooldown <- p.cooldown -. dt ;
  if input.fire && p.cooldown <= 0.0 && not releasing then begin
    (* Speed burst: reduced fire interval 0.06s instead of 0.18s. *)
    p.cooldown <- (if p.speed_boost_t > 0.0 then 0.06 else 0.18) ;
    fire_player_bullet
      s
      ~x:(p.x +. 3.0)
      ~y:p.y
      ~vx:bullet_speed
      ~vy:0.0
      ~kind:Bullet_normal ;
    (* Force adds extra firepower. *)
    let fx, fy = force_world_pos s in
    let force_bullets = if p.weapons.has_force_upgrade then 3 else 2 in
    (match p.force with
    | Force_front ->
        (* With force upgrade: 3 spread bullets; otherwise 2 offset. *)
        if force_bullets = 3 then begin
          fire_player_bullet
            s
            ~x:(fx +. 1.0)
            ~y:fy
            ~vx:bullet_speed
            ~vy:0.0
            ~kind:Bullet_normal ;
          fire_player_bullet
            s
            ~x:(fx +. 1.0)
            ~y:(fy -. 3.0)
            ~vx:bullet_speed
            ~vy:0.0
            ~kind:Bullet_normal ;
          fire_player_bullet
            s
            ~x:(fx +. 1.0)
            ~y:(fy +. 3.0)
            ~vx:bullet_speed
            ~vy:0.0
            ~kind:Bullet_normal
        end
        else begin
          fire_player_bullet
            s
            ~x:(fx +. 1.0)
            ~y:(fy -. 2.0)
            ~vx:bullet_speed
            ~vy:0.0
            ~kind:Bullet_normal ;
          fire_player_bullet
            s
            ~x:(fx +. 1.0)
            ~y:(fy +. 2.0)
            ~vx:bullet_speed
            ~vy:0.0
            ~kind:Bullet_normal
        end
    | Force_back ->
        fire_player_bullet
          s
          ~x:(fx -. 1.0)
          ~y:fy
          ~vx:(-.bullet_speed)
          ~vy:0.0
          ~kind:Bullet_normal
    | Force_detached _ ->
        fire_player_bullet
          s
          ~x:(fx +. 1.0)
          ~y:fy
          ~vx:bullet_speed
          ~vy:0.0
          ~kind:Bullet_normal) ;
    (* Missile upgrade: 2 diagonal missiles. *)
    if p.weapons.has_missile then begin
      let mspeed = bullet_speed *. 0.85 in
      let angle = Float.pi /. 5.0 in
      (* 36 degrees *)
      fire_player_bullet
        s
        ~x:(p.x +. 2.0)
        ~y:(p.y -. 1.0)
        ~vx:(mspeed *. cos angle)
        ~vy:(-.mspeed *. sin angle)
        ~kind:Bullet_missile ;
      fire_player_bullet
        s
        ~x:(p.x +. 2.0)
        ~y:(p.y +. 1.0)
        ~vx:(mspeed *. cos angle)
        ~vy:(mspeed *. sin angle)
        ~kind:Bullet_missile
    end
  end

(* Launch speed in world coords = scroll_speed + screen_speed (75 px/s forward). *)
let force_launch_wvx = scroll_speed +. 75.0

(* When recalling, approach the ship at this screen speed. *)
let force_recall_speed = 140.0

(* Deceleration rate when coasting (world vx → scroll_speed = 0 screen drift). *)
let force_coast_decel = 55.0

(* Auto-dock radius: must be < force_dock_offset (8) so the pod doesn't
   immediately re-dock on launch. *)
let force_auto_dock_r = 6.0

let toggle_force s =
  let p = s.player in
  match p.force with
  | Force_front | Force_back ->
      (* Launch: detach and send the Force forward at launch speed. *)
      let fx_screen, fy = force_world_pos s in
      p.force <-
        Force_detached
          {
            fx = fx_screen +. s.world_x;
            fy;
            fvx = force_launch_wvx;
            recalling = false;
            force_fire_t = 0.4;
            recall_t = 0.0;
          }
  | Force_detached fd ->
      (* Toggle recall — pressing d while floating reverses direction. *)
      let was_recalling = fd.recalling in
      fd.recalling <- not fd.recalling ;
      (* On fresh recall activation, set sprint timer. *)
      if not was_recalling then fd.recall_t <- 0.3

(* ---------- enemies ---------- *)

(* Geometry helpers used by both enemy AI and collision resolution. *)
let dist2 ax ay bx by =
  let dx = ax -. bx in
  let dy = ay -. by in
  (dx *. dx) +. (dy *. dy)

(* Tick the floating Force pod: coast or recall, auto-dock on contact.
   Called every frame from tick when mode = Playing. *)
let tick_force s ~dt =
  let p = s.player in
  match p.force with
  | Force_front | Force_back -> ()
  | Force_detached fd ->
      if fd.recall_t > 0.0 then fd.recall_t <- fd.recall_t -. dt ;
      if fd.recalling then begin
        (* Fly straight toward the ship's current world x. *)
        let target_wx = p.x +. s.world_x in
        let dx = target_wx -. fd.fx in
        let dir = if dx > 0.0 then 1.0 else -1.0 in
        (* Sprint boost for the first 0.3s of recall. *)
        let speed_mult = if fd.recall_t > 0.0 then 2.0 else 1.0 in
        fd.fvx <- dir *. ((force_recall_speed *. speed_mult) +. scroll_speed)
      end
      else begin
        (* Coast: decelerate world vx toward scroll_speed (= 0 screen drift). *)
        let diff = fd.fvx -. scroll_speed in
        let change = Float.min (Float.abs diff) (force_coast_decel *. dt) in
        fd.fvx <- fd.fvx -. Float.copy_sign change diff ;
        (* Once nearly stationary relative to world, clamp to prevent slow
           backward drift accumulation. *)
        if Float.abs (fd.fvx -. scroll_speed) < 2.0 then fd.fvx <- scroll_speed
      end ;
      fd.fx <- fd.fx +. (fd.fvx *. dt) ;
      (* Auto-fire: detached Force shoots forward every 0.4s. *)
      fd.force_fire_t <- fd.force_fire_t -. dt ;
      if fd.force_fire_t <= 0.0 then begin
        fd.force_fire_t <- 0.4 ;
        let fx_screen = fd.fx -. s.world_x in
        let bullets = if p.weapons.has_force_upgrade then 3 else 1 in
        for i = 0 to bullets - 1 do
          let spread =
            (float_of_int i -. (float_of_int (bullets - 1) /. 2.0)) *. 3.0
          in
          fire_player_bullet
            s
            ~x:(fx_screen +. 2.0)
            ~y:(fd.fy +. spread)
            ~vx:bullet_speed
            ~vy:0.0
            ~kind:Bullet_normal
        done
      end ;
      (* Auto-dock when Force comes within range of the ship. *)
      let fx_screen = fd.fx -. s.world_x in
      let r2 = force_auto_dock_r *. force_auto_dock_r in
      if dist2 fx_screen fd.fy p.x p.y <= r2 then
        (* Dock to front if Force is at or ahead of ship centre, else back. *)
        p.force <- (if fx_screen >= p.x -. 2.0 then Force_front else Force_back)

let enemy_radius (e : enemy) =
  match e.kind with
  | Grunt -> 3.0
  | Diver -> 3.0
  | Turret -> 4.0
  | Strafer -> 3.0
  | Shielded -> 4.5
  | Mine -> 3.5
  | Splitter -> 3.5
  | Laser_emitter -> 5.0
  | Carrier -> 7.0
  | Boomerang -> 3.5
  | Boss -> 9.0

let burst_explosion s ~x ~y ~kind =
  let n, speed, life, hue =
    match kind with
    | Grunt -> (14, 22.0, 0.7, 8)
    | Diver -> (16, 26.0, 0.7, 9)
    | Turret -> (20, 28.0, 0.9, 10)
    | Strafer -> (16, 32.0, 0.7, 9)
    | Shielded -> (24, 30.0, 1.0, 6)
    | Mine -> (40, 46.0, 1.1, 11)
    | Splitter -> (20, 28.0, 0.8, 8)
    | Laser_emitter -> (28, 34.0, 1.0, 3)
    | Carrier -> (36, 38.0, 1.1, 7)
    | Boomerang -> (18, 28.0, 0.8, 5)
    | Boss -> (60, 40.0, 1.4, 11)
  in
  Arcade_kit.Particles.spawn_burst
    s.particles
    ~x
    ~y
    ~n
    ~speed
    ~life
    ~hue
    ~rng:s.rng

(* Boss phase chooser: 1 = >50% HP, 2 = 25-50% HP, 3 = <25% HP. *)
let boss_phase_for ~hp ~hp_max =
  let pct = float_of_int hp /. float_of_int (max 1 hp_max) in
  if pct > 0.5 then 1 else if pct > 0.25 then 2 else 3

(* Update an existing boss enemy's [boss_phase] and emit a burst on
   transition. Caller passes [hp_max] from [Model.t]. *)
let maybe_advance_boss_phase s (e : enemy) ~hp_max =
  let new_phase = boss_phase_for ~hp:e.hp ~hp_max in
  if new_phase <> e.boss_phase then begin
    e.boss_phase <- new_phase ;
    s.boss_phase <- new_phase ;
    (* Phase-change warning banner. *)
    s.boss_phase_warn_t <- 0.6 ;
    (* Visual punch on phase transition. *)
    Arcade_kit.Particles.spawn_burst
      s.particles
      ~x:e.x
      ~y:e.y
      ~n:36
      ~speed:36.0
      ~life:0.9
      ~hue:(6 + new_phase)
      ~rng:s.rng ;
    Arcade_kit.Screen_fx.shake s.fx ~magnitude:1.5 ~duration:0.3
  end

(* ---------- splitter scatter bullets ---------- *)

let spawn_splitter_bullets s ~x ~y =
  (* 2 scatter bullets going left-down-ish and left-up-ish. *)
  let speed = 48.0 in
  let angles = [|Float.pi *. 0.85; Float.pi *. 1.15|] in
  Array.iter
    (fun a ->
      fire_enemy_bullet s ~x ~y ~vx:(speed *. cos a) ~vy:(speed *. sin a))
    angles

(* ---------- laser emitter ---------- *)

(* Fire a laser: a column of slow-moving wide bullet segments that together
   sweep the full screen height. They're positioned around [cx] in a vertical
   band [ay .. by]. *)
let fire_laser_sweep s ~cx ~sweep_y_start ~sweep_y_end =
  (* Divide height into segments, each is a Bullet_laser entity. *)
  let n_segs = int_of_float ((sweep_y_end -. sweep_y_start) /. 4.0) + 1 in
  for i = 0 to n_segs - 1 do
    let y = sweep_y_start +. (float_of_int i *. 4.0) in
    match alloc_bullet s.enemy_bullets with
    | None -> ()
    | Some b ->
        b.b_alive <- true ;
        b.bx <- cx ;
        b.by <- y ;
        b.bvx <- -30.0 ;
        (* drifts slowly left *)
        b.bvy <- 0.0 ;
        b.b_kind <- Bullet_laser ;
        b.b_life <- 1.0 ;
        (* each segment lives 1 s *)
        b.b_home_t <- 0.0
  done

let advance_enemies s ~dt =
  Array.iter
    (fun (e : enemy) ->
      if e.alive then begin
        e.phase <- e.phase +. dt ;
        e.age <- e.age +. dt ;
        if e.hit_flash > 0.0 then e.hit_flash <- e.hit_flash -. dt ;
        (match e.kind with
        | Grunt ->
            (* Slow drift left, sinusoidal y. *)
            e.x <- e.x -. (38.0 *. dt) ;
            e.y <- e.y0 +. (5.0 *. sin (e.phase *. 2.5))
        | Diver ->
            e.x <- e.x -. (45.0 *. dt) ;
            (* Dive then level. *)
            let dive_t = Float.min 1.5 e.phase in
            e.y <- e.y0 +. (12.0 *. sin (dive_t *. 1.2))
        | Turret ->
            e.x <- e.x -. (22.0 *. dt) ;
            e.fire_t <- e.fire_t -. dt ;
            (* Update facing direction toward player each tick. *)
            let p = s.player in
            let dx_p = p.x -. e.x in
            let dy_p = p.y -. e.y in
            e.face_dir <-
              (if abs_float dx_p >= abs_float dy_p then
                 if dx_p >= 0.0 then 0 else 2
               else if dy_p < 0.0 then 1
               else 3) ;
            if e.fire_t <= 0.0 then begin
              e.fire_t <- 1.4 +. Random.State.float s.rng 0.6 ;
              let dx = p.x -. e.x in
              let dy = p.y -. e.y in
              let len = Float.max 1.0 (sqrt ((dx *. dx) +. (dy *. dy))) in
              let bs = 55.0 in
              fire_enemy_bullet
                s
                ~x:e.x
                ~y:e.y
                ~vx:(bs *. dx /. len)
                ~vy:(bs *. dy /. len)
            end
        | Strafer ->
            (* Fast left drift with strong zigzag. *)
            e.x <- e.x -. (62.0 *. dt) ;
            e.y <- e.y0 +. (16.0 *. sin (e.phase *. 4.0))
        | Shielded ->
            (* Slow steady drift; the threat is its toughness. *)
            e.x <- e.x -. (24.0 *. dt) ;
            e.y <- e.y0 +. (3.5 *. sin (e.phase *. 1.5))
        | Mine ->
            (* Mostly stationary, drifts with world scroll. *)
            e.x <- e.x -. (scroll_speed *. dt) ;
            e.y <- e.y0 +. (1.5 *. sin (e.phase *. 0.6)) ;
            (* If the fuse is lit, count down then explode. *)
            if e.mine_fuse > 0.0 then begin
              e.mine_fuse <- e.mine_fuse -. dt ;
              if e.mine_fuse <= 0.0 then begin
                e.alive <- false ;
                burst_explosion s ~x:e.x ~y:e.y ~kind:Mine ;
                (* Chain-detonation ring: spawn 16 particles in a ring for
                   extra visual punch on chained explosions. *)
                if e.chain_depth > 0 then begin
                  let mx = e.x in
                  let my = e.y in
                  for k = 0 to 15 do
                    let a = Float.of_int k /. 16.0 *. 2.0 *. Float.pi in
                    Arcade_kit.Particles.spawn
                      s.particles
                      ~x:(mx +. (cos a *. 6.0))
                      ~y:(my +. (sin a *. 6.0))
                      ~vx:(cos a *. 45.0)
                      ~vy:(sin a *. 45.0)
                      ~life:0.25
                      ~hue:1
                  done
                end ;
                s.score <- s.score + e.score ;
                (* Chain: light any other mine within ~10 px (depth-capped). *)
                if e.chain_depth < mine_chain_max_depth then
                  Array.iter
                    (fun (other : enemy) ->
                      if
                        other.alive && other.kind = Mine
                        && other.mine_fuse <= 0.0
                      then begin
                        let r = 10.0 in
                        if dist2 e.x e.y other.x other.y <= r *. r then begin
                          other.mine_fuse <- 0.18 ;
                          other.chain_depth <- e.chain_depth + 1
                        end
                      end)
                    s.enemies
              end
            end
        | Splitter ->
            e.x <- e.x -. (44.0 *. dt) ;
            e.y <- e.y0 +. (8.0 *. sin (e.phase *. 3.0))
        | Carrier ->
            (* Slow steady drift left, gentle bob. *)
            e.x <- e.x -. (16.0 *. dt) ;
            e.y <- e.y0 +. (4.0 *. sin (e.phase *. 0.8)) ;
            (* Spawn timer: fires_t counts down; spawns 2 grunts on expiry. *)
            e.fire_t <- e.fire_t -. dt ;
            if e.fire_t <= 0.0 then begin
              e.fire_t <- 3.0 ;
              (* Spawn 2 grunts in a V off the carrier's right side. *)
              let gx = e.x +. 4.0 in
              spawn_enemy s ~kind:Grunt ~x:gx ~y:(e.y -. 6.0) ~hp:1 ~score:100 ;
              spawn_enemy s ~kind:Grunt ~x:gx ~y:(e.y +. 6.0) ~hp:1 ~score:100
            end
        | Laser_emitter ->
            (* Stationary in y, slow left drift. *)
            e.x <- e.x -. (18.0 *. dt) ;
            e.fire_t <- e.fire_t -. dt ;
            if e.fire_t <= 0.0 then begin
              (* Charge phase. *)
              e.laser_charge <- e.laser_charge +. dt ;
              if e.laser_charge >= 1.5 then begin
                e.laser_charge <- 0.0 ;
                e.laser_fire_t <- 0.5 ;
                e.fire_t <- 2.5 +. Random.State.float s.rng 1.0
              end
            end ;
            (* Firing phase: emit laser segments sweeping the screen height. *)
            if e.laser_fire_t > 0.0 then begin
              e.laser_fire_t <- e.laser_fire_t -. dt ;
              (* Emit a fresh row every ~0.05 s using phase as timer trick. *)
              let fire_period = 0.06 in
              let seg_phase = mod_float e.phase fire_period in
              if seg_phase < dt then
                fire_laser_sweep
                  s
                  ~cx:e.x
                  ~sweep_y_start:0.0
                  ~sweep_y_end:(float_of_int s.arena_h)
            end
        | Boomerang ->
            (* Sweeping arc motion: cosine Y with period 4s, amplitude 80px.
               Drifts left at medium speed. Fires 2-bullet spread every 2.5s. *)
            e.x <- e.x -. (36.0 *. dt) ;
            let period = 4.0 in
            let amplitude = 36.0 in
            e.y <-
              e.y0 +. (amplitude *. cos (e.phase *. (2.0 *. Float.pi /. period))) ;
            e.fire_t <- e.fire_t -. dt ;
            if e.fire_t <= 0.0 then begin
              e.fire_t <- 2.5 ;
              let p = s.player in
              let dx = p.x -. e.x in
              let dy = p.y -. e.y in
              let len = Float.max 1.0 (sqrt ((dx *. dx) +. (dy *. dy))) in
              let base_angle = atan2 dy dx in
              let spread = 0.35 in
              (* 20° ≈ 0.35 rad spread *)
              let bs = 80.0 in
              [|base_angle -. spread; base_angle +. spread|]
              |> Array.iter (fun a ->
                  fire_enemy_bullet
                    s
                    ~x:e.x
                    ~y:e.y
                    ~vx:(bs *. cos a)
                    ~vy:(bs *. sin a)) ;
              ignore len
            end
        | Boss ->
            (* Multi-phase boss: phase 1 radial spread, phase 2 aimed
               homing, phase 3 desperate burst. *)
            maybe_advance_boss_phase s e ~hp_max:s.boss_hp_max ;
            let target_x = float_of_int s.arena_w -. 22.0 in
            if e.x > target_x then e.x <- e.x -. (15.0 *. dt) ;
            (* Each phase has a different bob frequency / amplitude. *)
            let amp, freq =
              match e.boss_phase with
              | 2 -> (14.0, 1.2)
              | 3 -> (18.0, 1.7)
              | _ -> (10.0, 0.9)
            in
            e.y <- e.y0 +. (amp *. sin (e.phase *. freq)) ;
            e.fire_t <- e.fire_t -. dt ;
            if e.fire_t <= 0.0 then begin
              match e.boss_phase with
              | 1 ->
                  (* Radial spread of 8 bullets. *)
                  e.fire_t <- 1.1 ;
                  let bs = 50.0 in
                  let n = 8 in
                  for i = 0 to n - 1 do
                    let a =
                      (Float.pi *. 2.0 *. float_of_int i /. float_of_int n)
                      +. (e.phase *. 0.4)
                    in
                    fire_enemy_bullet
                      s
                      ~x:e.x
                      ~y:e.y
                      ~vx:(bs *. cos a)
                      ~vy:(bs *. sin a)
                  done
              | 2 -> (
                  (* Aimed pair + a homing bullet. *)
                  e.fire_t <- 0.7 ;
                  let p = s.player in
                  let dx = p.x -. e.x in
                  let dy = p.y -. e.y in
                  let len = Float.max 1.0 (sqrt ((dx *. dx) +. (dy *. dy))) in
                  let bs = 60.0 in
                  fire_enemy_bullet
                    s
                    ~x:e.x
                    ~y:(e.y -. 2.0)
                    ~vx:(bs *. dx /. len)
                    ~vy:(bs *. dy /. len) ;
                  fire_enemy_bullet
                    s
                    ~x:e.x
                    ~y:(e.y +. 2.0)
                    ~vx:(bs *. dx /. len)
                    ~vy:(bs *. dy /. len) ;
                  match alloc_bullet s.enemy_bullets with
                  | None -> ()
                  | Some b ->
                      b.b_alive <- true ;
                      b.bx <- e.x ;
                      b.by <- e.y ;
                      let s_h = 35.0 in
                      b.bvx <- s_h *. dx /. len ;
                      b.bvy <- s_h *. dy /. len ;
                      b.b_kind <- Bullet_homing ;
                      b.b_life <- 3.0 ;
                      b.b_home_t <- 0.0)
              | _ ->
                  (* Phase 3: desperate burst — wide spread plus aimed. *)
                  e.fire_t <- 0.45 ;
                  let bs = 70.0 in
                  let p = s.player in
                  let dxp = p.x -. e.x in
                  let dyp = p.y -. e.y in
                  let len =
                    Float.max 1.0 (sqrt ((dxp *. dxp) +. (dyp *. dyp)))
                  in
                  let base = atan2 dyp dxp in
                  let spread = 0.45 in
                  for i = -2 to 2 do
                    let a = base +. (spread *. float_of_int i) in
                    fire_enemy_bullet
                      s
                      ~x:e.x
                      ~y:e.y
                      ~vx:(bs *. cos a)
                      ~vy:(bs *. sin a)
                  done ;
                  ignore len
            end) ;
        if e.x < -10.0 then e.alive <- false
      end)
    s.enemies

(* ---------- bullets ---------- *)

let advance_bullets arr ~dt ~arena_w ~arena_h =
  let aw = float_of_int arena_w in
  let ah = float_of_int arena_h in
  Array.iter
    (fun (b : bullet) ->
      if b.b_alive then begin
        b.b_life <- b.b_life -. dt ;
        b.bx <- b.bx +. (b.bvx *. dt) ;
        b.by <- b.by +. (b.bvy *. dt) ;
        if b.bx < -2.0 || b.bx > aw +. 2.0 || b.by < -2.0 || b.by > ah +. 2.0
        then b.b_alive <- false ;
        if
          (b.b_kind = Bullet_homing || b.b_kind = Bullet_laser)
          && b.b_life <= 0.0
        then b.b_alive <- false
      end)
    arr

(* Steer a homing bullet toward [(tx, ty)] each frame. Cheap arc-bend. *)
let steer_homing_bullets arr ~dt ~tx ~ty =
  Array.iter
    (fun (b : bullet) ->
      if b.b_alive && b.b_kind = Bullet_homing then begin
        let dx = tx -. b.bx in
        let dy = ty -. b.by in
        let len = Float.max 1.0 (sqrt ((dx *. dx) +. (dy *. dy))) in
        let speed =
          Float.max 1.0 (sqrt ((b.bvx *. b.bvx) +. (b.bvy *. b.bvy)))
        in
        let target_vx = speed *. dx /. len in
        let target_vy = speed *. dy /. len in
        let k = Float.min 1.0 (dt *. 1.4) in
        b.bvx <- b.bvx +. (k *. (target_vx -. b.bvx)) ;
        b.bvy <- b.bvy +. (k *. (target_vy -. b.bvy)) ;
        (* Re-normalise to keep speed constant. *)
        let cur = Float.max 1.0 (sqrt ((b.bvx *. b.bvx) +. (b.bvy *. b.bvy))) in
        b.bvx <- b.bvx *. speed /. cur ;
        b.bvy <- b.bvy *. speed /. cur
      end)
    arr

(* ---------- collisions ---------- *)

(* Score popup helpers. *)

let alloc_popup s =
  let n = Array.length s.popups in
  let rec find i =
    if i >= n then None
    else if not s.popups.(i).sp_alive then Some s.popups.(i)
    else find (i + 1)
  in
  find 0

let spawn_score_popup s ~x ~y ~text ~hue =
  match alloc_popup s with
  | None -> ()
  | Some p ->
      p.sp_alive <- true ;
      p.sp_x <- x ;
      p.sp_y <- y ;
      p.sp_vy <- -10.0 ;
      p.sp_life <- 1.1 ;
      p.sp_life0 <- 1.1 ;
      p.sp_text <- text ;
      p.sp_hue <- hue

let advance_popups s ~dt =
  Array.iter
    (fun (p : score_popup) ->
      if p.sp_alive then begin
        p.sp_y <- p.sp_y +. (p.sp_vy *. dt) ;
        p.sp_life <- p.sp_life -. dt ;
        if p.sp_life <= 0.0 then p.sp_alive <- false
      end)
    s.popups

(* Apply [dmg] points of damage to an enemy. Returns [true] if the enemy
   was killed by this hit. Handles shields and boss death cinematics. *)
let damage_enemy s (e : enemy) ~dmg =
  e.hit_flash <- 0.16 ;
  (* Shielded enemies absorb shield first. *)
  let dmg_remaining =
    if e.shield > 0 then begin
      let absorbed = min e.shield dmg in
      e.shield <- e.shield - absorbed ;
      Arcade_kit.Particles.spawn_burst
        s.particles
        ~x:e.x
        ~y:e.y
        ~n:6
        ~speed:14.0
        ~life:0.3
        ~hue:6
        ~rng:s.rng ;
      dmg - absorbed
    end
    else dmg
  in
  if dmg_remaining > 0 then begin
    e.hp <- e.hp - dmg_remaining ;
    if e.kind = Boss then
      Arcade_kit.Screen_fx.shake s.fx ~magnitude:1.0 ~duration:0.18 ;
    if e.hp <= 0 then begin
      e.alive <- false ;
      (* Combo multiplier: advance counter on kill, reset window. *)
      let apply_combo = e.kind <> Boss in
      if apply_combo then begin
        s.combo <- min 5 (s.combo + 1) ;
        s.combo_t <- 1.5 ;
        if s.combo > s.combo_max then s.combo_max <- s.combo
      end ;
      let effective_score = e.score * s.combo in
      s.score <- s.score + effective_score ;
      (* Big-kill announcement for kills worth ≥ 500 points. *)
      if effective_score >= 500 then begin
        s.big_kill_t <- 1.5 ;
        s.big_kill_text <- Printf.sprintf "BIG KILL! +%d" effective_score
      end ;
      spawn_score_popup
        s
        ~x:e.x
        ~y:e.y
        ~text:(Printf.sprintf "+%d" effective_score)
        ~hue:9 ;
      (* Carrier death: 3 spread bursts simulating the ship breaking apart. *)
      if e.kind = Carrier then begin
        for i = -1 to 1 do
          let ox = float_of_int i *. 20.0 in
          Arcade_kit.Particles.spawn_burst
            s.particles
            ~x:(e.x +. ox)
            ~y:e.y
            ~n:12
            ~speed:28.0
            ~life:0.9
            ~hue:7
            ~rng:s.rng
        done
      end
      else burst_explosion s ~x:e.x ~y:e.y ~kind:e.kind ;
      (* Splitter: spawn 2 scatter bullets. *)
      if e.kind = Splitter then spawn_splitter_bullets s ~x:e.x ~y:e.y ;
      (* Random power-up drops: ~20% for regular enemies. *)
      if e.kind <> Boss && e.kind <> Mine then begin
        let roll = Random.State.int s.rng 100 in
        if roll < 20 then begin
          let pickup_kinds =
            [|
              Power_up_speed;
              Power_up_missile;
              Power_up_shield;
              Power_up_force_upgrade;
              Power_up_speed_burst;
            |]
          in
          let k =
            pickup_kinds.(Random.State.int s.rng (Array.length pickup_kinds))
          in
          spawn_pickup s ~kind:k ~x:e.x ~y:e.y
        end
      end ;
      if e.kind = Boss then begin
        s.boss_active <- false ;
        Arcade_kit.Screen_fx.flash s.fx ~intensity:1.0 ~duration:0.9 ;
        Arcade_kit.Screen_fx.shake s.fx ~magnitude:3.0 ~duration:0.7 ;
        Arcade_kit.Particles.spawn_burst
          s.particles
          ~x:e.x
          ~y:e.y
          ~n:120
          ~speed:60.0
          ~life:1.6
          ~hue:11
          ~rng:s.rng ;
        (* Transition to level-clear cinematic animation. *)
        let li = s.level - 1 in
        if li >= 0 && li < Array.length s.level_scores then begin
          let lvl_score = s.score - s.score_at_level_start in
          s.level_scores.(li) <- lvl_score ;
          s.best_level.(li) <- max s.best_level.(li) lvl_score
        end ;
        s.mode <- Level_clear_anim {anim_t = 0.0; level = s.level} ;
        s.mode_t <- 0.0 ;
        s.boss_phase <- 0
      end ;
      true
    end
    else false
  end
  else false

(* Mines that get hit don't take HP damage — they detonate after a fuse. *)
let trigger_mine (e : enemy) = if e.mine_fuse <= 0.0 then e.mine_fuse <- 0.18

(* Force pod radius — with upgrade, it's larger. *)
let force_radius (s : t) =
  if s.player.weapons.has_force_upgrade then 5.0 else 3.0

let resolve_player_bullets s =
  Array.iter
    (fun (b : bullet) ->
      if b.b_alive then
        Array.iter
          (fun (e : enemy) ->
            if e.alive && b.b_alive then begin
              let r = enemy_radius e in
              if dist2 b.bx b.by e.x e.y <= r *. r then begin
                let beam = b.b_kind = Bullet_beam in
                (* Beams pierce through grunts/divers; only consume the
                   bullet on truly tough targets. *)
                if not beam then b.b_alive <- false ;
                let dmg = if beam then 2 else 1 in
                if e.kind = Mine then trigger_mine e
                else ignore (damage_enemy s e ~dmg)
              end
            end)
          s.enemies)
    s.player_bullets

(* Force pod also blocks enemy bullets, when detached. *)

let resolve_enemy_bullets s =
  let p = s.player in
  let fx, fy = force_world_pos s in
  let fr = force_radius s in
  Array.iter
    (fun (b : bullet) ->
      if b.b_alive then begin
        (* Force absorbs bullets when detached. *)
        (match p.force with
        | Force_detached _ ->
            if dist2 b.bx b.by fx fy <= fr *. fr then begin
              b.b_alive <- false ;
              Arcade_kit.Particles.spawn_burst
                s.particles
                ~x:b.bx
                ~y:b.by
                ~n:6
                ~speed:14.0
                ~life:0.4
                ~hue:6
                ~rng:s.rng
            end
        | _ -> ()) ;
        if b.b_alive && p.alive && p.invuln <= 0.0 then begin
          (* Laser bullets have a larger effective hitbox (they're wide). *)
          let hit_r2 = if b.b_kind = Bullet_laser then 16.0 else 9.0 in
          if dist2 b.bx b.by p.x p.y <= hit_r2 then begin
            b.b_alive <- false ;
            (* Shield absorbs one hit; two hits before depletion. *)
            let w = p.weapons in
            if w.has_shield && w.shield_active then begin
              w.shield_hits <- w.shield_hits - 1 ;
              if w.shield_hits <= 0 then begin
                w.shield_active <- false ;
                w.has_shield <- false
              end ;
              w.flash_t <- 0.4 ;
              Arcade_kit.Particles.spawn_burst
                s.particles
                ~x:p.x
                ~y:p.y
                ~n:12
                ~speed:20.0
                ~life:0.5
                ~hue:10
                ~rng:s.rng
            end
            else p.alive <- false
          end
        end
      end)
    s.enemy_bullets

let resolve_player_enemy_collide s =
  let p = s.player in
  if p.alive && p.invuln <= 0.0 then
    Array.iter
      (fun (e : enemy) ->
        if e.alive && p.alive then
          let r = enemy_radius e +. 2.5 in
          if dist2 p.x p.y e.x e.y <= r *. r then begin
            let w = p.weapons in
            if w.has_shield && w.shield_active then begin
              w.shield_hits <- w.shield_hits - 1 ;
              if w.shield_hits <= 0 then begin
                w.shield_active <- false ;
                w.has_shield <- false
              end ;
              w.flash_t <- 0.4 ;
              p.invuln <- 0.8 ;
              Arcade_kit.Particles.spawn_burst
                s.particles
                ~x:p.x
                ~y:p.y
                ~n:12
                ~speed:20.0
                ~life:0.5
                ~hue:10
                ~rng:s.rng
            end
            else begin
              p.alive <- false ;
              (* The enemy takes damage too on contact unless it's the boss. *)
              if e.kind <> Boss then begin
                e.alive <- false ;
                burst_explosion s ~x:e.x ~y:e.y ~kind:e.kind
              end
            end
          end)
      s.enemies

(* Apply a power-up to the player. Speed caps at 3 stacks. Shield upgrades
   restore shield_active if already owned. *)
let apply_pickup s (kind : pickup) =
  let w = s.player.weapons in
  (match kind with
  | Power_up_speed ->
      if w.speed_level < 3 then w.speed_level <- w.speed_level + 1 ;
      s.score <- s.score + 100
  | Power_up_force_repair ->
      s.player.force <- Force_front ;
      s.score <- s.score + 250
  | Power_up_missile ->
      w.has_missile <- true ;
      s.score <- s.score + 200
  | Power_up_force_upgrade ->
      w.has_force_upgrade <- true ;
      s.score <- s.score + 300
  | Power_up_shield ->
      w.has_shield <- true ;
      w.shield_active <- true ;
      w.shield_hits <- 2 ;
      s.score <- s.score + 200
  | Power_up_speed_burst ->
      s.player.speed_boost_t <- 4.0 ;
      s.score <- s.score + 150) ;
  spawn_score_popup
    s
    ~x:s.player.x
    ~y:(s.player.y -. 6.0)
    ~text:
      (match kind with
      | Power_up_speed -> "+SPD"
      | Power_up_force_repair -> "+FRC"
      | Power_up_missile -> "+MSL"
      | Power_up_force_upgrade -> "+FUP"
      | Power_up_shield -> "+SHD"
      | Power_up_speed_burst -> "+BST")
    ~hue:10 ;
  (* Brief white-flash visual confirmation on the ship sprite. *)
  s.player.weapons.pickup_flash_t <- 0.2 ;
  Arcade_kit.Particles.spawn_burst
    s.particles
    ~x:s.player.x
    ~y:s.player.y
    ~n:18
    ~speed:18.0
    ~life:0.8
    ~hue:10
    ~rng:s.rng

let resolve_pickups s =
  let p = s.player in
  Array.iter
    (fun (pe : pickup_entity) ->
      if pe.p_alive then begin
        if dist2 p.x p.y pe.px pe.py <= 16.0 then begin
          pe.p_alive <- false ;
          apply_pickup s pe.p_kind
        end
      end)
    s.pickups

(* ---------- spawn pump ---------- *)

let pump_events s =
  let rec loop = function
    | [] -> []
    | (e : event) :: tl when s.world_x >= e.trigger_x ->
        let world_right = float_of_int s.arena_w +. 4.0 in
        (match e.spawn with
        | Spawn_enemy {kind; y; hp; score} ->
            spawn_enemy s ~kind ~x:world_right ~y ~hp ~score
        | Spawn_pickup (kind, y) -> spawn_pickup s ~kind ~x:world_right ~y
        | Spawn_boss {hp; score} ->
            let y = float_of_int s.arena_h /. 2.0 in
            spawn_enemy s ~kind:Boss ~x:world_right ~y ~hp ~score ;
            s.boss_active <- true ;
            s.boss_hp_max <- hp
        | Spawn_hazard {world_x = hx; y; height} ->
            (* world_x is the absolute level world coordinate for the spike. *)
            spawn_hazard s ~world_x:hx ~y ~height) ;
        loop tl
    | l -> l
  in
  s.events <- loop s.events

(* ---------- main tick ---------- *)

let tick s ~input ~dt =
  (* Apply time-scale to gameplay dt; HUD/mode timer uses real dt so
     overlays still pulse at normal speed. *)
  let game_dt = dt *. s.time_scale in
  s.mode_t <- s.mode_t +. dt ;
  match s.mode with
  | Title -> ()
  | Level_select -> ()
  | Game_over -> Arcade_kit.Screen_fx.tick s.fx ~dt
  | Level_clear -> Arcade_kit.Screen_fx.tick s.fx ~dt
  | Level_clear_anim anim ->
      Arcade_kit.Screen_fx.tick s.fx ~dt ;
      Arcade_kit.Particles.tick s.particles ~dt:game_dt ~ax:0.0 ~ay:0.0 ;
      anim.anim_t <- anim.anim_t +. dt ;
      if anim.anim_t >= 2.0 then begin
        s.mode <- Level_clear ;
        s.mode_t <- 0.0
      end
  | Playing ->
      if input.toggle_force then toggle_force s ;
      tick_force s ~dt:game_dt ;
      move_player s ~input ~dt:game_dt ;
      fire_logic s ~input ~dt:game_dt ;
      s.world_x <- s.world_x +. (scroll_speed *. game_dt) ;
      pump_events s ;
      advance_enemies s ~dt:game_dt ;
      (* Homing bullets steer toward the player each frame. *)
      steer_homing_bullets
        s.enemy_bullets
        ~dt:game_dt
        ~tx:s.player.x
        ~ty:s.player.y ;
      advance_bullets
        s.player_bullets
        ~dt:game_dt
        ~arena_w:s.arena_w
        ~arena_h:s.arena_h ;
      advance_bullets
        s.enemy_bullets
        ~dt:game_dt
        ~arena_w:s.arena_w
        ~arena_h:s.arena_h ;
      (* Pickups bob and drift left at scroll speed. *)
      Array.iter
        (fun (pe : pickup_entity) ->
          if pe.p_alive then begin
            pe.px <- pe.px -. (scroll_speed *. game_dt) ;
            pe.p_bob <- pe.p_bob +. (game_dt *. 3.0) ;
            pe.py <- pe.py +. (sin pe.p_bob *. 0.8 *. game_dt) ;
            if pe.px < -4.0 then pe.p_alive <- false
          end)
        s.pickups ;
      (* Hazards: advance (scroll with world) and test player collision. *)
      let p = s.player in
      Array.iter
        (fun (h : hazard) ->
          if h.h_alive then begin
            (* Despawn when scrolled off left edge. *)
            let hx_screen = h.h_world_x -. s.world_x in
            if hx_screen < -8.0 then h.h_alive <- false
            else if p.alive && p.invuln <= 0.0 then begin
              (* Check overlap: player within 3px horizontally and within
                 the spike height vertically. *)
              let dx = abs_float (p.x -. hx_screen) in
              let half_h = float_of_int h.h_height /. 2.0 in
              let dy = abs_float (p.y -. h.h_y) in
              if dx <= 3.0 && dy <= half_h then begin
                (* Hit: lose a life / invuln, same as enemy collision. *)
                let w = p.weapons in
                if w.has_shield && w.shield_active then begin
                  w.shield_hits <- w.shield_hits - 1 ;
                  if w.shield_hits <= 0 then begin
                    w.shield_active <- false ;
                    w.has_shield <- false
                  end ;
                  w.flash_t <- 0.4 ;
                  p.invuln <- 0.8 ;
                  Arcade_kit.Particles.spawn_burst
                    s.particles
                    ~x:p.x
                    ~y:p.y
                    ~n:12
                    ~speed:20.0
                    ~life:0.5
                    ~hue:10
                    ~rng:s.rng
                end
                else begin
                  p.alive <- false ;
                  Arcade_kit.Particles.spawn_burst
                    s.particles
                    ~x:p.x
                    ~y:p.y
                    ~n:20
                    ~speed:28.0
                    ~life:0.7
                    ~hue:9
                    ~rng:s.rng
                end
              end
            end
          end)
        s.hazards ;
      resolve_player_bullets s ;
      resolve_enemy_bullets s ;
      resolve_player_enemy_collide s ;
      resolve_pickups s ;
      advance_popups s ~dt:game_dt ;
      (* Combo window: decay toward 1× when no kill happens within 1.5s. *)
      if s.combo_t > 0.0 then begin
        s.combo_t <- s.combo_t -. game_dt ;
        if s.combo_t <= 0.0 then begin
          s.combo <- 1 ;
          s.combo_t <- 0.0
        end
      end ;
      (* Animated score: exponential smoothing toward real score at rate 8/s. *)
      let target = float_of_int s.score in
      let k = Float.min 1.0 (game_dt *. 8.0) in
      s.display_score <- s.display_score +. (k *. (target -. s.display_score)) ;
      (* Big-kill announcement countdown. *)
      if s.big_kill_t > 0.0 then s.big_kill_t <- s.big_kill_t -. game_dt ;
      (* Boss phase-change warning countdown. *)
      if s.boss_phase_warn_t > 0.0 then
        s.boss_phase_warn_t <- s.boss_phase_warn_t -. game_dt ;
      (* Milestone popup countdown. *)
      if s.milestone_t > 0.0 then s.milestone_t <- s.milestone_t -. game_dt ;
      (* Score milestones: check once-only thresholds 5000/10000/20000/50000. *)
      let milestones = [|5000; 10000; 20000; 50000|] in
      let nm = Array.length milestones in
      if s.next_milestone < nm && s.score >= milestones.(s.next_milestone) then begin
        s.milestone_text <- Printf.sprintf "%d!" milestones.(s.next_milestone) ;
        s.milestone_t <- 1.2 ;
        s.next_milestone <- s.next_milestone + 1
      end ;
      Arcade_kit.Particles.tick s.particles ~dt:game_dt ~ax:0.0 ~ay:0.0 ;
      Arcade_kit.Screen_fx.tick s.fx ~dt ;
      if not s.player.alive then begin
        s.lives <- s.lives - 1 ;
        Arcade_kit.Screen_fx.shake s.fx ~magnitude:2.0 ~duration:0.5 ;
        burst_explosion s ~x:s.player.x ~y:s.player.y ~kind:Boss ;
        if s.lives <= 0 then begin
          s.best <- Arcade_kit.Score_store.record ~demo:"miaou_force" s.score ;
          s.mode <- Game_over ;
          s.mode_t <- 0.0
        end
        else begin
          (* Respawn: brief invulnerability, recall force. *)
          s.player.alive <- true ;
          s.player.x <- 8.0 ;
          s.player.y <- float_of_int s.arena_h /. 2.0 ;
          s.player.invuln <- 1.5 ;
          s.player.force <- Force_front ;
          (* Shield is lost on death. *)
          s.player.weapons.shield_active <- false ;
          (* Respawn starburst: 16 cyan particles in a ring. *)
          Arcade_kit.Particles.spawn_burst
            s.particles
            ~x:s.player.x
            ~y:s.player.y
            ~n:16
            ~speed:30.0
            ~life:0.6
            ~hue:6
            ~rng:s.rng
        end
      end

(* ---------- weapon tier helper ---------- *)

(** Return the speed-upgrade tier for the ship (0–3). Used by the view to
    render a tier bar in the HUD. *)
let weapon_level (s : t) = s.player.weapons.speed_level
