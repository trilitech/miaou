# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- **MIAOU Crypt polish round 9**: five gameplay and atmosphere improvements. (1) **Bomb scroll item** (`B` in floor layouts, key `f`): area-blast that damages all enemies within radius 3 for 5 HP, spawns 24 orange particles, and triggers screen shake; placed on floors 3 and 5. (2) **Monster alert state**: Spider, Skeleton, and Zombie enemies enter an alerted state when the player comes within 4 Manhattan tiles — halving their movement cooldown; a bright yellow `!` sprite appears above the enemy billboard for 1.5 s on first alert. (3) **Floor 3 variant B**: alternate crossroads layout with locked doors, an Archer, Skeleton, and Spider in rearranged positions, randomly selected alongside the original floor 3A layout each run. (4) **Experience and level-up system**: killing monsters awards XP (score ÷ 5, min 1); reaching the XP threshold triggers a level-up (+5 max HP, +2 current HP, +1 attack bonus, +20 to next threshold), spawns golden particles, and shows a blinking `★ LEVEL UP! Lv.N ★` banner; the HUD shows `Lv.N` next to HP and `[B:N]` for bomb count. (5) **Enhanced title corridor art**: depth-shaded block-character first-person view with gradient wall shading and torch glyphs replaces the previous simple box-drawing art.

- **MIAOU Links polish round 9**: five gameplay, display, and content improvements. (1) **Club power yardage label**: during Aiming, the HUD now shows "MAX:XXXyd" for the current club at full power; during Powering, the label switches to "~XXXyd" reflecting the actual current power-meter fraction, giving precise distance feedback for shot planning. (2) **Scorecard cumulative/delta columns**: the end-of-round Card Summary table gains a per-hole `Delta` column (showing `+N`, `-N`, or `E` per hole) and a `Cumul` running-total column; over-par holes are highlighted in red, under-par in cyan. (3) **Wind gust whoosh marks**: when a gust event fires, four short diagonal streak marks slide rightward across the framebuffer for 1.5 s, fading as the gust subsides; positions are deterministic (no allocation) based on the `gust_visual_t` countdown. (4) **"The Island" hole** (hole 13 replacement): a par-3 island-green hole where the entire approach is water; the only safe landing is the small green island centred in the hazard, demanding precision over power. (5) **"NEW BEST" run banner**: the run-complete screen shows a gold `*** NEW PERSONAL BEST! ***` banner when the player beats their stored run record; otherwise it shows the current stored best for comparison.

- **MIAOU Force polish round 10**: five presentation and feedback improvements. (1) **Game-over screen enhancement**: "PILOT STATUS: KIA" in bright red, "REACHED LEVEL: N", and a heart-glyph lives display (up to 3 filled hearts per remaining life) added after the title. (2) **Turret rotation visual**: Turret enemies now track the player each tick and rotate their barrel to face the nearest cardinal direction; the barrel pixel indicator moves to the corresponding side of the body. (3) **End-of-run summary screen**: clearing all three levels shows "MISSION COMPLETE", a per-level score breakdown ("LVL 1: NNNN  LVL 2: NNNN  LVL 3: NNNN") based on per-level score deltas stored in `level_scores`, and a pilot rank (ROOKIE / CADET / VETERAN / ACE PILOT) based on total score. (4) **Force pod recall sprint**: pressing `d` to recall the Force pod now triggers a 0.3 s burst at 2× recall speed, making the snap-back feel snappier; a `recall_t` counter on the detached record drives the boost. (5) **Speed tier bar in HUD**: the right-aligned weapon section now shows a `Spd:[■■□]` filled-square tier bar for speed upgrades (0–3 levels) instead of a plain `[>>]` icon.

- **MIAOU Force polish round 9**: five gameplay and feedback improvements. (1) **Speed Burst power-up**: new `Power_up_speed_burst` pickup (cyan spark sprite) spawns in levels 1–3; collecting it sets a 4 s timer that multiplies ship speed by 1.6 and reduces fire interval to 0.06 s; a rainbow particle trail is drawn behind the ship while active, and "SPD" in bright cyan appears in the HUD. (2) **Omega Formation wave macro**: a six-Grunt hexagon wave followed by a central Turret 0.3 s later; used twice in level 2 (world_x ≈ 900 and 1300). (3) **Phase-change warning banner**: when the boss transitions phases (at 50% and 25% HP), a full-width bright red/orange bar with "!! PHASE CHANGE !!" text fades out over 0.6 s across the vertical midpoint. (4) **Score milestone popups**: passing 5 000, 10 000, 20 000, and 50 000 points (once each) shows a fading gold text overlay at the top-right corner for 1.2 s. (5) **Level 3 opening gauntlet**: four turret pairs at world_x = 100, 200, 300, 400 with mine fields between them create an intense corridor entry section; a speed burst pickup follows at x = 420.

- **MIAOU Crypt polish round 8**: six gameplay and atmosphere improvements. (1) **Zombie monster** (`Z` in floor layouts): HP 8, damage 3, XP 30; moves very slowly (3 s cooldown); immune to stun; drops a `Healing_rune` on death that restores +3 HP when stepped on; dark-green chunky sprite placed on floor 2B and floor 4. (2) **Healing_rune tile**: a green glowing pickup left by Zombie corpses; shown on minimap and in floor marks. (3) **Passive HP regen**: standing still for 4 s with HP below max restores +1 HP; a `"..."` indicator appears in the HUD when regen is halfway charged; taking damage resets the timer. (4) **Improved game-over screen**: redesigned with gravestone ASCII art panel showing `FLOORS REACHED`, `TOTAL KILLS`, `FLOOR RATINGS` star breakdown, and `CAUSE OF DEATH`. (5) **Torch pickup particle burst**: picking up a Torch spawns 8 warm-orange particles; the HUD torch timer blinks at 4 Hz when fewer than 5 s remain. (6) **Floor 5 secret alcove**: a 1-tile gap in the wall cluster near the Lich boss room (appears solid on minimap) leads to a hidden Health Potion.

- **MIAOU Links polish round 8**: six perks, physics, and UX improvements. (1) **Rough Ready perk** ($16, glyph `Rr`): rough terrain friction reduced to 1.2 (from 2.0) when active, making rough play like fairway. (2) **Albatross Alert perk** ($20, glyph `Al`): finishing a hole 2+ under par awards +4 bonus coins in run mode. (3) **Eagle stamina recovery**: eagle or better in run mode restores +1 stamina and shows a "EAGLE! +1 Stamina" cyan banner in the hole-clear panel. (4) **Landing divot ring**: when the ball touches down after flight, an expanding fading ring appears at the landing spot for 0.5 s. (5) **CONDITIONS label on hole preview**: CALM/BREEZY/GUSTY with colour coding (green/yellow/red) appears in the hole preview before committing to play. (6) **Chip-in detection**: ball flying z > 1.0 and landing in the cup zone is flagged as a chip-in and shown as "CHIP-IN!" in gold in the hole-clear panel.

- **MIAOU Force polish round 8**: six combat and feedback improvements. (1) **Enemy spawn fade-in**: newly spawned enemies materialise with a checkerboard pixel pattern for 0.3 s (skip every even-sum pixel), giving a brief blink-in effect. (2) **Laser emitter telegraph**: during charge-up, a dotted red line extends from the Laser_emitter to the right edge, previewing the beam path. (3) **Shield 2-hit absorption**: `shield_hits` counter introduced; shield now absorbs 2 hits instead of 1 before deactivating. (4) **Homing bullet particle trail**: `Bullet_homing` bullets spawn a small hue-4 (red) fading dot at their position each render frame, creating a glowing chase trail. (5) **Per-level best scores on title**: session-best scores for levels 1–3 are tracked in `best_level` and shown below the pilot rank on the title screen. (6) **Mine ring explosion**: chain-detonated mines also spawn 16 ring-pattern hue-1 (white) particles in a radial burst, visually distinct from the regular explosion cloud.

- **MIAOU Links polish round 7**: five physics and UX improvements. (1) **Out-of-bounds penalty**: rolling into a `Wall_oob` tile reverts ball to previous position, stops it, adds +1 stroke, and shows "OUT OF BOUNDS +1" event banner (matching the water-penalty pattern). (2) **Double Down perk** ($15): birdie or better doubles the per-hole coin reward in roguelite runs; glyph `Dd`. (3) **Wind tick marks**: when wind magnitude > 0.5, three short perpendicular tick marks appear on the wind arrow shaft, providing a visual speed cue without text. (4) **Cup capture ring during aiming**: while in Aiming or Powering mode, a green pulsing ring appears at slightly larger radius around the cup, showing the capture zone. (5) **Aim distance confirmed**: the `~Xyd` distance label during Powering was already present in the HUD; verified it accounts for `meter01` via `yardage_of_club`.

- **MIAOU Crypt polish round 7**: six dungeon and gameplay improvements. (1) **Armor item** (`V` in layouts): picking it up sets `has_armor`, reducing all incoming damage by 1 (min 1); shown as `[A]` in HUD; placed floor 6. (2) **Wraith phase teleport**: Wraiths teleport to the tile directly in front of the player every 5 s (if within 6 tiles Manhattan distance), with a brief flash on arrival. (3) **Star ratings**: floors cleared earn 1–3 stars based on score vs `floor×100` / `floor×200` benchmarks; shown as `F1:★★☆  F2:★☆☆  ...` on the game-over screen. (4) **Dragon phase-3 advance**: at ≤25% HP the Dragon moves one tile toward the player every 3 s, closing the distance in the final phase. (5) **Minimap legend**: a `"▲P  ●E  ★K  ×D"` legend line is rendered below the minimap box. (6) **Speed Scroll item** (`Q`): sets `speed_ring_timer = 15 s` (half the Ring of Speed); placed on floor 3 in the crossroads.

- **MIAOU Force polish round 7**: mid-layer rock formations scroll at 60% parallax speed between star layers (10 blobs, derived from `world_x`, no per-frame state); Carrier death triggers 3 spread explosion bursts; level-clear cinematic gains MAX COMBO and lives-remaining display; detached Force pod coast-clamps to prevent backward drift; HUD shows compact weapon icons right-aligned (`[M]`, `[S]`, `[F+]`, `[>>]`) with level number; entering a new level plays a 0.4 s white screen-wipe transition (vertical bar sweeps left→right).

- **MIAOU Links polish round 6**: six UI, physics, and content improvements. (1) **Shop UI**: selected item highlighted with emphasis styling; unaffordable items shown in muted style with `[can't afford]` suffix; coins at the top; navigable SKIP entry at the bottom (Enter on SKIP exits immediately). (2) **Backspin perk** (new, $20): ball landing on green applies 20% reverse velocity, simulating backspin stopping near the cup; glyph `Bs`. (3) **Run progress in title**: when a run is active, title/intro shows holes completed, stamina, coins, and active perk glyphs. (4) **Hole rating splash**: on hole completion, the par rating (BIRDIE, EAGLE, etc.) is shown for 2 s in triple big-text before the full scorecard; Space skips the wait; `mode_t` now resets to 0 entering `Hole_clear`. (5) **Ball glow halo**: while in flight, a dim yellow disc (radius+2) surrounds the ball sphere. (6) **Hole 12 water hazard**: a 3-tile water strip added at the approach fairway, turning the straight run-up into a carry challenge.

- **MIAOU Crypt polish round 6**: six gameplay and atmosphere improvements. (1) **Bat AI overhaul**: bats now pick a random cardinal direction every ~0.5 s from a per-bat `bat_dir_t`/`bat_dx`/`bat_dy` counter instead of re-rolling every move — producing true zigzag flight; move interval reduced to 0.15 s (was ~0.6–1.0 s) for rapid darting behaviour. (2) **Spin special attack**: pressing `e` spends one special charge (shown in HUD as `⚡×N`) to deal 3 damage to all 8 surrounding tiles simultaneously with a screen shake; players start with 1 charge, gain +1 per 5 floors descended and +1 when picking up a Sword upgrade (max 3). (3) **Player trail on minimap**: the last 5 tile positions are drawn as fading-grey dots (newest brightest at grey 180, oldest at grey 40), giving a breadcrumb path on the minimap. (4) **Minimap visited-tile contrast**: visited floor tiles now render at (60, 48, 38) instead of (40, 32, 26), making explored areas visibly lighter against the dark minimap background. (5) **Tile-grid wall shading**: every 3rd tile row (`map_y mod 3 = 0`) reduces wall brightness by 15% (horizontal mortar course); even-column tiles (`map_x mod 2 = 0`) get a 5% boost for vertical seam variation, adding stone-block structure to the raycasted view. (6) **Floor layout variants**: floors 1 and 2 each have two layouts (A and B) chosen randomly via `Random.bool ()` at `load_floor` time, doubling early-game variety; title screen gains a nine-line ASCII corridor art block for atmosphere.

- **MIAOU Force polish round 6**: six gameplay and feel improvements. (1) **Pickup flash**: picking up any power-up briefly flashes the ship sprite bright white for 0.2 s via a `pickup_flash_t` decay timer on `weapon_state`. (2) **Level 3 formations**: diamond formation (4 Strafers at ±60 px X, ±40 px Y) at world_x ≈ 840–960; carrier-with-escort (1 Carrier + 2 Boomerangs at ±60 Y) at world_x ≈ 1200. (3) **Difficulty scaling**: `difficulty_factor` (1.0 / 1.2 / 1.4 for levels 1–3) scales enemy `max_hp` at spawn and enemy bullet speed (capped at 250), making later levels meaningfully harder. (4) **Respawn star burst**: on death, 16 cyan hue-6 particles explode in a ring around the ship (speed 30, life 0.6 s), giving clear visual feedback of the invincibility window. (5) **Final boss HP boost**: level 3 Bydo Core raised from 50 → 70 HP for a more epic finale. (6) **Flashing combo multiplier**: when combo ≥ 2, the `×N` HUD label alternates to bright yellow using `sin(mode_t * 6)`, making the timer more eye-catching.

- **MIAOU Links polish round 5**: five physics and UX improvements. (1) **Tile-specific landing physics**: Green friction reduced to 0.15/s (smoother putting); Rough landing applies a 10% extra speed reduction; Sand landing clamps ball speed to 1.5 and adds a 5% velocity drift rotated 45° (unpredictable sand bounce). (2) **Putter ghost line**: with the Putter equipped, ghost-dot count increases to 10 and projected range halves, giving a precise dotted putt line instead of the generic 5-dot preview. (3) **Title screen stats**: classic best now reads "Classic best: -N under par" / "no round completed"; run best shows "Run best: N/9 holes (+N under par)" / "no run completed"; coin total shown prominently. (4) **Hole preview perk line**: during a roguelite run with active perks, a second footer line lists current perk effects in human-readable form (Eagle Eye, Power Swing, Sand Legs, etc.). (5) **Stamina bar styling**: bar segments color green/yellow/red by threshold; at stamina ≤ 3 the bar blinks via `sin(mode_t * 8) > 0` and a "LOW" pixel-dot warning appears beside it.

- **MIAOU Crypt polish round 5**: six environmental and feedback improvements. (1) **Torch lighting**: view distance extends from ~10 to 16 tiles while torch is active; walls receive an additive +30R +15G −20B warmth pass in `draw_wall_slice`. (2) **Health vignette**: when HP ≤ 5, a 10-pixel red ring pulses around the 3D view perimeter (alpha = `(1 − hp/5) × sin(mode_t × 4.0)`). (3) **Corpse markers**: monster kills add the tile to a `corpses` list; minimap renders dark-red × markers at each corpse tile, aiding navigation. (4) **Stairway glow**: stairs tile renders with +80 R/G and −10 B brightness boost in the raycaster, making the exit visually pop as warm yellow. (5) **Floor 2 additions**: a guarding Skeleton at the key corridor plus a reward Potion in the southern passage. (6) **Better game-over**: screen now shows "DEPTH REACHED: FLOOR N", score, best records, and cause of death ("Killed by SPIDER" etc.) tracked via `last_death_cause` on the model.

- **MIAOU Force polish round 5**: seven improvements to content, feedback, and game feel. (1) **Boomerang enemy**: a new amber crescent-shaped enemy (HP 2, score 350) that sweeps in a cosine Y arc (period 4 s, amplitude 36 px) and fires a 2-bullet aimed spread every 2.5 s; two added to level 2 mid-section, three to level 3. (2) **Force pod auto-fire**: the detached Force pod now shoots forward automatically every 0.4 s (3 spread bullets when the Force upgrade is held); the `force_fire_t` counter lives on the `Force_detached` record. (3) **Force tether line**: while the Force pod is recalling, a dashed cyan line is drawn from the pod to the ship every 2 pixels along the connecting segment, alternating bright/dim cyan — makes the recall trajectory immediately legible. (4) **Animated score counter**: the HUD score display now rolls up smoothly via exponential smoothing (rate 8/s) toward the real score; the shown value is rounded to the nearest 10. (5) **Big-kill announcement**: kills worth ≥ 500 effective score points (combo-adjusted) trigger a 1.5 s gold "BIG KILL! +NNN" overlay rendered with the pixel-font at the lower-centre of the playfield. (6) **Radar dot panel**: a 30×8 px radar panel at the top-centre of the framebuffer shows up to 8 enemy dots (2×2 px each) positioned relative to the player; enemies behind the ship appear dim. (7) **Level 1 content additions**: a second Power-up Missile placed at world_x ≈ 800, and a three-Shielded fortress line at world_x ≈ 1400 just before the boss, adding a late-game challenge spike to the introductory level.

- **MIAOU Crypt polish round 4**: monster knockback + 0.4 s stun on melee hit (hits feel weighty); footstep dust-puff flash at bottom of view; inventory popup (`i` key) listing keys/potions/torches/sword/ring; secret room on floor 4 (hidden passage, no door hint); Dragon boss phase 2 breath cone (5-bullet fan at ≤50% HP) with a blinking "INCOMING!" warning banner; floor 3 gains a central crossroads room with Potion.

- **MIAOU Links polish round 4**: four gameplay and content improvements. (1) **Hole 18 "The Clubhouse"**: a finishing par-4 hole added to the classic tour — sweeping dogleg-right layout with water running along the left side of the fairway and two concentric sand-trap rings guarding the green; the classic tour now spans 18 holes. (2) **Wind gust events**: every hole, a random gust triggers between 2–8 s and lasts 1.5 s; the wind widget flashes orange with a faster ring pulse and a blinking row of dots above it; the gust delta is included in the per-stroke wind when swinging during a gust; a `[GUST]` label appears in the HUD text bar. (3) **Brighter ball trail**: the in-flight particle trail increases life from 0.25 s to 0.4 s and uses a white-fading-to-cyan palette (was a dim grass green), making the flight path more readable. (4) **Live par tracking and run totals**: the HUD now shows a real-time par delta (`+1`, `-1`, `E`) next to the stroke count; the hole-clear scorecard displays a bold "Run total: N under par" summary line after the per-hole breakdown.

- **MIAOU Force polish round 4**: game feel, difficulty curve, and content additions. (1) **Carrier enemy**: a new heavy enemy kind — a slow-moving 12×8 rectangular hull with two dark hangar-bay notches; HP = 8, hitbox radius 7, spawns two Grunt escorts every 3 seconds. Pulsing cyan trim on the edges animates with the entity phase timer. One carrier placed in levels 2 and 3. (2) **Ship-silhouette lives display**: the HUD now renders a column of tiny 5×3 ship silhouettes (one per remaining life) in the top-right of the framebuffer, replacing the plain number; up to 5 silhouettes are drawn before capping. (3) **Spike hazard columns**: terrain spike columns (`Spawn_hazard`) can now be placed at arbitrary world-x positions via a new `hazard` pool (cap 16). Spikes are rendered as a bright orange-red column with white tip and narrow side-glow. Contact with a spike (within 3 px horizontally, within the spike height vertically) triggers the same shield-or-death collision as enemy contact, with a brief invulnerability window. Three spikes added to level 1, four to level 2 and four to level 3 in the mid-sections. (4) **Prominent title ranking**: the title screen replaces the plain `best score:` line with a bold `BEST SCORE: NNNNNN` label and a pilot rank derived from the all-time best (`CADET` / `RECRUIT *` / `VETERAN **` / `ACE PILOT ***`). (5) **Low-health border alert**: when the player has exactly one life remaining, a 2-pixel-wide red border pulses around the entire framebuffer at 2 Hz, driven by `mode_t`, creating urgency without obscuring gameplay.

- **MIAOU Links polish round 3**: six improvements to game feel and content. (1) **Shot trajectory preview**: during Aiming and Powering states, 5 semi-transparent ghost dots are drawn along the predicted flight path, linearly spaced over the expected landing distance for the current club and power-meter fraction; dots are dimmed to ~35% brightness so they guide without cluttering. (2) **Club-specific arrow colours**: the aim arrow now uses a distinct tint per club — Driver is bright yellow, Iron is orange-tinted, Wedge is green-tinted, and Putter is pale blue; the power-meter gradient overrides club colour during Powering as before; the Eagle Eye perk warm-tints all clubs. (3) **Celebration star ring**: on hole completion, 12 golden star dots expand outward around the cup over 0.5 s (radius 2→8, brightness fading with the countdown timer), giving a burst of visual feedback at the moment of success. (4) **Water penalty overlay**: when a stroke penalty is applied for hitting water, a bright red horizontal bar appears above the splash site in the framebuffer for up to 1.2 s, fading with an alpha ramp; the `water_penalty_t` timer ticks during In_flight and Aiming states. (5) **Three new holes** (15–17) extending the classic tour to 17 holes: Hole 15 "The Lake" (par 4, large central water carry or go-around), Hole 16 "The Bunker Farm" (par 3, six sand bunkers in two symmetrical rows flanking the approach), Hole 17 "The Finale" (par 5, dogleg-left with water along the entire right side and sand traps on the left protecting a narrow green). (6) **Hole-in-one bonus**: any hole completed in one stroke instantly awards +3 stamina, +$8 coins, and shows "HOLE-IN-ONE! +3 Stam +$8" in the event banner and a bright gold line on the hole-clear screen.

- **MIAOU Crypt polish round 3**: six combat-feel and content improvements. (1) **Attack flash animation**: landing a melee hit sets a 0.3 s `attack_flash_t` timer; while active, `view.ml` draws a bright white diagonal cross (two diagonal line-sweeps) centred on-screen at alpha proportional to the remaining time, giving clear visual feedback that the blow connected. (2) **Weapon swing arc**: simultaneously with the slash cross, five short horizontal dashes at varying y-offsets sweep outward from the screen centre, suggesting the weapon arc; pixels fade toward the tip so the motion reads as directional. (3) **Monster taunts**: when a monster occupies the tile directly in front of the player, a one-line flavour text is shown in a dim muted style between the 3-D viewport and the footer — each monster kind has two taunts selected by floor-number parity (e.g. Spider: "It clicks its chelicerae..." / "A web glistens in the darkness"; Dragon: "RAAAAAWR!" / "Smoke curls from beneath the door"). (4) **Persistent best-score tracking**: `best_score` is recorded via the score store on game over (separate key from the floor-depth record) and shown on the title screen as "Best depth: FN  |  Best score: NNNNN" and on the game-over screen. (5) **Ring of Speed item** (`R` in floor layouts): picking it up sets a 30 s `speed_ring_timer` on the player; while active a ⚡Ns indicator appears in the HUD inventory row; the timer ticks down in game-dt, surviving debug step-mode correctly. Placed on floor 6 in the east wing (accessible after unlocking the new locked door). (6) **Improved floor layouts**: floor 3 now has three Archers in narrow arrow-slit corridor positions (replacing the spider at row 1 and bat at row 3); floor 4 gains a treasury room (north-east, cols 11-17) with Sword + Map_scroll guarded by two Skeletons and a Wraith; floor 6 adds a locked door (`D`) at the entrance to the east wing (stairs side) requiring the key already present in the centre of the floor, creating a meaningful locked-gate puzzle before floor 7.

### Fixed

- **`Input_parser`: recognise PageUp / PageDown / Home / End CSI sequences**: `parse_key` and `peek_key` now handle `ESC[5~` (PageUp), `ESC[6~` (PageDown), `ESC[H` / `ESCOH` / `ESC[1~` / `ESC[7~` (Home), and `ESC[F` / `ESCOF` / `ESC[4~` / `ESC[8~` (End). Previously these sequences fell through to `Unknown`. The `key_to_string` and `is_nav_key` helpers are updated accordingly. (#132)

- **MIAOU Force — persistent FB and smaller framebuffer cap**: same `FB.create()` per-frame issue fixed as in Links. The `FB.t` is now created once in `Inner.state` and reused; the framebuffer cap is reduced from 240×60 to 160×48 cells (~96 KB ANSI per frame vs ~360 KB, 73% reduction) to prevent terminal write-buffer saturation at high frame rates.
- **MIAOU Force — authentic R-Type Force pod mechanics**: the original `f`-key front/back toggle was not how R-Type works. The Force pod now behaves like the arcade original: pressing `d` while docked launches it forward at ~75 px/s screen-relative velocity; it coasts and gradually halts at a fixed world position as the level scrolls past. Pressing `d` again while floating toggles recall mode — the Force accelerates back toward the ship. Docking front/back is now fully automatic based on which side the Force contacts: arrive from the right of the ship → front dock; arrive from the left → back dock. To put the Force on the back, use the authentic manoeuvre: launch it, fly your ship past it, then recall or let it auto-attach from behind. The `f` key binding and `flip_force` helper are removed.
- **MIAOU Links polish round 2**: six visual and UX improvements. (1) **Hole preview**: each new hole opens with a 2-second animated preview screen (skippable with Space) that shows the full course top-down — no ball — with a double-pulsing ring around the cup, a pulsing "TEE" marker at the start position, and a footer with wind direction, club distances, and the hole number/par. `Hole_preview` is a new mode variant; `begin_hole` and `begin_run_hole` both go through it. (2) **Putting green grain**: Green and Cup tiles now have a subtle alternating ±8 brightness stripe on the G channel every 4 pixel rows, simulating surface grain and making the green feel distinct from fairway. (3) **Distance-to-cup HUD**: the aim line during Aiming/Powering now shows `DIST: XXyd` (scanning the hole layout for the Cup tile, then scaling by a tiles-to-yards factor). (4) **Ball landing dirt burst**: the particle burst when the ball lands is more impactful — brown/tan hue-3 particles at speed 8.0 / life 0.4 s (was generic hue with less punch). (5) **Hole-clear screen**: redesigned to show "HOLE COMPLETE!", a colour-coded par-comparison label (ALBATROSS in cyan / EAGLE in gold / BIRDIE in green / PAR in white / OVER PAR in red), and a running per-hole scorecard for both run and classic modes. (6) **Wind in preview**: wind speed and cardinal direction are shown prominently in the preview footer so the player can plan before teeing off.
- **MIAOU Links freeze during Powering state (two-phase fix)**: the `Framebuffer_widget` was created fresh every frame inside `View.render`, so its `render_cache` was always `None` and the full Octant encoder ran on all 12,000 cells each frame. Additionally, 300 KB of ANSI output per frame at ~60 fps saturated terminal write buffers and caused exit-137 kills. First fix: (1) the `FB.t` is now allocated once in `Inner.state` and reused; (2) persistent framebuffer. Second fix: residual freeze ("gauge fills but eventually freezes") was still caused by ~540 KB of GC pressure per render (build_frame bytes + FB.blit bytes + ANSI buffer/output). Fix: framebuffer cap tightened to 120×32 cells (was 200×60) so each frame is ~90 KB ANSI, and the render throttle doubled to 100 ms (10 fps) capping throughput to ~0.9 MB/s. Also removed a spurious `build_frame` call in the `Hole_clear` branch that allocated 90 KB only to discard the result.

### Changed

- **MIAOU Force polish round 3**: visual flair and better feel. (1) **Score multiplier system**: killing enemies within 1.5 s of the previous kill increments a combo counter (capped at 5×); all kill scores are multiplied by the current combo, which resets when the window expires. The HUD shows `×N` when the multiplier is active. (2) **Boss health bar**: while the boss is alive a centred red fill bar (60% of frame width, white border) with a "BOSS" label appears at the bottom of the playfield; the fill flashes white when the boss takes a hit. (3) **Charge beam glow**: `Bullet_beam` bullets now render a 5-row horizontal glow strip — bright cyan/white at the centre row fading to dim teal at ±2 rows — making the charged shot visually distinct from regular fire. (4) **Shielded enemy ring**: the pulsing shield indicator grows to radius ~6, with 8 points (cardinal + diagonal) and a smooth sine-wave pulse driven by the enemy's phase timer. (5) **Level-clear cinematic**: boss death transitions into a new 2-second `Level_clear_anim` mode that overlays fading white flash + gold "LEVEL N CLEAR!" text + score onto the still-running particle burst, before auto-advancing to the confirmation screen; Space/Enter skips it. (6) **Pickup magnet line**: when a power-up is within 30 px of the ship, a 4-pixel dashed yellow guide line points from the pickup toward the player as a subtle collection hint. Extended the pixel font with `B`, `O`, `C`, `E`, `A`, `R`, `V`, `N`, `I`, `T`, `!`, `*`, and space characters to support the new on-screen labels.

- **MIAOU Crypt polish round 2**: six polish improvements that make the dungeon feel like a real game. (1) **Monster AI overhaul**: spiders and skeletons now actively path toward the player instead of standing still; monsters 2+ tiles away occasionally strafe (25% chance) to break symmetrical approach lines; when a monster's target tile is blocked by another monster it sets a 0.5 s `wait_t` yield timer instead of hardlocking, eliminating the "monster wall" pileup. (2) **Archer enemy kind**: a new `Archer` monster fires grid-level arrows (bright cyan dot) toward the player every 2 s from 3+ tiles away; arrows advance one tile per 0.25 s and disappear on hitting a wall or the player (dealing 2 HP); at close range archers strafe sideways. Archers placed on floors 3, 5 and 7 replacing one melee monster each. (3) **Floor-transition animation**: stepping on stairs no longer jumps instantly to `Floor_clear`; instead a 0.8 s `Descending_anim` overlay shows a blinking "DESCENDING... floor N → floor N+1" flash, then auto-transitions. (4) **Map Scroll item**: a new `Map_scroll` pickup (`M` in floor layouts) grants `has_full_map`, revealing all tiles of the current floor in the minimap at once; before pickup only the 3×3 neighbourhood around the player is visible. Placed on floors 2 and 4. (5) **Speed-run score bonus**: a `steps_on_floor` counter resets each floor; clearing a floor in ≤ 12 steps applies a `speed_mult = 2` multiplier to all subsequent kill scores on that floor, with a "+SPEED" popup at the player position. (6) **Enhanced wall shading**: a `stripe_factor` in the raycaster boosts brightness by 15% on every 4th tile-column position, mimicking stone block seams; floors 5–6 (Lich domain) receive a red tint and floor 7 (Dragon arena) receives an amber tint, making each danger zone visually distinct.

- **MIAOU Links polish round 1 — Roguelite Greens**: the chill golf demo grows a roguelite framework on top of the existing top-down golf, plus a major aim-arrow visual upgrade. The aim arrow is now a thick, multi-cell shaft (3-pixel-wide overlapping discs with a darker outline) topped by a filled triangular arrowhead (~9 px deep, ~6 px half-width), drawn in bright contrasting yellow/amber by default and shifting through a green→yellow→red gradient during `Powering` (driven by `meter01`). Arrow length is proportional to the active club's `effective_max_speed` so Driver visibly draws long, Putter draws short; the **Eagle Eye** perk extends the arrow further and warms its colour. The HUD now exposes an angle/yardage readout (`Aim:037°(Driver,~210y)`) recomputed every frame from the aim angle and current power-meter fraction. A new `run` field on `Model.t` carries the roguelite state: a randomly-drawn 9-hole sequence (`Courses.boss_indices` seeds every 3rd hole from a pool of three boss layouts), a `stamina` budget that decrements with every stroke (and water penalty), persistent `coins` stored under `$XDG_STATE_HOME/miaou/miaou_links_coins.score`, and a list of `active_perks`. The state machine extends with `New_run_intro | In_shop | Perk_pick | Boss_intro | Run_complete | Run_failed`. Pre-run **shop** lists 5 random perks at hand-tuned coin costs ($12-$30); between holes a **perk-pick** screen offers 3 random perks. The **12-perk catalogue** ships `+1 Stamina`, `Wind Breaker` (wind ×0.5), `Sand Legs` (sand friction 4.0→0.9), `Power Swing` (Driver max speed +20%), `Putter Genius` (Putter speed scale 0.95 — narrower spread), `Lucky Bounce` (25% redirect on water), `Stroke Saver` (+1 stamina every 4th hole), `Coin Magnet` (+50% coins on run completion), `Eagle Eye` (longer arrow + 0.85-tile cup capture radius), `Storm Caller` (wind ×1.8), `Birdie Bonus` (+$2 per birdie), `Iron Will` (one-shot first-water save). The hole pool grows from 6 to **14 hand-authored layouts** in `courses.ml` (Hole 7 island green, Hole 8 narrow chute, Hole 9 BOSS triple-hazard par-5, Hole 10 sweeping S-curve, Hole 11 BOSS water carry, Hole 12 BOSS triple-bunker green, Hole 13 wide green warm-up, Hole 14 hourglass fairway). Visuals gain a pulsing **wind indicator** widget at the top-left of the playfield (ring + arrow showing per-shot wind direction and magnitude), an oversize **stamina bar** drawn directly into the framebuffer above the playfield (green/yellow/red banding), and a heavier water-splash particle effect (24 + 12 outer-ring particles per hit). The HUD adds compact perk glyphs (`[Pw Sl Ee]`-style row), run-progress (`Hole 3/9 * BOSS NEXT`), stamina bar (`Stam [###...] 18/45`), and live coin total. Title screen shows `Coins: $X · Best run: +N under par · Best classic round: +N under par`. End-of-run rewards: 5 coins per hole completed plus 4 coins per under-par stroke, multiplied by ×1.5 if Coin Magnet is active. Run failure on stamina = 0 transitions to `Run_failed`. The legacy 14-hole tour stays available via `O` (`tOur`) on the title since `T` is reserved by the demo-page wrapper for the tutorial modal. The four protected files (`matrix_ansi_parser.ml`, `framebuffer_widget.ml`, `terminal_caps.ml`, `widgets.ml`) are untouched; pixel mode still resolves through `Arcade_kit.Pixel_mode.resolve` (Octant default, `MIAOU_LINKS_PIXEL_MODE` override). Important fix: `Random.State.int` bound was capped at `0x3FFFFFFF` (instead of `0x7FFFFFFF`) so the run-seed RNG no longer raises `Invalid_argument`.
- **MIAOU Crypt polish round 1**: the raycast dungeon-crawler doubles in scope. The dungeon now stretches across **seven hand-authored floors** in `floors.ml` (entry hall, twisting corridors, key/door puzzles, monster-dense kill rooms, a Lich boss arena on floor 5, a final dragon arena on floor 7) with new tile types (locked doors, a final artifact tile, lit and unlit floor variants). Two new monster kinds join Spider/Skeleton/Bat: **Wraith** (semi-transparent magenta drift, AI seeks the player slowly), **Lich** and **Dragon** (boss-class — AI in `tick_boss` casts telegraphed bullet patterns down the corridor, requires multiple hits, drops the artifact on death). Items beyond the existing key: **Health potion** (`+5` HP, max 20), **Torch** (extends visibility distance and warms the wall palette for ~30 s via a `torch_timer` countdown), **Sword upgrade** (`+1` melee damage, persistent for the run, stacks across pickups). HUD on `Exploring` shows compact icons for keys 🗝, potions ⚗, torches 🔥, sword bonus ⚔ alongside HP, current floor (`F1/7`), best floor reached, and score. Bosses have a dedicated **kill cinematic** (`Boss_kill_cinematic` mode): full-intensity flash, magnitude-1.5 shake, 96-particle hue-9 burst, and a "<NAME> SLAIN — ARTIFACT FOUND" overlay that flashes 4× per second over the still world frame, then auto-transitions to `Floor_clear` after 2.5 s (skippable with Enter/Space/Esc). Damage popups (player and monster sides) use a hand-rolled 3-tile-wide pixel-digit font over a fixed-size pool, mirroring the Force score-popup design (no per-frame allocation). A `MIAOU_CRYPT_DEBUG=1` env var enables a deterministic step mode: `n` advances 1 frame, `N` advances 10, `b` advances 60; the HUD shows `[TURN-BASED frame N pending=K n/N/b]` so an agent driving via tmux can step monster cooldowns and cinematic timers exactly. Wall raycaster gains **6-step posterised distance shading** plus an extra dim on E/W faces; floor and ceiling use a vertical gradient (cool blue-grey above the horizon, warm umber below) that warms further while a torch is lit. The four protected files (`matrix_ansi_parser.ml`, `framebuffer_widget.ml`, `terminal_caps.ml`, `widgets.ml`) are untouched; pixel mode resolves through `Arcade_kit.Pixel_mode.resolve` (Octant default, `MIAOU_CRYPT_PIXEL_MODE` override).
- **MIAOU Force polish round 2**: three full levels, persistent weapon upgrades, and a level-select screen. Levels 2 ("Asteroid Belt") and 3 ("The Core") ship as hand-authored event streams in `levels.ml` with distinct enemy mixes: level 2 packs `splitter_cluster`, `dense_wave`, `fortress_group`, `strafer_quad`, `mine_corridor`, and shielded duo encounters, and hands the player a `Power_up_missile` and `Power_up_force_upgrade` pickup before a 40-HP dual-core boss at world_x 1700; level 3 introduces pairs of `Laser_emitter` enemies (charge 1.5 s → fire a full-height horizontal laser sweep), `gauntlet` corridors mixing mines and lasers, `splitter_ambush` and `mine_laser_wall` set pieces, and a 50-HP Bydo-style final boss at world_x 1800. A persistent `weapon_state` record on the player carries four upgrades across lives within a level: `speed_level` (stacks up to 3 ×, each +25 % movement), `has_missile` (fires 2 diagonal missiles per shot via `fire_missiles`), `has_force_upgrade` (Force pod fires 3 bullets and has a wider hitbox), and `has_shield` (absorbs one hit, flashes, then deactivates until next pickup). `apply_powerup` handles all five pickup kinds (`Power_up_speed`, `missile`, `shield`, `force_upgrade`, plus existing `Power_up_extra_life`). The `Level_select` screen (press `S` from title or level-clear) shows the three levels with Up/Down cursor and Enter to start fresh from any level — useful for practice runs. `page.ml` gains `start_level_n` to carry score+weapons into the next level; `handle_key_level_clear` now advances to level N+1 (or records the all-clear score and returns to title) rather than ending the game. Entity and bullet caps raised (128 enemies, 128 player bullets, 160 enemy bullets, 1024 particles) to support the denser level-3 encounter layouts. The four protected drift files are untouched.
- **MIAOU Force polish round 1**: the R-Type-style demo gains a deterministic turn-based debug mode and a wave of content polish. Setting `MIAOU_FORCE_TURN_BASED=1` starts the game paused and gates simulation `dt` on explicit step keys (`n` advances 1 frame, `N` advances 10, `b` advances 60), with a `[TURN-BASED frame N]` HUD overlay so an agent driving the game from tmux always knows which frame they're inspecting. All gameplay keys (Space, arrows, `d`, `f`, Esc) are buffered between steps; Space presses accumulate fire-buffer frames so the charge beam can be wound up across many `n`/`b` steps. Three new enemy kinds round out the variety: **Strafer** (fast, sharp zigzag, magenta diamond sprite), **Shielded** (multi-hit purple core protected by a pulsing cyan shield ring that absorbs hits before damage applies), and **Mine** (stationary spiked bomb that lights a 0.18 s fuse when shot, then detonates and chain-triggers any other mine within ~10 px). The boss is now a multi-phase fight: phase 1 (>50 % HP) fires an 8-bullet rotating radial spread, phase 2 (25–50 % HP) fires aimed pairs plus a single arc-bending homing bullet (`Bullet_homing`, steered toward the player each frame at constant speed), phase 3 (<25 % HP) fires a wide 5-bullet desperate burst aimed at the player; each transition emits a particle burst, screen shake, and a palette shift on the boss sprite. Holding (or, in turn-based mode, repeated tapping of) Space past a 0.85 s charge threshold powers a **charge beam** — five vertically stacked `Bullet_beam` bullets that pierce through grunts/divers and deal 2 damage; the ship's nose glows brighter through three posterised palette steps as charge approaches the threshold. Boss death triggers a 1.5 s **slow-mo cinematic** (gameplay `time_scale = 0.3`, screen-shake, full-intensity flash, 120-particle burst) before transitioning to the new `LEVEL CLEAR / BOSS DEFEATED` overlay. Killed enemies spawn **score popups** ("+100", "+250", …) drawn with a tiny 3×5 hand-rolled pixel-digit font; popups float upward and fade over 1.1 s from a fixed-size pool of 32 slots (no per-frame allocation). Enemy entity caps raised to 96 to accommodate mine fields and shielded squadrons. `levels.ml` now interleaves strafer pairs, shielded duos, and 5-mine fields with the existing grunt V-formations, dive columns, and turret pairs; the boss arrives at world_x = 1600 (~62 s in). Internals: collision resolution moves through a unified `damage_enemy` helper that handles shields, hit-flash, kill-score, popup spawn, explosion burst, and the boss-death cinematic in one place; `dist2`, `enemy_radius`, and `burst_explosion` are hoisted above the enemy AI so the new mine-chain logic can call them. The four protected files (`matrix_ansi_parser.ml`, `framebuffer_widget.ml`, `terminal_caps.ml`, `widgets.ml`) are untouched; pixel mode still resolves through `Arcade_kit.Pixel_mode.resolve` (defaulting to Octant); `Demo_page.MakeSimple` wiring is intact.

### Added

- **MIAOU Links demo (`example/demos/miaou_links/`)**: a chill top-down golf game registered in the gallery's `Games` group. Six hand-authored holes (three par-3, two par-4, one par-5) live in `courses.ml` as ASCII tile maps using the legend `# ~ . R T G S C` for walls / water / fairway / rough / tee / green / sand / cup; layouts include a dogleg, a water-carry, and a sand-trap risk-reward green. The page implements a `Title | Course_select | Aiming | Powering | In_flight | Hole_clear | Card_summary` state machine in `model.ml` with continuous (x, y, z) ball physics: per-tile friction (fairway 0.6/s, green 0.2/s, rough 1.5/s, sand 4.0/s), a small parabolic flight `z` driven by the chosen club's launch angle (driver / iron / wedge / putter — different max distances and arcs), a per-shot wind shifted ±10% from the hole's base wind, water-tile splash that replays the prior position with a +1 stroke penalty, and cup capture when the ball is within 0.6 of the cup centre at low speed. Controls: `←` / `→` rotate aim, `[` / `]` fine-rotate aim, `Space` first press locks aim and starts the bouncing power meter, `Space` again swings, `c` cycles club, `Esc` steps back through gameplay → course-select → title → launcher. The renderer in `view.ml` is a top-down framebuffer painted with a soft pastel palette (deliberately unlike Force/Crypt neon): `Arcade_kit.Hue.grass`-shaded fairways with cheap Lambert-ish hill undulation, `Hue.sand` bunkers, `Hue.ice` deep-blue water with a time-based sine shimmer, a small 3-D ball sphere with a streaming pixel trail in flight (via `Arcade_kit.Particles` over a 256-slot pre-allocated pool, plus water-splash and cup-celebration bursts), an aim arrow during `Aiming` and a colour-graded power meter overlay during `Powering`, and a thin pulsing ring around the cup. The framebuffer is capped to 200×60 cells; pixel mode resolves through `Arcade_kit.Pixel_mode.resolve` (defaulting to `Octant`, overridable via `MIAOU_LINKS_PIXEL_MODE`). The best (most-under-par) full round persists across sessions via `Arcade_kit.Score_store.record ~demo:"miaou_links"`.
- **MIAOU Crypt demo (`example/demos/miaou_crypt/`)**: a pseudo-3-D first-person dungeon crawler registered in the gallery's `Games` group. The renderer is a from-scratch DDA raycaster (`raycast.ml`) that casts one ray per framebuffer column, walks the tile grid up to 32 cells, and returns the perpendicular wall distance, the wall side (N/S vs E/W), and a tile-relative texture coordinate; `view.ml` then draws a vertical wall slice per column with a six-step distance-based shade ramp (closer = brighter, far walls fade to near-black) and a one-step extra dim on E/W faces for cheap fake lighting. Floor and ceiling fill the non-wall pixels with a vertical gradient — cool blue-grey above the horizon, warm umber below. Monsters (`Spider`, `Skeleton`, `Bat`) are billboarded with per-kind silhouettes (round blob / humanoid + head / wide V), depth-tested per column against the wall buffer, and faded by distance using the same ramp. A toggleable minimap (`m`) sits in the top-right and shows the tile grid, monster pins, and the player's pose as an orange triangle. The page implements a `Title | Exploring | Floor_clear | Game_over` state machine over five hand-authored floors in `floors.ml` with walls / locked doors / keys / stairs / a final artifact tile. Controls: `↑`/`w` step forward, `↓`/`s` step back, `←`/`→` turn 90°, `a`/`d` strafe, `Space` attacks an adjacent monster (or unlocks a door if the player carries a key), `Esc` returns to title, `Esc` again to launcher. Damage popups go through `Arcade_kit.Particles` over a 256-slot pre-allocated pool; player hits trigger `Arcade_kit.Screen_fx.flash` with the `lava` ramp; the deepest floor reached persists across sessions via `Arcade_kit.Score_store.record ~demo:"miaou_crypt"`. Framebuffer is capped to 200×60 cells, raycast columns at the framebuffer width (≤ 200 × 2 sub-pixels in Octant), and pixel mode resolves through `Arcade_kit.Pixel_mode.resolve` (defaulting to `Octant`, overridable via `MIAOU_CRYPT_PIXEL_MODE`).
- **MIAOU Force demo (`example/demos/miaou_force/`)**: an R-Type-style horizontal shoot-em-up registered in the gallery's `Games` group. The world auto-scrolls rightward over a two-layer parallax star field plus a perlin-style rocky terrain band rendered into the framebuffer (Octant 2×4 sub-cells via `Framebuffer_widget` and `Arcade_kit.Pixel_mode.resolve` — defaulting to `Octant`, overridable via `MIAOU_FORCE_PIXEL_MODE`). The page implements a `Title | Playing | Level_clear | Game_over` state machine; `Enter` from the title launches the level, `Esc` from gameplay returns to the title, `Esc` again returns to the launcher. Hand-authored `Levels.level1` triggers V-formations of grunts, dive-bombing diver columns, sweeping turret pairs (which fire homing bullets), two power-up pickups, and a 30-HP boss at the one-minute mark. The iconic **Force** module (`d` toggles attached / detached, `f` flips front / back when attached) provides extra forward fire when docked-front, rear fire when docked-back, and absorbs enemy bullets when floating detached at a fixed world position. Three lives by default; set `MIAOU_FORCE_HARD=1` for one-life arcade mode. Particle bursts on every kill use `Arcade_kit.Particles` over a 512-slot pre-allocated pool; boss hits trigger `Arcade_kit.Screen_fx.shake`; boss death triggers `flash`. High scores persist across sessions via `Arcade_kit.Score_store.record ~demo:"miaou_force"`. Entity counts are capped (≤ 64 enemies, ≤ 64 player bullets, ≤ 64 enemy bullets, ≤ 8 pickups) and the framebuffer is capped to 240×60 cells so encoding cost stays bounded on large terminals.
- **Shared `Arcade_kit` (`example/shared/arcade_kit.{ml,mli}`)**: small toolkit used by the gallery's arcade-style demos. `Arcade_kit.Particles` is a pre-allocated ring-buffer particle pool with `spawn` / `spawn_burst` / `tick ~dt ~ax ~ay` / `iter` and zero per-frame allocation in the hot path. `Arcade_kit.Hue` ships seven hand-snapped 12-stop xterm-256 ramps (cyan / magenta / amber / sand / lava / ice / grass) plus matching `(r,g,b)` approximations for pixel-buffer rendering, dodging the smooth-gradient banding that hits Octant render mode. `Arcade_kit.Screen_fx` exposes `flash` and `shake` overlays decaying over a duration. `Arcade_kit.Score_store` reads/writes per-demo high scores under `$XDG_STATE_HOME/miaou/<demo>.score` (best-effort, silent on IO error). `Arcade_kit.Pixel_mode.resolve` returns `Caps.Octant` by default with env-var override — never auto-detects, since auto-Sixel produces fragmented output on Konsole.
- **Solar System demo (`example/demos/solar_system/`)**: an animated visual of the Sun and the eight planets at their real orbital and rotational periods (Mercury 88 d / Earth 365.25 d / Neptune 60 190 d for orbits; Earth 1 d / Jupiter 0.41 d / Venus 243 d for axial spin). Distances are square-root-compressed and radii cube-root-compressed so even Mercury stays visible while Jupiter still feels imposing. The Sun has a quadratic radial glow over a white-hot core, every planet is filled with smooth Lambert shading from the Sun's direction (with rim light + a small bright spin marker that orbits the limb to show rotation), Saturn carries a thin ring, orbit rings are dimmed so they don't fight the planets, and a deterministic sparse star field sits behind everything. A right-side panel (toggleable with `Tab`) shows simulated time, the speed multiplier (`1`–`5` set ×1 / ×10 / ×100 / ×1000 / ×10 000 days per real second), each planet's current orbital phase in degrees, and inline help. `Space`/`p` pauses, `o` toggles orbit rings, `l` toggles labels, `r` resets time. The pixel mode is auto-detected (`Sixel` on capable terminals, `Octant` otherwise) and overridable via `MIAOU_SOLAR_PIXEL_MODE`. Registered under the gallery's `Showcases` group.
- **Geo Quiz demo (`example/demos/geo_quiz/`)**: a city-locator showcase game registered in the gallery's `Games` group. The menu mode features a colour-shaded rotating 3-D globe with filled continents and Lambert shading anchored to a fixed-screen sun (Octant 2×4 sub-cell rendering — sand-toned land, navy ocean, paler limb), a five-tier difficulty selector (capitals of large countries → all capitals → cities >1 M → cities >100 K → cities >15 K), and embedded `coastline.bin` (Natural Earth `ne_50m`, 60 K points), `landmask.bin` (rasterised `ne_50m_land` polygons at 720×360, 32 KB) and `cities.bin` (filtered GeoNames cities15000, 33 K cities) blobs. Round mode draws a colour, aspect-corrected equirectangular world map (Octant sub-pixels via `Framebuffer_widget`); the player moves a crosshair with arrow keys, `Shift+arrow` for big jumps, or a mouse click, and presses `Enter` to lock in the guess. A 30 s `Timer.set_timeout` auto-locks a zero-score guess on expiry. Scoring combines a haversine distance score (`max 0 (1000·(1 − d/max_d))`, with `max_d = 5000 km` for tiers 1–3 and `2500 km` for tiers 4–5) and a remaining-time bonus capped at 300, with the round-end map showing both the truth and guess pins; the game-over screen renders a per-round bar chart. Two-tier caching (a per-resolution background-bytes cache plus a final-ANSI string cache keyed on cursor + truth + size) keeps input latency low even on large terminals; map and globe sizes are capped to bound encoding work, and the layout adapts to compact / standard / wide breakpoints.
- **Reusable `Globe_widget` (`Miaou_widgets_display.Globe_widget`)**: standalone rotating-globe widget used by the Geo Quiz menu. Public API: `create ?is_land ~coastline ()`, `advance ~dt`, `set_rotation ~yaw ~pitch`, `yaw`, `render ~cols ~rows`. Renders into an `Octant_canvas`, fills the inscribed disc by inverting the camera-space rotation per cell, looking up a caller-supplied land/sea classifier, and applying separate sand and ocean Lambert ramps to a fixed screen-space sun. Overlays equator and meridian graticule, then projects coastline points with backface culling (z < 0). Also exposes `latlon_to_xyz` and `haversine_km` helpers for callers that need the same sphere math. Self-registers via `Miaou_registry`.
- **Reusable `Prompt` helpers (`Miaou_core.Prompt`)**: thin wrappers over `Modal_manager.confirm_with_extract` exposing `Prompt.confirm`, `Prompt.input`, and `Prompt.select` so application code no longer has to assemble the modal-page boilerplate by hand. Each helper takes an `on_result` callback receiving the user's choice (or `None`/`false` for cancellation) and renders the matching widget centred. Pure result-mapping helpers (`confirm_outcome`, `input_result`, `select_result`) are exposed for unit testing.
- **Gallery demos for `Responsive`, `Select_widget`, inline mode, and inline + responsive composition**: four new entries under `example/demos/` exercising recently-added building blocks. `responsive/` swaps between 4-column / 2×2-grid / stacked layouts as the terminal narrows. `inline_select/` puts a `Select_widget` inline on a page rather than as a centred dialog. `inline_cli/` is a tiny "list current directory" page that, when launched via its `run.sh` (`MIAOU_INLINE_MODE=1 dune exec …`), runs without taking over the alternate screen — its output stays in scrollback after quit. `inline_color_picker/` combines both: a 16-colour swatch grid that adapts to width and runs in inline mode via its own `run.sh`.
- **User keymap overrides (`Miaou_core.Keymap_config`)**: optional line-based config file letting end users rebind page actions without touching application code. Parses entries of the form `page=<name|*>  key=<key>  action=<id>` (with `#` comments and blank lines), folds key spellings (`ctrl+x`, `Ctrl-X`, `c-x` → `C-x`; `shift+tab` → `Shift-Tab`) so configs are case-insensitive, and resolves `page=*` as a global fallback after page-specific rules. Default lookup path is `$MIAOU_KEYMAP_FILE`, then `$XDG_CONFIG_HOME/miaou/keymap.conf`, then `~/.config/miaou/keymap.conf`; a missing file yields an empty keymap silently. The dispatch wiring (consulting overrides before each page's keymap) is intentionally deferred to a follow-up so pages can opt in by exposing named actions.
- **File browser icons + filetype colours**: `File_browser_widget` now prefixes each entry with a Unicode glyph keyed by file extension (📁 for directories, 🐫 for OCaml, 🦀 for Rust, 🐍 for Python, 📦 for archives, 📝 for markdown, etc.) and applies a per-extension 256-colour foreground. Setting `MIAOU_NERD_FONT=1` switches to a Nerd Font glyph set for terminals using a Nerd-patched font. The icon table lives in the new `Miaou_widgets_layout.File_icons` module and is reusable from any custom widget that lists files.
- **`Responsive`**: a tiny utility for picking among layouts based on terminal width. `Responsive.pick` walks an ascending list of `{max_width; layout}` breakpoints and returns the first match (mobile-first ordering). Layouts can be `Flex_layout.t`, `Grid_layout.t`, or anything else — the module is fully polymorphic.
- **Inline mode (`MIAOU_INLINE_MODE=1`)**: a new run mode for the matrix driver in which the TUI does not switch to the alternate screen. The rendered frame stays in the terminal scrollback after exit, making it easy to review what a short-running TUI produced. Mouse tracking is suppressed in this mode (since copy/paste matters more than mouse interaction for inline tools). Programmatic configuration via the new `Matrix_config.inline_mode` field and `Matrix_terminal.set_alt_screen` / `Terminal_raw.set_alt_screen`. *Note: this minimum-viable mode renders starting from the top of the viewport; an anchored partial-row mode (rendering only N rows below the current cursor) is planned as a follow-up.*
- **`Wizard_widget`**: a generic multi-step wizard, polymorphic over user state. Each step provides its own `render`, `validate`, and `on_key`; the wizard owns navigation (Enter advances when validation passes, Shift+Tab returns, Esc cancels), breadcrumb chrome, and finished/cancelled state. Adds `example/demos/wizard/` with a 3-step "pick backend → name it → review" flow.
- **`Textarea_widget` undo / redo**: the multi-line editor now supports `Ctrl+Z` (undo) and `Ctrl+Y` / `Ctrl+Shift+Z` (redo). Consecutive character inserts are coalesced into a single undo step so a typed word is reverted in one go; backspace, delete and newline get individual steps. The undo/redo stacks are capped at 200 entries each. New API: `Textarea_widget.undo`, `redo`, `can_undo`, `can_redo`.
- **`Tree_widget` keyboard navigation**: the tree widget now responds to `Up`/`Down`/`Left`/`Right`/`Enter`/`Home`/`End`, tracks expansion state per path, renders an expand marker (▾/▸ with ASCII fallback) and highlights the cursor row via the theme's selection style. Previously the widget rendered statically. New helpers `Tree_widget.expand_all`, `collapse_all`, `is_expanded`, and `flatten_visible` are exposed.
- **Web Viewer for headless sessions** (`Web_viewer`): standalone HTTP+WebSocket server that runs alongside the headless driver, letting a human observe an AI agent's TUI session in real time via a browser. Serves the existing xterm.js viewer page, broadcasts ANSI frames to all connected viewers, and tracks terminal dimensions so xterm.js resizes to match the headless render size. New viewers receive the current dimensions and last frame on connect (no blank screen).
- **`on_frame` callback in headless runner**: `Headless_json_runner.run` and `Runner_tui.run` accept an optional `?on_frame:(rows:int -> cols:int -> string -> unit)` callback invoked with the raw ANSI frame and terminal dimensions on every frame emit. This enables external consumers (like `Web_viewer`) to observe frames without modifying the headless protocol.
- **Viewer auto-reconnect**: the xterm.js client (`client.js`) now automatically reconnects with a 2-second retry when a viewer WebSocket disconnects, surviving server restarts without requiring a manual browser refresh.
- **Viewer dimension sync**: when the headless driver's terminal size changes, a `{"type":"dimensions","rows":R,"cols":C}` JSON message is sent to all viewers. The client resizes xterm.js to match; FitAddon auto-fit is disabled for viewers so the terminal size is controlled by the server.

### Added

- **Octant rendering mode** (`Octant_canvas`): high-resolution chart rendering using Unicode 16 octant block characters (2×4 sub-cell pixels per character cell). Gives 8× resolution compared to ASCII mode with per-cell color support. Octant mode is available on `Sparkline_widget`, `Line_chart_widget`, and `Bar_chart_widget` via a new `~mode:Octant` parameter.
- **Framebuffer widget** (`Framebuffer_widget`): direct pixel/cell-based drawing surface embeddable in any layout slot. Supports both character-cell and sub-cell (Octant) pixel addressing, making it easy to build custom visualisations, games, or image renderers.
- **Terminal capabilities detection** (`Terminal_caps`): detects whether the connected terminal supports Unicode 16 octant characters. Used internally by the Octant rendering mode to fall back gracefully on older terminals.
- **Periodic viewer refresh daemon** (headless runner): when an `on_frame` callback is registered (e.g. by `Web_viewer`), a background Eio daemon fiber re-renders the screen every 200 ms and broadcasts the updated frame. This keeps live viewers up-to-date during agent idle periods (timers, async I/O, spinners) without requiring a key press or tick.
- **"Framebuffer & Octant Charts" demo** added to the gallery, showcasing both the `Framebuffer_widget` and Octant chart modes side-by-side.

### Fixed

- **Viewer daemon race condition**: the periodic viewer-refresh fiber previously called `idle_wait` each iteration, which allowed it to interleave with the command handler's own `idle_wait` and concurrently mutate shared page-state (double-ticking clocks/timers). The daemon now reads the cached screen content directly via `HD.Screen.get` without advancing any state.
- **Web driver Tab key**: `ev.preventDefault()` is now called for all recognized keys in the web client's keyboard handler. Previously, Tab (and other browser-reserved keys like F5) were forwarded to the server but also processed by the browser for focus navigation / page reload. Tab now reaches the Miaou application correctly.

## [0.4.2] - Unreleased

### Fixed

- **Canvas ANSI row isolation**: `Canvas.to_ansi_with_defaults` now always emits an SGR sequence at column 0 of every row, making each row self-contained. Previously, style was carried across row boundaries as an optimisation; this caused `apply_bg_fill` to bleed the wrong background into the first character of rows where style happened to carry unchanged from the previous row.
- **Canvas widget fills full terminal height**: Miaou Invaders (and any `Canvas_widget` page) no longer shows black bars below the canvas on tall terminals. The 36-row cap on the canvas height has been removed so the game scales to the full terminal height.
- **Matrix driver scrub flicker**: `force_render` is no longer called from the main loop (neither on modal transitions nor during periodic scrub). Both cases now only call `mark_all_dirty`, letting the render domain (the sole terminal writer) pick up the change within one frame. This eliminates the interleaved-write race that caused visible flicker.
- **Miaou Invaders background**: All `draw_text` calls in the Invaders demo now carry an explicit `bg` matching the current game or HUD background. Previously, entities drawn with `bg=-1` clobbered the `fill_rect`-painted background, producing black horizontal bars wherever sprites appeared.
- **Periodic scrub interval**: Default `scrub_interval_frames` reduced from 30 frames (0.5 s at 60 fps) to 300 frames (5 s), making the occasional full-refresh nearly imperceptible.

## [0.4.1] - Unreleased

### Fixed

- **Table row selection highlighting**: Full row background now displays correctly when `selection_mode = Row`. Previously, only border characters (vertical separators) showed the selection color due to ANSI reset codes from `themed_border` clearing the selection background. Now, border styling is skipped for selected rows, allowing the full row to inherit the selection background color.

## [0.4.0] - Unreleased

### Breaking Changes

- **Box_widget border style**: added `None_` to `Box_widget.border_style` for borderless containers. Pattern matches on `border_style` may need a new case.

### Added

- **Cascading style system** (`miaou_style`): semantic styles + CSS-like selectors with effect-based context (`Style_context`).
- **Theme JSON support** with discovery/merge rules and optional validation for low-contrast fg/bg combinations.
- **Built-in themes** (`Builtin_themes`): 11 popular themes included directly in the library:
  - Dark: catppuccin-mocha, dracula, nord, gruvbox-dark, tokyonight, opencode, oled
  - Light: catppuccin-latte, nord-light, gruvbox-light, tokyonight-day
  - `opencode` and `oled` themes use borderless style for a clean, minimal look
  - `oled` theme features true black background (#000000) with soft pastel colors for OLED screens
- **Theme registry API**: `Builtin_themes.list_builtin()`, `get_builtin(id)`, `is_builtin(id)` for discovering and loading built-in themes.
- **Smart theme loading**: `Theme_loader.load_any(name)` checks built-in themes first, then user themes; `list_all_themes()` returns combined list.
- **Style system demo** (`miaou.style_system-demo`) with runtime theme switching and contextual styling.

### Changed

- **Widget theming**: widgets now use semantic themed styles; containers fill contextual backgrounds across full line width.

### Fixed

- **Theme JSON parsing**: tolerant parsing for partial style objects, multiple color formats, and string border styles.

## [0.3.2] - Unreleased

### Added

- **Textarea widget** (`miaou_widgets_input.Textarea_widget`): multiline text input with cursor navigation, line joining, and scroll support. Use Alt+Enter to insert newlines.
- **Left-bordered box** (`Widgets.render_left_border_box`): display helper for context/quote blocks with colored left border and optional background.
- **Blocks spinner style** (`Spinner_widget.Blocks`): animated spinner with size+color gradient progression trail, configurable direction and block count.
- **Alt+Enter key parsing** (`Input_parser.AltEnter`): universally-supported newline insertion key for textarea widgets.
- **Mouse helper module** (`Miaou_helpers.Mouse`): utilities for parsing mouse events (clicks, drags, wheel) in widgets.
- **Mouse support for widgets**: wheel scrolling and click handling added to:
  - Pager: wheel scroll, click to position cursor (in cursor mode)
  - Select: wheel scroll, click to select item
  - File Browser: wheel scroll, click to select entry
  - Textbox: click to position cursor
  - Textarea: wheel scroll, click to position cursor
  - Tabs: click to select tab
  - Breadcrumbs: click on crumb to navigate
  - Button: click to activate
  - Link: click to navigate
  - Checkbox/Radio/Switch: click to toggle

- **Signal handling control**: optional SIGINT handling via `install_signals'` and `Runner_tui.run` `handle_sigint` option.
- **Per-side border colors** for `Box_widget` to style each edge independently.

### Changed

- **Input parser**: added `AltEnter` key variant for Alt+Enter detection (ESC followed by newline).

### Fixed

- **Matrix driver scrub**: avoid screen clear during periodic scrub to reduce flicker.
- **Terminal raw mode**: disable `c_isig` and ignore SIGINT when not handling it.
- **Mouse interactions**: consistent enable sequence via `/dev/tty`, improved click handling, and double-click support.
- **Pager**: add ANSI reset and wrap-aware scrolling.

## [0.3.0] - Unreleased

### Breaking Changes

- **Navigation API hardening**: `Navigation.pending` now returns `Navigation.nav option` (`Goto of string | Back | Quit`) instead of `string option`, replacing magic strings (`"__BACK__"`, `"__QUIT__"`).
- **Modal navigation callback API**: `Modal_manager.set_pending_navigation` now takes `Navigation.nav` instead of `string`.
- **Page transition hooks**: page transition handler records now expose an explicit `on_back` callback.
- **Matrix IO internals**: `Matrix_io.t` removes legacy polling/drain fields (`poll`, `drain_nav_keys`, `drain_esc_keys`) in favor of a decoupled event queue reader model.

### Added

- **Clock capability** (`miaou_interfaces.Clock`) exposing `dt`, `now`, and `elapsed` thunks to pages/widgets.
- **Page-scoped timers** (`miaou_interfaces.Timer`) with `set_interval`, `set_timeout`, `clear`, and fired-event draining.
- **Animation module** (`miaou_helpers.Animation`) with easing, repeat modes, sequencing, delay, and lerp helpers.
- **Canvas abstraction** (`miaou-core.canvas`) with drawing primitives, border styles, composition, and ANSI rendering.
- **Canvas layers**: `Canvas.compose` and `Canvas.compose_new` for ordered transparent/opaque overlay compositing.
- **Canvas widget** (`miaou_widgets_layout.Canvas_widget`) for embeddable mutable drawing surfaces in layout slots.
- **Runner CLI snapshot mode**: `--cli-output` (plus `--cols`, `--rows`, `--ticks`) for non-interactive stdout rendering.
- **Color documentation**: new `docs/colors.md` plus widget interface docs clarifying ANSI payload formats and precedence rules.

### Changed

- **Matrix driver input architecture**: dedicated Eio reader fiber + mutexed queue; tick loop drains full event batches.
- **Default matrix tick rate** increased to **60 TPS**.
- **Matrix artifact scrubbing** is now configurable via `MIAOU_MATRIX_SCRUB_FRAMES` (set `0` to disable).
- **Example gallery** now includes the renamed **Miaou Invaders** demo, with richer gameplay systems and modularized demo code.

### Fixed

- **ESC parsing robustness**: avoid out-of-bounds exceptions on unknown ESC-prefixed pairs while preserving Escape semantics.
- **Demo overlay/collision consistency** in Miaou Invaders: gameplay coordinate handling stays aligned with canvas size and reserved HUD rows.

## [0.2.7] - 2026-02-07

### Fixed

- **Esc key repeat quitting app after modal close** — Matrix driver now applies a 200ms cooldown after closing a modal with Esc, suppressing spurious Esc events from terminal key repeat that would otherwise reach the page and trigger app exit
- **Footer hints not rendering in Matrix driver** — `key_hints` from pages are now correctly rendered in the footer bar

## [0.2.6] - 2026-02-06

### Added

- **Unified key handling architecture** with `Key_event.result` type:
  - New `on_key` / `on_modal_key` methods return `Handled | Bubble` for composable key dispatch
  - `key_hints` for display-only footer hints (replaces action-bearing `keymap`)
  - All input widgets (`Button`, `Checkbox`, `Radio`, `Switch`, `Textbox`, `Select`, `ValidatedTextbox`) expose `on_key`
  - `Keys.of_string` now accepts aliases: `"S-Tab"`, `"BackTab"` → `ShiftTab`; `"Esc"` → `Escape`

### Fixed

- **Keymap dispatch bypassing `handle_key`** — Drivers now always route keys through `on_key`, fixing Focus_ring Tab navigation when Tab was in page keymap
- **Lambda-term driver Enter key** — Enter now goes through `on_key` like other keys

### Changed

- **BREAKING**: `PAGE_SIG` now requires `on_key`, `on_modal_key`, and `key_hints` methods
- `Demo_page.MakeSimple` functor for demos without explicit `key_hints`
- Legacy `handle_key`, `handle_modal_key`, `keymap` deprecated but still functional

## [0.2.5] - 2026-02-05

### Added

- **Focus Ring widget** (`Miaou_internals.Focus_ring`) for named-slot focus hierarchy:
  - Type-safe focus management with string-keyed slots
  - Automatic wrap-around navigation (next/prev)
  - `handle_key` returns `Handled | `Bubble` for composable key dispatch
  - Ideal for forms, toolbars, and multi-widget layouts

- **Focus Container widget** (`Miaou_internals.Focus_container`) for GADT-based focus management:
  - Type-safe heterogeneous widget containers using extensible GADTs
  - No `Obj.magic` - full type safety with witness pattern
  - Nested container support for complex UI hierarchies
  - Generic focus traversal across different widget types

- **Box Widget** (`Miaou_widgets_layout.Box_widget`) for border-decorated containers:
  - Five border styles: `Single`, `Double`, `Rounded`, `Heavy`, `Ascii`
  - Optional colored borders with 256-color support
  - Configurable padding (top, bottom, left, right)
  - Nested box support for complex layouts
  - Automatic ASCII fallback via `MIAOU_TUI_UNICODE_BORDERS=false`

- **Direct_page** (`Miaou.Core.Direct_page`) for simplified page development:
  - Only 3 required functions vs 13 in PAGE_SIG: `init`, `view`, `on_key`
  - Navigation via OCaml 5 effects: `Direct_page.navigate`, `go_back`, `quit`
  - `With_defaults` functor provides sensible defaults for optional functions
  - Reduces boilerplate significantly for simple pages

- **Grid Layout** (`Miaou_widgets_layout.Grid_layout`) for CSS-grid-like layouts:
  - Row and column track definitions with `Fr`, `Px`, `Auto` sizing
  - `grid_area` placement for precise cell positioning
  - Gap support (row_gap, column_gap)
  - Span support for multi-cell items
  - Automatic content fitting

### Fixed

- **Flex layout column alignment** - Short/empty lines in row layouts now properly padded to allocated width, preventing subsequent columns from bleeding into earlier column areas

## [0.2.0] - 2026-02-05

### Added

- **Web driver** (`miaou-driver-web`) for browser-based terminal rendering:
  - xterm.js terminal emulation over WebSocket
  - Controller/viewer architecture for shared sessions
  - Password authentication support
  - 60 FPS configurable refresh rate

- **Path-based roles for web driver** with explicit URL routing:
  - `/ws` — controller WebSocket (returns 409 if slot already taken)
  - `/ws/viewer` — viewer WebSocket (returns 409 if no controller connected)
  - `/viewer` — dedicated viewer HTML page
  - Separate `controller_password` and `viewer_password` authentication
- **Composable `MiaouTerminal(container, options)` JS factory** replacing the IIFE in `client.js`:
  - `wsPath` option (`/ws` or `/ws/viewer`)
  - `onRole`, `onStatusChange`, `onAuthRequired` callbacks
  - `sessionStorage` keys scoped by `wsPath`
  - Returns `{ term, fitAddon, reconnect(pw), getRole() }`
- **Custom HTML pages and extra assets** for the web driver:
  - `~controller_html` and `~viewer_html` optional parameters on `Web_driver.run`
  - `extra_asset` type for serving additional static files (e.g. logos)
  - Both parameters forwarded through `Runner_web.run`
- **Branded gallery pages** with Miaou logo header and role badges:
  - `MIAOU_WEB_VIEWER_PASSWORD` environment variable (falls back to `MIAOU_WEB_PASSWORD`)

### Changed

- Web driver routing refactored: `/ws` always creates controller, `/ws/viewer` always creates viewer (previously role was assigned by connection order on single `/ws` endpoint)

## [0.1.4] - 2026-01-22

### Fixed

- **Modal title rendering** with multiline text
  - Modal titles containing newlines no longer corrupt the layout
  - First line is displayed in the colored title bar with blue background
  - Additional lines are prepended to the modal content body
  - Fixes misaligned borders and improper blue background spanning

## [0.1.3] - 2026-01-16

### Added

- **`enable_mouse` parameter** for `Runner_tui.run` to programmatically control mouse tracking
  ```ocaml
  (* Disable mouse tracking from code *)
  Runner_tui.run ~enable_mouse:false my_page
  ```

### Changed

- Version bump to 0.1.3

## [0.1.2] - 2026-01-16

### Added

- **Optional mouse tracking** via environment variable `MIAOU_ENABLE_MOUSE`
  - Set `MIAOU_ENABLE_MOUSE=0` or `MIAOU_ENABLE_MOUSE=no` to disable mouse tracking
  - Allows traditional terminal copy/paste when mouse tracking interferes
  - See [`docs/MOUSE_CONTROL.md`](./docs/MOUSE_CONTROL.md) for details
- **`Matrix_config.with_mouse_disabled`** helper for programmatic mouse control

### Changed

- Version bump to 0.1.2

## [0.1.1] - 2026-01-16

### Fixed

- **Matrix driver race condition** in dirty flag handling that caused intermittent render artifacts
  - `clear_dirty` was called outside the buffer lock, allowing new UI writes to be skipped
  - Now cleared atomically inside `compute_atomic` while holding the lock
- **Lambda-term `split_lines_preserve`** incorrectly added an extra empty element
  - `String.split_on_char` already handles trailing delimiters correctly

### Changed

- File browser fixes for edit mode (Space key handling, selection highlight)
- Version bump to 0.1.1

## [Unreleased]

### API

- Rename `Vsection.render` parameter `~footer` to `~content_footer` to clarify it is for page content, not driver-generated keymap footers.
- Clarify `PAGE_SIG` docs: keymap footers are auto-generated by drivers, `?` is reserved but may appear in keymaps for display, and `handled_keys` is only for conflict detection.
- Add `display_only` flag to keymap bindings so reserved keys (e.g., `?`) can be shown in footers/help without being dispatched; drivers and the key handler stack respect this.
- Add `File_browser_modal` helper plus `File_browser_widget.key_hints` to avoid re-wrapping the widget for modals and to surface consistent key hints.

### Breaking Changes (2026-01-08)

#### ⚠️ PAGE_SIG Navigation API Rewrite

**Impact:** All page implementations must be updated. This is a significant API change.

**What changed:**

The `next_page` field and `enter` function have been removed from `PAGE_SIG`. Instead, pages now use the `Navigation` module for all navigation, and all handlers work with `pstate` (which wraps state in `Navigation.t`).

**Old API (removed):**
```ocaml
module type PAGE_SIG = sig
  type state
  type msg

  val init : unit -> state
  val next_page : state -> string option  (* REMOVED *)
  val enter : state -> state               (* REMOVED *)

  val update : state -> msg -> state
  val view : state -> focus:bool -> size:LTerm_geom.size -> string
  val move : state -> int -> state
  val refresh : state -> state
  val service_select : state -> int -> state
  val service_cycle : state -> int -> state
  val back : state -> state
  val keymap : state -> (string * (state -> state) * string) list
  val handled_keys : unit -> Keys.t list
  val handle_modal_key : state -> string -> size:LTerm_geom.size -> state
  val handle_key : state -> string -> size:LTerm_geom.size -> state
  val has_modal : state -> bool
end
```

**New API:**
```ocaml
module type PAGE_SIG = sig
  type state  (* Your page's own state - no next_page field needed *)
  type msg
  type pstate = state Navigation.t  (* Wrapped state with navigation *)

  val init : unit -> pstate
  val update : pstate -> msg -> pstate
  val view : pstate -> focus:bool -> size:LTerm_geom.size -> string
  val move : pstate -> int -> pstate
  val refresh : pstate -> pstate
  val service_select : pstate -> int -> pstate
  val service_cycle : pstate -> int -> pstate
  val back : pstate -> pstate
  val keymap : pstate -> (string * (pstate -> pstate) * string) list
  val handled_keys : unit -> Keys.t list
  val handle_modal_key : pstate -> string -> size:LTerm_geom.size -> pstate
  val handle_key : pstate -> string -> size:LTerm_geom.size -> pstate
  val has_modal : pstate -> bool
end
```

**Migration guide:**

1. **Remove `next_page` from your state type:**
```ocaml
(* Before *)
type state = {
  items : string list;
  cursor : int;
  next_page : string option;  (* REMOVE THIS *)
}

(* After *)
type state = {
  items : string list;
  cursor : int;
}
```

2. **Add the `pstate` type alias:**
```ocaml
type pstate = state Navigation.t
```

3. **Update `init` to wrap state:**
```ocaml
(* Before *)
let init () = { items = []; cursor = 0; next_page = None }

(* After *)
let init () = Navigation.make { items = []; cursor = 0 }
```

4. **Remove `next_page` and `enter` functions** (they no longer exist).

5. **Update all handlers to use `pstate` and Navigation functions:**
```ocaml
(* Before *)
let handle_key s key ~size =
  match key with
  | "q" -> { s with next_page = Some "__QUIT__" }
  | "Esc" -> { s with next_page = Some "__BACK__" }
  | "Enter" -> { s with next_page = Some "details" }
  | "j" -> { s with cursor = s.cursor + 1 }
  | _ -> s

(* After *)
let handle_key ps key ~size =
  match key with
  | "q" -> Navigation.quit ps
  | "Esc" -> Navigation.back ps
  | "Enter" -> Navigation.goto "details" ps
  | "j" -> Navigation.update (fun s -> { s with cursor = s.cursor + 1 }) ps
  | _ -> ps
```

6. **Update state transformations to use `Navigation.update`:**
```ocaml
(* Before *)
let refresh s = { s with items = load_items () }

(* After *)
let refresh ps = Navigation.update (fun s -> { s with items = load_items () }) ps
```

7. **Update `view` to access inner state:**
```ocaml
(* Before *)
let view s ~focus ~size = render_items s.items s.cursor

(* After *)
let view ps ~focus ~size =
  let s = ps.s in  (* Access inner state via .s field *)
  render_items s.items s.cursor
```

**Navigation module reference:**
- `Navigation.make : 'a -> 'a t` - Wrap state with no pending navigation
- `Navigation.goto : string -> 'a t -> 'a t` - Navigate to a named page
- `Navigation.back : 'a t -> 'a t` - Go back (equivalent to `goto "__BACK__"`)
- `Navigation.quit : 'a t -> 'a t` - Quit application (equivalent to `goto "__QUIT__"`)
- `Navigation.update : ('a -> 'a) -> 'a t -> 'a t` - Modify inner state
- `Navigation.pending : 'a t -> string option` - Check pending navigation (used by framework)

**Compiler errors you'll see:**
```
Error: This expression has type state but an expression was expected of type
         state Navigation.t

Error: Unbound value next_page

Error: Unbound value enter
```

**Why this change?**
- Eliminates the error-prone `next_page` field that LLM agents frequently forgot to propagate
- Clear, named navigation functions instead of magic strings in a field
- Pure functional style with no hidden side effects
- Framework handles navigation automatically - pages just call `Navigation.goto`

### Added (2026-01-08)

#### Modal Navigation Helpers

Modal `on_close` callbacks can now request navigation without using refs or checking state in `service_cycle`:

```ocaml
(* Before - error-prone pattern requiring manual ref and service_cycle check *)
let nav_ref = ref None in
Modal_manager.push
  (module My_modal)
  ~init:(My_modal.init ())
  ~ui:{ title = "Choose"; ... }
  ~commit_on:["Enter"]
  ~cancel_on:["Esc"]
  ~on_close:(fun state outcome ->
    match outcome with
    | `Commit -> nav_ref := Some "next_page"
    | `Cancel -> ()) ;

(* Then in service_cycle: *)
let service_cycle ps _ =
  match !nav_ref with
  | Some page ->
      nav_ref := None ;
      Navigation.goto page ps
  | None -> ps

(* After - direct API call *)
Modal_manager.push
  (module My_modal)
  ~init:(My_modal.init ())
  ~ui:{ title = "Choose"; ... }
  ~commit_on:["Enter"]
  ~cancel_on:["Esc"]
  ~on_close:(fun _state outcome ->
    match outcome with
    | `Commit -> Modal_manager.set_pending_navigation "next_page"
    | `Cancel -> ())

(* No service_cycle code needed - framework handles it automatically *)
```

New functions:
- `Modal_manager.set_pending_navigation : string -> unit` - Request navigation from modal callback
- `Modal_manager.take_pending_navigation : unit -> string option` - Used by framework

#### Auto-Refresh Before Service Cycle

Drivers now automatically call `Page.refresh` before `Page.service_cycle`. This means:

- Pages no longer need to manually call `refresh` in `service_cycle`
- Consistent behavior across all drivers (Matrix, Lambda-term, SDL)
- The pattern `Page.service_cycle (Page.refresh ps) 0` is now handled by the framework

```ocaml
(* Before - manual refresh in service_cycle *)
let service_cycle ps _ =
  let ps = refresh ps in  (* Manual refresh call *)
  (* ... check refs, etc. *)
  ps

(* After - just handle service logic *)
let service_cycle ps _ =
  (* refresh is already called by the driver *)
  ps
```

#### Pager Widget Enhancements

- **Wrap toggle**: Press **`w`** to toggle word wrap on/off in the pager
- **Line truncation**: Long lines are truncated with visual indicator when wrap is off
- Default behavior changed to wrap=on for better readability

#### Narrow Terminal Warning

Both Matrix and Lambda-term drivers now show consistent narrow terminal warnings:

- **Warning banner** displayed when terminal width < 80 columns
- **One-time modal** appears on first detection (auto-dismisses after 5 seconds)
- **Any key dismisses** the modal immediately
- Warning only shown once per session (not repeatedly on resize)

### Changed (2026-01-08)

#### Driver Architecture Improvements

- **Periodic partial refresh**: Matrix driver performs full buffer refresh every ~2 seconds to catch rendering artifacts
- **Region-based dirty marking**: More efficient partial updates in Matrix driver
- **Terminal cleanup reliability**: Improved cleanup on exit to restore terminal state
- **Screen content preservation**: Exit screen content saved for debugging

#### Shared Driver Modules

Common functionality extracted into shared modules:
- `terminal_raw.ml` - Raw terminal mode handling
- `input_parser.ml` - ANSI escape sequence parsing

This reduces code duplication between Matrix and Lambda-term drivers.

### Fixed (2026-01-08)

- Modal close no longer causes double-navigation with Esc key
- Matrix driver now drains pending Esc keys after modal close
- Fiber scheduling improved in Matrix driver (uses `Eio.Time.sleep`)
- File pager uses proper Eio-based fiber scheduling

### Added (2026-01-05)

#### High-Performance Matrix Terminal Driver

- **`miaou-driver-matrix`** package with Ratatui-style diff rendering
- **Two-domain architecture** using OCaml 5 Domains for true parallelism:
  - Render Domain: 60 FPS, handles diff computation and terminal output
  - Main Domain: 30 TPS, handles input and state updates
- **Cell-based double buffering** with O(1) pointer swap
- **Diff-based rendering**: only changed cells are written to terminal (no flicker)
- **Thread-safe buffer** with mutex synchronization and atomic dirty flag
- Pure ANSI output (no lambda-term dependency)
- Matrix is now the **default driver** (priority: Matrix > SDL > Lambda-term)
- Configuration via environment variables:
  - `MIAOU_DRIVER=matrix` (default) or `term` or `sdl`
  - `MIAOU_MATRIX_FPS=60` - Render domain frame rate cap
  - `MIAOU_MATRIX_TPS=30` - Main domain tick rate

#### Debug Overlay for Performance Monitoring

- **`MIAOU_OVERLAY=1`** environment variable enables real-time performance metrics
- Displays in top-right corner with dim styling:
  - **L** (Loop FPS): Render loop iteration rate (the cap)
  - **R** (Render FPS): Actual frames rendered per second
  - **T** (TPS): Ticks per second (main loop rate)
- Available in both Matrix and Lambda-term drivers
- Useful for diagnosing performance issues and verifying frame rates

### Added (2025-12-19)

#### Debounced Validation for Validated Textbox Widget

- **`debounce_ms` parameter** for `Validated_textbox_widget.create` (default: 250ms)
- Validation now defers during rapid typing, running after the debounce period elapses
- Text input remains immediate for responsive UX
- New functions:
  - `tick` - Check and run pending validation (call in `service_cycle`)
  - `flush_validation` - Force immediate validation (useful before form submission)
  - `has_pending_validation` - Check if validation is pending
- Set `debounce_ms=0` to disable debouncing (legacy immediate behavior)

#### Global Render Notification System

- **`Miaou_helpers.Render_notify`** module for widgets to request async UI updates
- `request_render()` - Request a re-render from any widget
- `should_render()` - Check if a render was requested (called by driver)
- Used by validated textbox to trigger validation after debounce period

#### Generic Debounce Module

- **`Miaou_helpers.Debounce`** module for generic debounce timing
- Thread-safe implementation using `Atomic` operations
- Functions: `create`, `mark`, `is_ready`, `clear`, `has_pending`, `check_and_clear`
- Configurable debounce period in milliseconds (default: 250ms)

#### File Browser Performance Optimization

- **Caching for directory listings** - `list_entries_with_parent` now caches results
- **Caching for writable status** - `is_writable` checks are cached per-directory
- Cache automatically invalidates when navigating to a different directory
- Cache manually invalidated after directory creation (`mkdir_and_cd`, inline mkdir)
- New `invalidate_cache()` function for manual cache clearing
- Significantly reduces filesystem calls during rapid Up/Down navigation
- **Note**: Cache is shared globally across all file browser instances

#### File Browser Hidden Files Toggle

- Press **`h`** to toggle visibility of hidden files/directories (starting with `.`)
- New `show_hidden` parameter in `open_centered` (default: `false`)
- Tab completion always includes hidden files for convenience (allows completing `.config/` etc.)
- Header hint updates dynamically to show current state

#### Textbox Input Draining for Typing Responsiveness

- **`Miaou_helpers.Input_drain`** module for draining buffered input characters
- Textbox widgets now process all pending printable characters at once
- Prevents typing lag when entering text quickly
- Driver registers drain function, widgets call `drain_pending_chars()`

### Added (2025-12-17)

- Modal sizing supports dynamic width specs (`Fixed`, `Ratio`, `Clamped`) resolved at render time, including fallback terminal size detection via `/dev/tty` so modals resize with the terminal even when `System` is mocked.

### Changed (2025-12-17)

#### Opam package restructuring for optional SDL

Restructured opam packages to allow terminal-only builds without SDL2 dependency:

- **`miaou-core`**: Standalone core package with all widgets, no SDL dependencies
- **`miaou-driver-term`**: Terminal driver, depends only on `miaou-core`
- **`miaou-driver-sdl`**: SDL driver with SDL2 dependencies (`tsdl`, `tsdl-ttf`, `tsdl-image`)
- **`miaou-widgets-display-sdl`**: SDL-specific widget implementations
- **`miaou-runner`**: Runner with `miaou-driver-sdl` as optional dependency
- **`miaou-tui`**: Meta-package for terminal-only installs (no SDL)
- **`miaou`**: Meta-package for full install (includes SDL)
- **`miaou-core.lib`**: The convenience `Miaou` module (re-exporting Core, Widgets, etc.) is now part of `miaou-core`, available to terminal-only users

Terminal-only users can now: `opam install miaou-tui`

### Breaking Changes (2025-12-17)

- Library public names changed to use package prefixes:
  - `miaou.lib` → `miaou-core.lib`
  - `miaou.core` → `miaou-core.core`
  - `miaou.widgets.display` → `miaou-core.widgets.display`
  - `miaou.driver.term` → `miaou-driver-term.driver`
  - `miaou.driver.sdl` → `miaou-driver-sdl.driver`
  - And similar for other libraries
- `Miaou_widgets_display.Sparkline_widget_sdl` moved to `Miaou_widgets_display_sdl.Sparkline_widget_sdl` (and similar for other SDL widgets)
- `Modal_manager.ui.max_width` (and related helpers) now expects `max_width_spec option` instead of `int option`; wrap existing fixed widths with `Fixed n` or switch to ratio/clamped specs.

### Changed (2025-12-15)

- File pager tail fibers are now scoped to per-page switches and auto-cancel on navigation; terminal, SDL, and headless drivers wrap pages in `Fiber_runtime.with_page_switch` for structured cleanup; `Fiber_runtime` exposes page switch helpers. Adds regression coverage for pager cleanup.
- Pager UX fixes: follow hint only shown when streaming, static pager test added, markdown renderer hides inline backticks and underlines H1 titles.
- Service lifecycle: removing instance files no longer requires a role value.
- File browser navigation: canonicalize paths so parent navigation works from relative paths, scroll the viewport earlier, and tighten Enter navigation checks; demo uses the real filesystem so Enter now changes directories.
- Modal sizing: modal pages now receive the actual modal content geometry (rows/cols) so list widgets don’t scroll into invisible items due to modal height clipping.

### Added (2025-12-11)

#### Input Buffer Draining for Navigation Keys
- **Navigation key coalescing** to prevent scroll lag in list widgets
- When arrow keys are held down and released, consecutive identical navigation events are automatically drained from the input buffer
- Only the final navigation event is processed, making the UI feel more responsive
- Debug logging available with `MIAOU_DEBUG=1` to track drain operations
- Fixes issue where selection continues scrolling for ~0.5s after releasing arrow keys

#### Braille Rendering Mode
- **Unicode Braille patterns** for high-resolution chart rendering (2×4 dots per character cell)
- Braille mode support for `Line_chart_widget`, `Bar_chart_widget`, and `Sparkline_widget`
- `Braille_canvas` module for efficient braille dot manipulation
- 8x higher resolution compared to ASCII mode with only 2x performance cost
- Colored braille output with ANSI styling support
- Performance: 9,259 renders/second for line charts in braille mode

#### Global Keys API
- **Type-safe keyboard handling system** with variant-based key definitions
- Extended `Keys.t` with new key types: `PageUp`, `PageDown`, `Home`, `End`, `Escape`, `Delete`, `Function of int`
- Global key reservations for application-wide actions: `Settings`, `Help`, `Menu`, `Quit`
- Registry validation to prevent key conflicts at page registration time
- `Registry.check_all_conflicts()` for detecting inter-page key conflicts
- `Registry.conflict_report()` for human-readable conflict summaries
- Helper functions: `Keys.is_global_key`, `Keys.get_global_action`, `Keys.show_global_keys`

### Changed (2025-12-10)

#### Performance Optimizations
- **Significant performance improvements** across all widgets (8-24x faster in some cases)
- Replaced `String.concat` with buffer-based rendering throughout codebase
- Introduced `Helpers.pad_to_width` eliminating O(n²) padding allocations
- Optimized pager widget: 9.1s → 1.2s (8x faster)
- Optimized layout widget: 9.0s → 0.8s (12x faster)
- Optimized card_sidebar: 15.1s → 1.0s (15x faster)
- All other widgets show 20-40% performance improvements

### Breaking Changes (2025-12-12)

#### ⚠️ Runtime Migrated from Lwt to Eio

**Impact:** Applications must initialize the Eio runtime before using Miaou.

**What changed:**
- All async/concurrency now uses Eio instead of Lwt
- `cohttp-lwt-unix` replaced with `cohttp-eio`
- Terminal driver uses `Eio_unix.await_readable` for input polling
- Background tasks use `Eio.Fiber` instead of `Thread.create`

**Migration guide:**

1. Wrap your main function in `Eio_main.run` and initialize the runtime:
```ocaml
(* Before *)
let () =
  let page = ... in
  Miaou_runner_tui.Runner_tui.run page

(* After *)
let () =
  Eio_main.run @@ fun env ->
  Eio.Switch.run @@ fun sw ->
  Miaou_helpers.Fiber_runtime.init ~env ~sw;
  let page = ... in
  Miaou_runner_tui.Runner_tui.run page
```

2. Update opam dependencies:
```
- lwt
- cohttp-lwt-unix
+ eio
+ eio_main
+ cohttp-eio
```

**New modules:**
- `Miaou_helpers.Fiber_runtime` — shared Eio runtime management
- `Miaou_widgets_display.File_pager` — Eio-based file tailing pager

#### ⚠️ Pager Widget: Notification Callback Now Per-Instance

**Impact:** Code using `Pager_widget.set_notify_render` must be updated.

**What changed:**
```ocaml
(* OLD - Global callback (removed) *)
Pager_widget.set_notify_render (Some callback);
let pager = Pager_widget.open_lines ~title:"Log" lines in

(* NEW - Per-instance callback *)
let pager = Pager_widget.open_lines ~title:"Log" ~notify_render:callback lines in
```

**Migration guide:**

1. Remove calls to `set_notify_render`
2. Pass `~notify_render` parameter to `open_lines`/`open_text`

**Before:**
```ocaml
let pager = Pager_widget.open_lines ~title:"My Pager" [] in
Pager_widget.set_notify_render (Some render_callback);
```

**After:**
```ocaml
let pager = Pager_widget.open_lines ~title:"My Pager"
              ~notify_render:render_callback [] in
```

**Why this change?**
- Eliminates global mutable state
- Enables multiple independent pagers with different callbacks
- Makes callback lifetime explicit (tied to pager instance)
- Better composability and testability

**Type signature changes:**
- `open_lines : ?title:string -> ?notify_render:(unit -> unit) -> string list -> t`
- `open_text : ?title:string -> ?notify_render:(unit -> unit) -> string -> t`
- `set_notify_render` function removed

**Compiler error you'll see:**
```
Error: Unbound value Pager_widget.set_notify_render
```

### Breaking Changes (2025-12-11)

#### ⚠️ PAGE_SIG Requires `handled_keys` Function

**Impact:** All page implementations must be updated.

**What changed:**
```ocaml
module type PAGE_SIG = sig
  (* ... existing fields ... *)
  
  (* NEW - REQUIRED *)
  val handled_keys : unit -> Keys.t list
end
```

**Migration guide:**

For **minimal migration**, add this to every page:
```ocaml
let handled_keys () = []
```

For **proper key declaration** (recommended):
```ocaml
let handled_keys () = [
  Keys.Char "a";      (* Declare all keys your page handles *)
  Keys.Enter;
  Keys.Up;
  Keys.Down;
  (* ... *)
]
```

**Why this change?**
- Enables compile-time key conflict detection
- Self-documents key bindings
- Foundation for auto-generated help system
- Enables future page registry and navigation features

**Compiler error you'll see:**
```
Error: Signature mismatch:
       The value `handled_keys' is required but not provided
       File "src/miaou_core/tui_page.mli", line 38, characters 2-40:
         Expected declaration
```

**Benefits:**
- ✅ Type-safe key handling (variants, not strings)
- ✅ Prevents global key conflicts automatically
- ✅ Runtime validation catches inter-page conflicts
- ✅ Clear error messages when conflicts occur

## [Previous Releases]

<!-- Previous changelog entries would go here -->
