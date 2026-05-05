# MIAOU Crypt

A pseudo-3-D first-person dungeon crawler rendered in the terminal using
a real DDA raycast engine. Seven floors of permadeath dungeoneering, two
boss encounters, and an ever-deepening crypt that never plays quite the
same way twice.

```
  HP:20/20  Lv.1 | 🗝0  ⚗0  🕯0  ⚔+0  ⚡×1 | F1/7 | Best:F0 | Score:0

                                             MIAOU CRYPT — descend
                                   a pseudo-3-D first-person dungeon crawler

                                       ████▓▓▒▒░░             ░░▒▒▓▓████
                                        ████▓▓▒░  ╔══════════╗  ░▒▓▓████
                                        ████▓▒░   ║          ║   ░▒▓████
                                        ████▓░   ╔╝          ╚╗   ░▓████
                                        ████░   ╔╝            ╚╗   ░████
                                         ███░    ║  🔥      🔥  ║    ░███
                                        ███     ║              ║     ███
                                        ████░   ╚╗            ╔╝   ░████
                                        ████▓░   ╚╗          ╔╝   ░▓████
                                      ═══════════════════════════════════
```

## Story

You wake at the entrance of a seven-floor crypt. A small lantern, a
pocket dagger, and the rumour of an artifact on the deepest floor. Each
floor has at least one key, a locked door, and monsters between you and
the stairs down. **Permadeath** — every death restarts from floor 1.

## Controls

| Key            | Action                                        |
|----------------|-----------------------------------------------|
| `↑` / `w`      | Step forward (one tile)                       |
| `↓` / `s`      | Step back                                     |
| `←` / `→`      | Turn 90°                                      |
| `a` / `d`      | Strafe left / right                           |
| `Space`        | Attack adjacent monster / open door / pick up |
| `e`            | Spin attack — hits all 8 surrounding tiles (costs ⚡ charge) |
| `f`            | Use bomb scroll — area blast radius 3 (costs bomb) |
| `q`            | Drink potion (+5 HP)                          |
| `t`            | Light torch (+visibility, warm palette, 30 s) |
| `m`            | Toggle minimap                                |
| `i`            | Inventory panel                               |
| `Esc`          | Back to title                                 |
| `Enter`        | Start / restart                               |

**Debug step mode** (`MIAOU_CRYPT_STEP=1` or `t` on title):

| Key | Action |
|-----|--------|
| `n` | Advance one tick |
| `N` | Advance ten ticks |
| `b` | Advance sixty ticks (≈1 s) |

## How It Plays

The view is a true **DDA raycast** first-person 3-D corridor: each
framebuffer column casts a ray, finds the first wall hit, and draws a
vertical wall slice with distance-based shading. Closer walls are bright;
far walls fade through a six-step ramp to near-black. Floor and ceiling
use vertical gradients (cool dim above, warm dim below). Stone-block
texture variation: every 3rd tile row has a darker mortar course; even
columns get a slight brightness boost.

**Monsters** are billboarded coloured shapes that scale with distance. A
bright yellow `!` sprite appears above a monster for 1.5 s when it first
detects you — and then it enters its alerted state, moving faster.

The **minimap** in the top-right shows the tile grid, your pose (orange
▲), monster positions, corpse markers (×), and a player breadcrumb trail.

## Monster Roster

| Monster | HP | Dmg | XP | Behaviour |
|---------|----|----|-----|-----------|
| Spider | 2 | 1 | 10 | Fast; low HP; red blob |
| Skeleton | 4 | 2 | 20 | Methodical; pale humanoid |
| Bat | 1 | 1 | 5 | Random-direction zigzag flight |
| Archer | 3 | 1 | 25 | Fires arrows from 3+ tiles; ranged |
| Zombie | 8 | 3 | 30 | Very slow (3 s cooldown); stun-immune; drops Healing Rune |
| Wraith | 5 | 2 | 50 | Teleports to tile in front of player every 5 s |
| Lich | 16 | 4 | 500 | Mid-boss (floor 5); ranged fireball; two phases |
| Dragon | 30 | 6 | 1500 | Final boss (floor 7); breath cone; three phases |

**Alerted monsters** (within 4 tiles) halve their movement cooldown —
Spiders, Skeletons, and Zombies become noticeably more aggressive.

## Floor Layout

| Floor | Variant | Highlights |
|-------|---------|-----------|
| 1 | A or B | Tutorial layout, Spider + key + locked door |
| 2 | A or B | Bat encounter, Potion reward |
| 3 | A or B | Crossroads room, Archer sniper positions, Bomb scroll, Speed scroll |
| 4 | — | Treasury room (Sword + Map scroll), secret alcove |
| 5 | — | Pre-boss corridor, Lich boss arena, secret alcove with hidden Potion |
| 6 | — | Locked door needs floor key, Armor pickup, Ring of Speed |
| 7 | — | Dragon boss arena with approach corridor |

Floors 1–3 each have two randomised layout variants, chosen fresh each
run. The **floor 5 secret alcove** is a 1-tile gap in the wall that looks
solid on the minimap — it hides a Health Potion.

## Items

| Item | Layout char | Effect |
|------|-------------|--------|
| Key | `K` | Opens locked doors (`D`) |
| Health Potion | `P` | +5 HP (press `q` from inventory) |
| Torch | `T` | +30 s torch timer; extends view to 16 tiles; warm palette |
| Sword Upgrade | `W` | +1 permanent attack damage |
| Map Scroll | `M` | Reveals entire floor on minimap |
| Ring of Speed | `R` | ×1.5 speed for 30 s |
| Speed Scroll | `Q` | ×1.5 speed for 15 s |
| Armor | `V` | Reduces all incoming damage by 1 (min 1); shown as `[A]` |
| Bomb Scroll | `B` | Area blast (radius 3, 5 dmg); use with `f` |
| Healing Rune | dropped | Left by Zombie corpses; +3 HP on step |

## Combat

- **Step on adjacent tile** to face a monster: `Space` swings your weapon.
- Weapon damage = `1 + attack_bonus + level_attack_bonus`.
- **Spin attack** (`e`): costs 1 ⚡ charge — damages all 8 surrounding tiles.
  Charges: start with 1, gain +1 per 5 floors and per Sword pickup (max 3).
- **Bomb** (`f`): area blast, radius 3, 5 damage to everything caught.
- Monsters hit back on the same turn if still alive.
- **Stun** (`stun_t`): some attacks briefly stun monsters. Zombies are immune.

## Player Progression

**Experience and levelling up:**
- Every kill awards XP = score value ÷ 5 (min 1).
- Level-up threshold starts at 30 XP, +20 per level.
- Level-up grants: +5 max HP, +2 current HP, +1 attack bonus.
- A golden `★ LEVEL UP! Lv.N ★` banner appears on level-up.
- Current level shown as `Lv.N` in the HUD.

**Passive regen:**
- Standing still for 4 s with HP below max restores +1 HP.
- A `...` indicator in the HUD shows regen charging (appears after 2 s).
- Taking any damage resets the timer.

## HUD Layout

```
HP:20/20  Lv.1 | 🗝0  ⚗0  🕯30s  ⚔+1  ⚡×2 [A] | F3/7 | Best:F5 | Score:320
```

- **HP** — current / max; pulses red vignette when ≤ 5
- **Lv** — player level
- **🗝** — key count, **⚗** — potion count, **🕯** — torch timer (blinks when < 5 s)
- **⚔** — attack bonus, **⚡** — spin charges, **[A]** — armor active
- **F3/7** — current floor / total floors
- **[B:N]** — bomb count (in orange) when bombs are held
- **Score** — current run score

## Boss Encounters

### The Lich (Floor 5)
Fires homing fireballs. At 50% HP enters phase 2 with faster fire rate.
Approach down the boss corridor — use the walls for cover. A **boss
warning banner** flashes red before the encounter.

### The Dragon (Floor 7)
Fires a wide breath cone. At 66% HP enters phase 2 (faster, wider cone).
At ≤25% HP enters phase 3 — **moves one tile toward you every 3 s**,
closing the distance. Kill it before it corners you.

## Death Summary

Game-over shows a gravestone panel with:
- **FLOORS REACHED**: deepest floor this run
- **TOTAL KILLS**: all monsters slain
- **FLOOR RATINGS**: 1–3 ★ per floor based on score benchmarks
- **CAUSE OF DEATH**: "Killed by DRAGON", "Fell to a Skeleton", etc.

Best depth persists in `$XDG_STATE_HOME/miaou/miaou_crypt.score`.

## Visual Highlights

- **DDA raycast** 3-D corridor — each column is a real ray intersection
- Distance-based **wall shading** with stone-block texture variation
- **Torch warm palette** — additive orange tint to walls while torch is active
- **Health vignette** — pulsing red perimeter ring at low HP
- **Footstep flash** — subtle floor highlight on each move step
- **Corpse markers** — dark-red × pins on minimap for each kill location
- **Player trail** — 5-step breadcrumb in fading grey on minimap
- **Boss kill cinematic** — upward particle burst before floor-clear screen
- **Monster alert `!`** sprite — bright yellow exclamation above newly-alerted enemies

## Render Mode

Defaults to **Octant** (sub-cell 2×4 pixels).
Override: `MIAOU_CRYPT_PIXEL_MODE=sixel|octant|sextant|half_block|braille`
