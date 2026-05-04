(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(** Hand-authored spawn tables for all three levels.

    World units are pixels of the framebuffer. With [scroll_speed = 26.0]
    px/s, a level that triggers around world_x = 1500 plays out around the
    one-minute mark. Earlier triggers are timed to arrive at a steady
    cadence with breathing-room gaps. *)

(* The y axis used here assumes the standard arena height (~80 px). The
   model clamps motion to its own arena, so spawn ys outside that band
   simply spawn off-screen and get despawned. *)

let mk_event trigger_x spawn = {Model.trigger_x; spawn}

(* ========================================================================= *)
(*  Level 1 — "Vanguard Run"  (rocky brown/grey terrain, orange enemies)     *)
(* ========================================================================= *)

(* Wave macro: a horizontal V-formation of grunts. *)
let v_wave ~at_x ~y =
  [
    mk_event
      at_x
      (Model.Spawn_enemy {kind = Model.Grunt; y; hp = 1; score = 100});
    mk_event
      (at_x +. 18.)
      (Model.Spawn_enemy {kind = Model.Grunt; y = y -. 6.; hp = 1; score = 100});
    mk_event
      (at_x +. 18.)
      (Model.Spawn_enemy {kind = Model.Grunt; y = y +. 6.; hp = 1; score = 100});
    mk_event
      (at_x +. 36.)
      (Model.Spawn_enemy {kind = Model.Grunt; y = y -. 12.; hp = 1; score = 100});
    mk_event
      (at_x +. 36.)
      (Model.Spawn_enemy {kind = Model.Grunt; y = y +. 12.; hp = 1; score = 100});
  ]

(* Wave macro: a column of divers from the top. *)
let dive_column ~at_x =
  [
    mk_event
      at_x
      (Model.Spawn_enemy {kind = Model.Diver; y = 12.; hp = 1; score = 150});
    mk_event
      (at_x +. 12.)
      (Model.Spawn_enemy {kind = Model.Diver; y = 12.; hp = 1; score = 150});
    mk_event
      (at_x +. 24.)
      (Model.Spawn_enemy {kind = Model.Diver; y = 12.; hp = 1; score = 150});
  ]

let turret_pair ~at_x =
  [
    mk_event
      at_x
      (Model.Spawn_enemy {kind = Model.Turret; y = 18.; hp = 2; score = 250});
    mk_event
      (at_x +. 4.)
      (Model.Spawn_enemy {kind = Model.Turret; y = 60.; hp = 2; score = 250});
  ]

let strafer_pair ~at_x ~y =
  [
    mk_event
      at_x
      (Model.Spawn_enemy {kind = Model.Strafer; y; hp = 1; score = 200});
    mk_event
      (at_x +. 8.)
      (Model.Spawn_enemy
         {kind = Model.Strafer; y = y +. 14.; hp = 1; score = 200});
  ]

let mine_field ~at_x =
  [
    mk_event
      at_x
      (Model.Spawn_enemy {kind = Model.Mine; y = 22.; hp = 1; score = 300});
    mk_event
      (at_x +. 6.)
      (Model.Spawn_enemy {kind = Model.Mine; y = 32.; hp = 1; score = 300});
    mk_event
      (at_x +. 12.)
      (Model.Spawn_enemy {kind = Model.Mine; y = 42.; hp = 1; score = 300});
    mk_event
      (at_x +. 18.)
      (Model.Spawn_enemy {kind = Model.Mine; y = 52.; hp = 1; score = 300});
    mk_event
      (at_x +. 24.)
      (Model.Spawn_enemy {kind = Model.Mine; y = 62.; hp = 1; score = 300});
  ]

let shielded ~at_x ~y =
  mk_event
    at_x
    (Model.Spawn_enemy {kind = Model.Shielded; y; hp = 4; score = 500})

let carrier ~at_x ~y =
  mk_event
    at_x
    (Model.Spawn_enemy {kind = Model.Carrier; y; hp = 8; score = 800})

(* Spike hazard column at a given world-x trigger. The spike itself sits at
   the given world_x so it arrives on screen a moment after the trigger fires. *)
let spike ~at_x ~y ~height =
  mk_event at_x (Model.Spawn_hazard {world_x = at_x +. 80.; y; height})

let boomerang ~at_x ~y =
  mk_event
    at_x
    (Model.Spawn_enemy {kind = Model.Boomerang; y; hp = 2; score = 350})

let boomerang_pair ~at_x =
  [boomerang ~at_x ~y:28.; boomerang ~at_x:(at_x +. 20.) ~y:52.]

(* 3 Shielded enemies in a horizontal line — end-of-level fortress. *)
let shielded_line ~at_x =
  [
    mk_event
      at_x
      (Model.Spawn_enemy {kind = Model.Shielded; y = 28.; hp = 4; score = 500});
    mk_event
      at_x
      (Model.Spawn_enemy {kind = Model.Shielded; y = 40.; hp = 4; score = 500});
    mk_event
      at_x
      (Model.Spawn_enemy {kind = Model.Shielded; y = 52.; hp = 4; score = 500});
  ]

(* Speed-burst power-up pickup event. *)
let speed_burst ~at_x ~y =
  mk_event at_x (Model.Spawn_pickup (Model.Power_up_speed_burst, y))

(* Omega formation: 6 Grunts in a hexagon pattern, then a Missile_fighter
   (represented as a Turret with extra HP) at the centre 0.3s later. *)
let omega_formation ~at_x ~y =
  (* Hex angles: 6 points at 60° increments, radius 10px. *)
  let r = 10.0 in
  let hex_offsets =
    Array.init 6 (fun i ->
        let a = Float.pi /. 3.0 *. float_of_int i in
        (r *. cos a, r *. sin a))
  in
  (* Each grunt spawns 10px after the previous so they arrive sequentially. *)
  Array.to_list
    (Array.mapi
       (fun i (ox, oy) ->
         mk_event
           (at_x +. (float_of_int i *. 10.0))
           (Model.Spawn_enemy
              {kind = Model.Grunt; y = y +. oy +. ox; hp = 1; score = 100}))
       hex_offsets)
  @ [
      (* Missile fighter at centre: Turret with high fire-rate representing
         a dedicated missile-launching foe. *)
      mk_event
        (at_x +. 50.0 +. (0.3 *. 26.0))
        (Model.Spawn_enemy {kind = Model.Turret; y; hp = 3; score = 400});
    ]

let level1 : Model.event list =
  List.sort (fun a b -> compare a.Model.trigger_x b.Model.trigger_x)
  @@ List.concat
       [
         v_wave ~at_x:60. ~y:40.;
         v_wave ~at_x:160. ~y:30.;
         [mk_event 250. (Model.Spawn_pickup (Model.Power_up_speed, 50.))];
         [speed_burst ~at_x:500. ~y:40.];
         v_wave ~at_x:300. ~y:50.;
         dive_column ~at_x:380.;
         strafer_pair ~at_x:440. ~y:32.;
         v_wave ~at_x:520. ~y:35.;
         turret_pair ~at_x:580.;
         [shielded ~at_x:660. ~y:35.];
         [mk_event 700. (Model.Spawn_pickup (Model.Power_up_missile, 40.))];
         dive_column ~at_x:760.;
         mine_field ~at_x:820.;
         (* Extra missile power-up in the mid-section for players who missed the first. *)
         [mk_event 800. (Model.Spawn_pickup (Model.Power_up_missile, 38.))];
         (* Spike hazards in the mid-section — 3 columns to dodge. *)
         [spike ~at_x:870. ~y:40. ~height:16];
         [spike ~at_x:900. ~y:30. ~height:12];
         [spike ~at_x:930. ~y:52. ~height:14];
         v_wave ~at_x:920. ~y:55.;
         strafer_pair ~at_x:980. ~y:48.;
         v_wave ~at_x:1040. ~y:25.;
         turret_pair ~at_x:1100.;
         [shielded ~at_x:1180. ~y:40.; shielded ~at_x:1190. ~y:55.];
         v_wave ~at_x:1260. ~y:40.;
         dive_column ~at_x:1320.;
         mine_field ~at_x:1380.;
         (* Fortress group: 3 Shielded in a line just before the boss. *)
         shielded_line ~at_x:1400.;
         [mk_event 1460. (Model.Spawn_pickup (Model.Power_up_shield, 50.))];
         [mk_event 1600. (Model.Spawn_boss {hp = 30; score = 5000})];
       ]

(* ========================================================================= *)
(*  Level 2 — "Asteroid Belt"  (dark blue/teal palette, splitters, dual boss) *)
(* ========================================================================= *)

(* Splitter cluster — enemies that split into 2 bullets when killed. *)
let splitter_cluster ~at_x ~y =
  [
    mk_event
      at_x
      (Model.Spawn_enemy {kind = Model.Splitter; y; hp = 2; score = 200});
    mk_event
      (at_x +. 10.)
      (Model.Spawn_enemy
         {kind = Model.Splitter; y = y -. 8.; hp = 2; score = 200});
    mk_event
      (at_x +. 10.)
      (Model.Spawn_enemy
         {kind = Model.Splitter; y = y +. 8.; hp = 2; score = 200});
  ]

(* Dense grunt wave — tight 3-row formation. *)
let dense_wave ~at_x ~y =
  [
    mk_event
      at_x
      (Model.Spawn_enemy {kind = Model.Grunt; y; hp = 1; score = 100});
    mk_event
      (at_x +. 6.)
      (Model.Spawn_enemy {kind = Model.Grunt; y = y -. 8.; hp = 1; score = 100});
    mk_event
      (at_x +. 6.)
      (Model.Spawn_enemy {kind = Model.Grunt; y = y +. 8.; hp = 1; score = 100});
    mk_event
      (at_x +. 12.)
      (Model.Spawn_enemy {kind = Model.Grunt; y; hp = 1; score = 100});
    mk_event
      (at_x +. 18.)
      (Model.Spawn_enemy {kind = Model.Grunt; y = y -. 8.; hp = 1; score = 100});
    mk_event
      (at_x +. 18.)
      (Model.Spawn_enemy {kind = Model.Grunt; y = y +. 8.; hp = 1; score = 100});
    mk_event
      (at_x +. 24.)
      (Model.Spawn_enemy {kind = Model.Grunt; y; hp = 1; score = 100});
  ]

(* Turret + shielded combo — harder mixed group. *)
let fortress_group ~at_x =
  [
    mk_event
      at_x
      (Model.Spawn_enemy {kind = Model.Turret; y = 25.; hp = 3; score = 350});
    mk_event
      at_x
      (Model.Spawn_enemy {kind = Model.Turret; y = 55.; hp = 3; score = 350});
    mk_event
      (at_x +. 20.)
      (Model.Spawn_enemy {kind = Model.Shielded; y = 40.; hp = 5; score = 600});
  ]

let strafer_quad ~at_x ~y =
  [
    mk_event
      at_x
      (Model.Spawn_enemy {kind = Model.Strafer; y; hp = 1; score = 200});
    mk_event
      (at_x +. 5.)
      (Model.Spawn_enemy
         {kind = Model.Strafer; y = y +. 10.; hp = 1; score = 200});
    mk_event
      (at_x +. 10.)
      (Model.Spawn_enemy
         {kind = Model.Strafer; y = y +. 20.; hp = 1; score = 200});
    mk_event
      (at_x +. 15.)
      (Model.Spawn_enemy
         {kind = Model.Strafer; y = y +. 30.; hp = 1; score = 200});
  ]

let mine_corridor ~at_x =
  (* Two parallel mine lanes — forces the player to pick a path. *)
  [
    mk_event
      at_x
      (Model.Spawn_enemy {kind = Model.Mine; y = 18.; hp = 1; score = 300});
    mk_event
      (at_x +. 12.)
      (Model.Spawn_enemy {kind = Model.Mine; y = 18.; hp = 1; score = 300});
    mk_event
      (at_x +. 24.)
      (Model.Spawn_enemy {kind = Model.Mine; y = 18.; hp = 1; score = 300});
    mk_event
      at_x
      (Model.Spawn_enemy {kind = Model.Mine; y = 58.; hp = 1; score = 300});
    mk_event
      (at_x +. 12.)
      (Model.Spawn_enemy {kind = Model.Mine; y = 58.; hp = 1; score = 300});
    mk_event
      (at_x +. 24.)
      (Model.Spawn_enemy {kind = Model.Mine; y = 58.; hp = 1; score = 300});
  ]

let level2 : Model.event list =
  List.sort (fun a b -> compare a.Model.trigger_x b.Model.trigger_x)
  @@ List.concat
       [
         (* Opening: splitters + fast grunts to establish tone. *)
         splitter_cluster ~at_x:50. ~y:40.;
         dense_wave ~at_x:130. ~y:38.;
         [mk_event 200. (Model.Spawn_pickup (Model.Power_up_speed, 40.))];
         (* Speed burst mid-level pick-ups. *)
         [speed_burst ~at_x:450. ~y:38.];
         [speed_burst ~at_x:850. ~y:42.];
         (* Omega formation waves at x≈900 and x≈1300. *)
         omega_formation ~at_x:900. ~y:40.;
         omega_formation ~at_x:1300. ~y:38.;
         (* Asteroid-belt corridor feel: mine lanes + pressure. *)
         mine_corridor ~at_x:260.;
         splitter_cluster ~at_x:360. ~y:30.;
         splitter_cluster ~at_x:380. ~y:55.;
         strafer_quad ~at_x:440. ~y:20.;
         dense_wave ~at_x:520. ~y:35.;
         fortress_group ~at_x:600.;
         [mk_event 660. (Model.Spawn_pickup (Model.Power_up_missile, 45.))];
         mine_corridor ~at_x:720.;
         (* Carrier — slow heavy ship that spawns grunts; 4 spikes nearby. *)
         [carrier ~at_x:800. ~y:38.];
         [spike ~at_x:820. ~y:28. ~height:14];
         [spike ~at_x:850. ~y:52. ~height:12];
         [spike ~at_x:880. ~y:38. ~height:18];
         [spike ~at_x:910. ~y:22. ~height:10];
         splitter_cluster ~at_x:820. ~y:40.;
         strafer_quad ~at_x:900. ~y:25.;
         (* Mid-section intensification. *)
         dense_wave ~at_x:970. ~y:42.;
         boomerang_pair ~at_x:1000.;
         [
           mk_event
             1020.
             (Model.Spawn_enemy
                {kind = Model.Shielded; y = 30.; hp = 6; score = 700});
         ];
         [
           mk_event
             1040.
             (Model.Spawn_enemy
                {kind = Model.Shielded; y = 55.; hp = 6; score = 700});
         ];
         mine_corridor ~at_x:1100.;
         splitter_cluster ~at_x:1180. ~y:38.;
         fortress_group ~at_x:1240.;
         [mk_event 1300. (Model.Spawn_pickup (Model.Power_up_shield, 40.))];
         strafer_quad ~at_x:1350. ~y:18.;
         dense_wave ~at_x:1430. ~y:40.;
         mine_corridor ~at_x:1500.;
         [
           mk_event
             1560.
             (Model.Spawn_pickup (Model.Power_up_force_upgrade, 40.));
         ];
         (* Dual-core boss: two linked boss entities spawn together. *)
         [mk_event 1700. (Model.Spawn_boss {hp = 40; score = 8000})];
       ]

(* ========================================================================= *)
(*  Level 3 — "The Core"  (red-tinted environment, laser emitters, Bydo boss) *)
(* ========================================================================= *)

(* Laser emitter placement — the key new hazard. *)
let laser_pair ~at_x =
  [
    mk_event
      at_x
      (Model.Spawn_enemy
         {kind = Model.Laser_emitter; y = 24.; hp = 3; score = 450});
    mk_event
      (at_x +. 30.)
      (Model.Spawn_enemy
         {kind = Model.Laser_emitter; y = 52.; hp = 3; score = 450});
  ]

(* Shielded + turret gauntlet. *)
let gauntlet ~at_x =
  [
    mk_event
      at_x
      (Model.Spawn_enemy {kind = Model.Turret; y = 20.; hp = 4; score = 400});
    mk_event
      at_x
      (Model.Spawn_enemy {kind = Model.Turret; y = 60.; hp = 4; score = 400});
    mk_event
      (at_x +. 15.)
      (Model.Spawn_enemy {kind = Model.Shielded; y = 30.; hp = 6; score = 700});
    mk_event
      (at_x +. 15.)
      (Model.Spawn_enemy {kind = Model.Shielded; y = 52.; hp = 6; score = 700});
    mk_event
      (at_x +. 30.)
      (Model.Spawn_enemy {kind = Model.Shielded; y = 40.; hp = 8; score = 900});
  ]

(* Full-screen splitter ambush. *)
let splitter_ambush ~at_x =
  [
    mk_event
      at_x
      (Model.Spawn_enemy {kind = Model.Splitter; y = 15.; hp = 2; score = 250});
    mk_event
      (at_x +. 8.)
      (Model.Spawn_enemy {kind = Model.Splitter; y = 30.; hp = 2; score = 250});
    mk_event
      (at_x +. 16.)
      (Model.Spawn_enemy {kind = Model.Splitter; y = 45.; hp = 2; score = 250});
    mk_event
      (at_x +. 24.)
      (Model.Spawn_enemy {kind = Model.Splitter; y = 60.; hp = 2; score = 250});
    mk_event
      (at_x +. 4.)
      (Model.Spawn_enemy {kind = Model.Splitter; y = 22.; hp = 2; score = 250});
    mk_event
      (at_x +. 12.)
      (Model.Spawn_enemy {kind = Model.Splitter; y = 38.; hp = 2; score = 250});
  ]

(* Mine + laser combo wall: mines filling gap lanes while lasers fire. *)
let mine_laser_wall ~at_x =
  [
    mk_event
      at_x
      (Model.Spawn_enemy {kind = Model.Mine; y = 28.; hp = 1; score = 300});
    mk_event
      (at_x +. 10.)
      (Model.Spawn_enemy {kind = Model.Mine; y = 28.; hp = 1; score = 300});
    mk_event
      (at_x +. 20.)
      (Model.Spawn_enemy {kind = Model.Mine; y = 28.; hp = 1; score = 300});
    mk_event
      at_x
      (Model.Spawn_enemy {kind = Model.Mine; y = 48.; hp = 1; score = 300});
    mk_event
      (at_x +. 10.)
      (Model.Spawn_enemy {kind = Model.Mine; y = 48.; hp = 1; score = 300});
    mk_event
      (at_x +. 20.)
      (Model.Spawn_enemy {kind = Model.Mine; y = 48.; hp = 1; score = 300});
    mk_event
      (at_x +. 35.)
      (Model.Spawn_enemy
         {kind = Model.Laser_emitter; y = 38.; hp = 3; score = 450});
  ]

let level3 : Model.event list =
  List.sort (fun a b -> compare a.Model.trigger_x b.Model.trigger_x)
  @@ List.concat
       [
         (* Opening gauntlet: 4 turret pairs at x=100,200,300,400 with
            mine rings between them — an intense corridor opening. *)
         turret_pair ~at_x:100.;
         mine_field ~at_x:145.;
         turret_pair ~at_x:200.;
         mine_field ~at_x:245.;
         turret_pair ~at_x:300.;
         mine_field ~at_x:345.;
         turret_pair ~at_x:400.;
         [mk_event 420. (Model.Spawn_pickup (Model.Power_up_speed_burst, 40.))];
         (* Intro: dense formation + first laser emitter. *)
         dense_wave ~at_x:50. ~y:38.;
         laser_pair ~at_x:120.;
         [mk_event 200. (Model.Spawn_pickup (Model.Power_up_speed, 40.))];
         splitter_ambush ~at_x:240.;
         (* Gauntlet section. *)
         gauntlet ~at_x:340.;
         [mk_event 420. (Model.Spawn_pickup (Model.Power_up_missile, 38.))];
         mine_laser_wall ~at_x:480.;
         dense_wave ~at_x:580. ~y:40.;
         laser_pair ~at_x:650.;
         [mk_event 720. (Model.Spawn_pickup (Model.Power_up_shield, 42.))];
         splitter_ambush ~at_x:780.;
         (* Carrier with a spike gauntlet — forces careful navigation. *)
         [carrier ~at_x:840. ~y:35.];
         [spike ~at_x:855. ~y:25. ~height:16];
         [spike ~at_x:870. ~y:50. ~height:14];
         [spike ~at_x:890. ~y:38. ~height:20];
         [spike ~at_x:915. ~y:28. ~height:12];
         gauntlet ~at_x:860.;
         mine_laser_wall ~at_x:960.;
         (* Escalation — tight corridor feel. *)
         laser_pair ~at_x:1050.;
         (* 3 Boomerangs mid-section for level 3. *)
         [boomerang ~at_x:1070. ~y:28.];
         boomerang_pair ~at_x:1090.;
         [
           mk_event
             1060.
             (Model.Spawn_enemy
                {kind = Model.Shielded; y = 38.; hp = 8; score = 900});
         ];
         dense_wave ~at_x:1130. ~y:35.;
         splitter_ambush ~at_x:1200.;
         gauntlet ~at_x:1280.;
         [
           mk_event
             1360.
             (Model.Spawn_pickup (Model.Power_up_force_upgrade, 40.));
         ];
         mine_laser_wall ~at_x:1400.;
         laser_pair ~at_x:1480.;
         [mk_event 1500. (Model.Spawn_pickup (Model.Power_up_shield, 45.))];
         splitter_ambush ~at_x:1560.;
         dense_wave ~at_x:1620. ~y:40.;
         gauntlet ~at_x:1680.;
         (* Diamond formation: 4 Strafers arranged in a diamond at world_x ≈ 900.
            Centre at y≈40; ±40px Y for top/bottom, ±60px trigger offset for
            leading/trailing so they arrive in diamond shape. *)
         [
           (* Centre-top *)
           mk_event
             900.
             (Model.Spawn_enemy
                {kind = Model.Strafer; y = 0.; hp = 2; score = 250});
           (* Centre-bottom *)
           mk_event
             900.
             (Model.Spawn_enemy
                {kind = Model.Strafer; y = 80.; hp = 2; score = 250});
           (* Leading tip (ahead of pack — spawns later so it is further right) *)
           mk_event
             960.
             (Model.Spawn_enemy
                {kind = Model.Strafer; y = 40.; hp = 2; score = 250});
           (* Trailing tip *)
           mk_event
             840.
             (Model.Spawn_enemy
                {kind = Model.Strafer; y = 40.; hp = 2; score = 250});
         ];
         (* Carrier with escort: 1 Carrier flanked by 2 Boomerangs at world_x ≈ 1200. *)
         [
           mk_event
             1200.
             (Model.Spawn_enemy
                {kind = Model.Carrier; y = 38.; hp = 8; score = 800});
           (* Escort Boomerangs at ±60px Y from carrier centre *)
           mk_event
             1200.
             (Model.Spawn_enemy
                {kind = Model.Boomerang; y = -22.; hp = 2; score = 350});
           mk_event
             1200.
             (Model.Spawn_enemy
                {kind = Model.Boomerang; y = 98.; hp = 2; score = 350});
         ];
         (* Bydo Core — final boss, 3 phases (reuses boss entity with high HP). *)
         [mk_event 1800. (Model.Spawn_boss {hp = 70; score = 15000})];
       ]

(* ========================================================================= *)
(*  Accessors                                                                 *)
(* ========================================================================= *)

(* Return events + palette for a given level number. *)
let get_level n =
  match n with
  | 1 -> (level1, Model.Palette_rocky)
  | 2 -> (level2, Model.Palette_asteroid)
  | 3 -> (level3, Model.Palette_core)
  | _ -> (level1, Model.Palette_rocky)

let max_level = 3
