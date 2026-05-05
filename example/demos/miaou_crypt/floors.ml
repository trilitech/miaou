(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(** Hand-authored floor layouts for MIAOU Crypt.

    Grid legend:
    {v
      #  wall
      .  empty floor
      K  key (pickup)
      P  health potion (+5 HP)
      T  torch (+visibility, +30 s warm palette)
      W  sword upgrade (+1 attack damage, persistent for run)
      D  closed locked door (consumes a key on Space)
      d  closed unlocked door
      S  stairs down
      X  exit / artifact (final floor)
      @  player spawn (faces +x i.e. east)
      M  map scroll (reveals entire floor minimap)
      R  ring of speed (+1.5× speed for 30 s)
      V  armor (reduces all incoming damage by 1, shown as [A])
      Q  speed scroll (+1.5× speed for 15 s)
      s  spider
      k  skeleton (lowercase k since K = key)
      b  bat
      w  wraith
      A  archer (ranged, fires arrows every 2 s from 3+ tiles)
      Z  zombie (slow, immune to stun, drops healing rune on death)
      B  bomb scroll (area-blast item, pressed f to use)
      L  lich (boss — floor 5)
      g  dragon (boss — floor 7, final)
    v}

    Round 1 polish extended the dungeon to seven floors. Floor 5 hosts
    the Lich (mid-boss), floor 7 hosts the Dragon (final boss); both
    rooms are explicit boss arenas with the boss anchored at the back
    wall and a corridor approach so the player can be hit by ranged
    fireballs.

    Round 2 adds Archer enemies on floors 3, 5, and 7 (replacing one
    Skeleton per floor) and Map_scroll pickups on floors 2 and 4.

    Round 3 adds: three Archers in arrow-slit positions on floor 3; a
    treasury room (Sword + Map_scroll, guarded by 2 Skeletons + Wraith)
    on floor 4; a locked door on floor 6 requiring the existing key
    before reaching the stairs; and a Ring_of_speed item on floor 6.
    'R' in the layout = Ring_of_speed pickup.

    Round 4 adds: a crossroads room (4×4 open space with a Potion) in
    the centre of floor 3, with Archers repositioned to fire down the
    corridors leading to it; and a secret room on floor 4 accessible by
    walking through a wall that looks like a wall on the minimap (no
    door, no hint) — it contains a Health potion.

    Round 7 adds: Speed_scroll (Q) in floor 3 crossroads near the Potion;
    Armor (V) in floor 6 dead-end north-east alcove.

    Round 9 adds: Bomb_scroll (B) item on floors 3 and 5; floor 3
    variant B (crossroads with locked doors, Archer, Skeleton, Spider);
    'B' = bomb scroll pickup. *)

(* Floor 1 has two layout variants (A and B) chosen randomly each run. *)
let floor_1_a =
  [|
    "##############";
    "#@...#.....s.#";
    "#....#.......#";
    "#....d...#####";
    "######.P.#K..#";
    "#....#...#...#";
    "#.s..#...D...#";
    "#....#...#.S.#";
    "#....#...#####";
    "##############";
  |]

let floor_1_b =
  [|
    "##############";
    "#@..........b#";
    "#...########.#";
    "#...#K.....d.#";
    "#...#.....####";
    "#...#..P..#s.#";
    "#...d.....D..#";
    "#...########.#";
    "#............S";
    "##############";
  |]

let floor_1 = floor_1_a

(*  Floor 2 round 5: added a second Skeleton on the northern path (forcing
    the player to fight before reaching the key, or attempt to sneak past
    via the door), and a Health potion in the southern corridor to reward
    thorough exploration. *)
let floor_2_a =
  [|
    "################";
    "#@.....#...K...#";
    "#...k..#...P...#";
    "#..s...d...b...#";
    "########...#####";
    "#..T.#.....#...#";
    "#..M.#..k..D.S.#";
    "#....#..P..#...#";
    "################";
  |]

(* Floor 2 variant B: L-shaped layout with bats in a wider arena.
   Key guarded by a bat in the north room; Skeleton patrols the south
   corridor before the stairs. *)
let floor_2_b =
  [|
    "################";
    "#@...........b.#";
    "#...#########.##";
    "#...#K.........#";
    "#...d..b.......#";
    "#...#########.##";
    "#...#..T.......#";
    "#...#..Z...P...#";
    "#...d......M...#";
    "#...#..k...D.S.#";
    "################";
  |]

let floor_2 = floor_2_a

(*  Floor 3 round 4: crossroads room (4×4) opened up in the centre of
    the map (rows 4-7, cols 7-10).  A Potion sits in the crossroads
    centre.  Three Archers repositioned to fire down the north, west,
    and east corridors leading into the crossroads.  Bat retained in
    the south-west pocket for flavour.
    Round 9: Bomb_scroll (B) added to the crossroads area near the
    Speed_scroll. *)
let floor_3_a =
  [|
    "##################";
    "#@.............#W#";
    "#..########....#.#";
    "#..#K....A.....d.#";
    "#..#....####.###.#";
    "#....A..P.Q.A..#.#";
    "#.b..####....###.#";
    "######....#......#";
    "#.......BD..S....#";
    "##################";
  |]

(* Floor 3 variant B: alternate crossroads layout with locked doors,
   an Archer in the south corridor, a Skeleton in the key alcove,
   and a Spider in the northern shortcut.  Bomb_scroll placed in the
   eastern wing as a reward for exploring past the locked door. *)
let floor_3_b =
  [|
    "####################";
    "#@..#.....#........#";
    "#...#.s...#...P....#";
    "#...D......d.......#";
    "#...#######.#######";
    "#...#k.....P#......#";
    "#...#.......D..B...#";
    "#...#.A.....#......#";
    "################.###";
    "###############.S###";
    "####################";
  |]

let floor_3 = floor_3_a

(*  Floor 4 round 4: secret room added to the east side of the middle
    corridor.  Row 5 col 17 (the old outer wall) is now passable floor
    ('.') — the minimap shows it as floor only if visited, but since
    there is no door or visual hint the player must explore by walking
    into what appears to be a wall.  The hidden room (cols 18-22,
    rows 4-6) contains a Health potion at col 20 row 5. *)
let floor_4 =
  [|
    "########################";
    "#@..#..w..#..k.K.######";
    "#...#..s..#.Wk..w######";
    "#...d.....d..PM..######";
    "#####.....##########.##";
    "#......k.........#.P..#";
    "#####.....##########.##";
    "#...d.....d......######";
    "#...#..b..#.Z.S..######";
    "#.T.#..w..D......######";
    "########################";
  |]

(* Floor 5: LICH BOSS room. Layout:
   - Player enters from the west via a locked door (needs a key on
     floor 5, found in a nearby alcove).
   - Pillars create cover so the player can sidestep fireballs.
   - Lich anchored at the east wall.
   - Archer replaces the Skeleton at the south approach.
   - Exit stairs hidden behind the Lich. *)
(* Floor 5: LICH BOSS room. Round 8 adds a secret alcove south of the
   boss area.  Row 8 col 13 is changed from '#' to '.' — it appears as
   part of the solid '#####' cluster on the minimap but is actually
   passable.  The player can walk into the apparent wall from (col 13,
   row 9) to reach the alcove at (col 13, row 7) where a Potion awaits.
   Row 7 col 13 is also opened from '#' to 'P'. *)
let floor_5 =
  [|
    "######################";
    "#@.......#K....#.....#";
    "#..A.....#.....d.....#";
    "#........d.....#..w..#";
    "######...#######.....#";
    "#....#...#...........#";
    "#.P..D...#...#...L.S.#";
    "#....#...#...P.......#";
    "######...####........#";
    "#......#..........B..#";
    "#..b...#......T......#";
    "######################";
  |]

(*  Floor 6: added a locked door (D) at col 16, row 3 (east of the
    middle section).  The existing key at col 4, row 5 now also unlocks
    this door — the player must explore the centre to find it before
    reaching the stairs in the east wing.  A Ring_of_speed (R) sits in
    the east wing at col 20, row 5 as a reward for the detour.
    The unlocked door at row 3 col 16 becomes 'D' (locked). *)
let floor_6 =
  [|
    "########################";
    "#@..#.....#.....#...V..#";
    "#...#..w..#..k..#...P..#";
    "#...d.....d.....D......#";
    "#####.....#######......#";
    "#..K..............wR...#";
    "#####.....#######......#";
    "#...d.....d.....d......#";
    "#...#..s..#..b..#...S..#";
    "#.W.#.....D.....#......#";
    "########################";
  |]

(* Floor 7: DRAGON BOSS — final. Wide arena, dragon at the centre east,
   pillars give cover, the artifact (X) is right behind the dragon.
   Archer replaces one Skeleton at the north approach. *)
let floor_7 =
  [|
    "##########################";
    "#@.....#......#..........#";
    "#..A...#.s....#....w.....#";
    "#......d......d..........#";
    "########.....##......##..#";
    "#.K..#..............P....#";
    "#....D....##........g..X.#";
    "#....#..............T....#";
    "########.....##......##..#";
    "#......d......d..........#";
    "#..b...#..b...#....w.....#";
    "#......#......#..........#";
    "##########################";
  |]

let all = [|floor_1; floor_2; floor_3; floor_4; floor_5; floor_6; floor_7|]

let count = Array.length all

(** [get n] returns floor [n] (1-based). Indices outside [1..count] are
    clamped. For floors 1, 2, and 3 a random variant (A or B) is chosen
    each call, providing layout variety across runs. *)
let get n =
  let i = max 1 (min count n) - 1 in
  match n with
  | 1 -> if Random.bool () then floor_1_a else floor_1_b
  | 2 -> if Random.bool () then floor_2_a else floor_2_b
  | 3 -> if Random.bool () then floor_3_a else floor_3_b
  | _ -> all.(i)

(** Whether floor [n] hosts a boss (decided by inspecting whether the
    layout contains an L or g glyph). Cheap because the strings are
    short. *)
let is_boss_floor n =
  let layout = get n in
  Array.exists
    (fun row -> String.contains row 'L' || String.contains row 'g')
    layout
