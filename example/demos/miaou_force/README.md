# MIAOU Force

An R-Type-style horizontal shoot-em-up rendered entirely in the terminal
using sub-cell Octant pixel graphics. Three levels, a multi-phase final
boss, and the iconic detachable **Force** pod that separates expert play
from survival.

```
 LVL1 Score 00000 Best 11950 Lives 3 Force[F]

                                          MIAOU FORCE
                             an R-Type-style horizontal shoot-em-up

                             ═══════════════════════════════════

                                   Arrow keys  -  Move ship
                         Space       -  Fire (auto / hold to charge)
                           d           -  Detach / recall the Force
                            f           -  Flip Force front / back
                           Esc         -  Pause / back to launcher

                            Enter to launch  ·  S for level select

                                      BEST SCORE: 011950
                                       RANK: RECRUIT *
```

## Story

Your ship is small. The enemies are many. Fortunately you have the
**Force** — a glowing pod that docks to the front or back of your ship,
or floats in space firing on its own. Three levels stand between you and
the Bydo Core. Use it well.

## Controls

| Key          | Action                                       |
|--------------|----------------------------------------------|
| Arrow keys   | Move ship (8-way)                            |
| Space        | Fire (auto-fire on tap, sustained on hold)   |
| `d`          | Detach the Force / recall it                 |
| `f`          | Flip the Force front ↔ back when attached    |
| `s`          | Level select screen                          |
| `Esc`        | Back to title (and from title, to launcher)  |
| `Enter`      | Start / restart                              |

**Debug / turn-based mode** (toggle with `MIAOU_FORCE_TURN_BASED=1`):

| Key | Action |
|-----|--------|
| `n` | Advance one frame (1/60 s) |
| `N` | Advance ten frames |
| `b` | Advance sixty frames (1 s) |

## The Force Module

The Force pod is the central mechanic — master its placement to survive.

| State | HUD label | Effect |
|-------|-----------|--------|
| Front-docked | `Force[F]` | Heavy forward fire; blocks enemy bullets from the front |
| Back-docked | `Force[B]` | Fires behind the ship; great for trailing enemies |
| Detached | `Force[*]` | Floats at a fixed world position, auto-fires forward, absorbs bullets |

- Press `f` while attached to flip front/back.
- Press `d` to toggle detached/attached.
- When recalled from detach, a **0.3 s speed burst** propels the pod back
  to the ship quickly.

## Weapons & Power-ups

Collect glowing pickups to upgrade your arsenal:

| Pickup | Effect |
|--------|--------|
| Weapon Upgrade | Increases fire tier (up to level 4): wider spread → triple shot → laser |
| Missile Upgrade | Adds homing missiles that track the nearest enemy |
| Force Upgrade | Doubles Force pod fire rate |
| Speed Burst | 4 s overdrive: ship speed ×1.6, fire interval 0.06 s; rainbow particle trail |
| Shield | Absorbs 2 hits before breaking; `[S]` shown in HUD |

**Charge beam**: hold Space to charge. Release for a devastating wide beam
with a glow at the ship nose.

## Enemy Roster

| Enemy | Behaviour |
|-------|-----------|
| Grunt | Standard fighter; flies left, fires one bullet |
| Diver | Swoops in from the top edge |
| Turret | Stationary; barrel rotates to track player vertically |
| Laser Emitter | Charges then fires a full-screen horizontal laser; telegraphs path with a dotted red line |
| Missile Fighter | Fires homing missiles |
| Strafer | Side-to-side weave, burst fire |
| Shielded | Armoured: shield absorbs 3 hits before HP damage starts |
| Mine | Stationary cluster; chain-detonates neighbours when hit |
| Carrier | Large slow ship; periodically spawns Grunt reinforcements; 3-burst death |
| Boomerang | Arc-motion; fires spread bullets |

## Levels

### Level 1 — Vanguard Run
Rocky brown terrain. Classic wave sequences: V-formations, dive columns,
turret pairs, a Carrier encounter. Boss: **Wyvern Core** (two phases).

### Level 2 — Nebula Approach
Green nebula tiles. Laser emitters, **Omega Formations** (six-Grunt hexagon
plus a central Turret 0.3 s later), Speed Burst pickups. Boss: **Null
Sphere** (two phases, homing barrage on phase 2).

### Level 3 — Bydo Fortress
Dark purple terrain. Opens with a **gauntlet corridor**: four turret pairs
and mine fields in the first 400 px demand immediate aggressive play.
Diamond formations and Carrier escorts follow. Boss: **Bydo Core** (three
phases, 70 HP).

Phase transitions are announced with a full-width **"!! PHASE CHANGE !!"**
banner in bright red, fading over 0.6 s.

## HUD Layout

```
LVL1 Score 12345 Best 19990 Lives ♥♥♥ Force[F]
[Weapon: ■■□□]  [M:■□□]  SPD  Spd:[■■□]
```

- **Animated score** — exponentially smoothed toward the real score
- **Combo multiplier** — flashes yellow when ≥ 2× (decays after 1.5 s)
- **Milestone popups** — gold overlay at 5 000 / 10 000 / 20 000 / 50 000
- **Weapon tier bars** — filled squares show current upgrade level
- **SPD** label — appears in cyan while Speed Burst is active

## Scoring

| Kill | Base points |
|------|-------------|
| Grunt | 100 |
| Diver | 150 |
| Turret | 250 |
| Strafer | 200 |
| Laser Emitter | 350 |
| Missile Fighter | 300 |
| Shielded | 400 |
| Mine | 350 |
| Carrier | 500 |
| Boomerang | 250 |
| Boss | 5 000+ |

Kills within 1.5 s of each other build a **combo multiplier** (up to 8×).

## End-of-run Summary

Clearing all three levels shows a **mission-complete screen** with:
- Per-level score breakdown (LVL 1 / LVL 2 / LVL 3)
- Total score with pilot rank: ROOKIE → CADET → VETERAN → **ACE PILOT**

Best score persists in `$XDG_STATE_HOME/miaou/miaou_force.score`.

## Visual Highlights

- Two-layer **parallax starfield** + mid-layer rock formations at 60% scroll speed
- Sub-cell **Octant pixel** terrain and sprites (2×4 pixels per character cell)
- **Charge beam glow** that widens as the charge builds
- **Speed burst rainbow trail** — hue cycles as the boost timer counts down
- **Enemy spawn fade-in** — checkerboard materialise effect over 0.3 s
- **Homing bullet particle trail** — red fading dot streak behind each missile
- **Screen shake** on boss hits and player death
- **Level-clear wipe** transition — vertical bar sweeps left-to-right
- **Pre-allocated particle ring buffer** — no per-frame GC pressure

## Render Mode

Defaults to **Octant** (sub-cell 2×4 pixels) for maximum detail.
Override: `MIAOU_FORCE_PIXEL_MODE=sixel|octant|sextant|half_block|braille`

## Difficulty

Three lives; respawn with 1.5 s invulnerability.
Set `MIAOU_FORCE_HARD=1` for one-life arcade mode.
Enemies on levels 2 and 3 scale up HP and bullet speed
(`difficulty_factor` 1.2× / 1.4×).
