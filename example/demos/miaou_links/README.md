# MIAOU Links

A chill top-down golf roguelite rendered in the terminal using sub-cell
Octant pixel graphics. Play a classic 18-hole tour, or dive into the
**Roguelite Run** — 9 random holes, a coin economy, a pre-run perk shop,
and a stamina clock that forces bold play.

```
  MIAOU LINKS — Roguelite Greens

                             MIAOU LINKS — Roguelite Greens
                   a top-down golf roguelite — 9 random holes per run

                          ═══════════════════════════════════

                              Left/Right     -  Rotate aim
                           [ / ]          -  Fine-rotate aim
                         Space          -  Power meter / swing
                              c              -  Cycle club
                                 Esc            -  Back

                                    Enter — New Run
                            O — Classic 18-hole tour (tOur)

                                       Coins: $0
                            Classic best: no round completed
                               Run best: no run completed
                                     >>> ready <<<
```

## Controls

| Key            | Action                                          |
|----------------|-------------------------------------------------|
| `←` / `→`      | Rotate aim                                      |
| `[` / `]`      | Fine-rotate aim (small steps)                   |
| `Space`        | First press: lock aim, start power meter        |
| `Space`        | Second press: swing                             |
| `c`            | Cycle club (driver / iron / wedge / putter)     |
| `Enter`        | New run / confirm / next hole                   |
| `O`            | Classic 18-hole tour                            |
| `Esc`          | Back (gameplay → title → launcher)              |

## Game Modes

### Roguelite Run (Enter)
Nine holes drawn at random from the full 18-hole catalogue. You start with
**45 stamina** (strokes remaining). Each hole consumes strokes; reaching 0
ends the run. Earn **coins** for completing holes, with bonuses for birdies,
eagles, and perks. Spend coins in the **pre-run shop** before each run
begins.

- **Hole preview** shows wind conditions and yardage before you start.
- After each hole a **perk pick** offers three random upgrades — choose one.
- Special holes trigger a **Boss Intro** screen before the tee-off.
- The run ends with a summary of your total score and best performance.

### Classic Tour (`O`)
14 holes, played in order, no stamina limit. Best total-under-par persists
across sessions.

## The Swing

1. **Aim** (`←` / `→`): rotate the aim arrow. Hold `[` / `]` for fine steps.
   - During aiming, the HUD shows `MAX: XXXyd` — maximum carry for the current club.
   - A **cup capture ring** pulses around the hole to show the sink radius.
   - **Eagle Eye** perk extends the aim arrow with a snap-to-cup helper.
2. **Power** (first Space): a bouncing meter fills and empties.
   - The HUD shows `~XXXyd` in real-time as the meter moves.
3. **Swing** (second Space): ball launches at the locked direction and power.
4. Watch the flight arc, the **ball trail**, and the **landing divot ring**.

## Clubs

| Club | Max distance | Best for |
|------|-------------|----------|
| Driver | ~264 yd | Long par-4/5 tee shots |
| Iron | ~204 yd | Approach shots |
| Wedge | ~132 yd | Short approaches, over hazards |
| Putter | ~96 yd | Green putts (reduced spread) |

Press `c` to cycle clubs. A **Putter Genius** perk improves put accuracy.
A **Power Swing** perk adds 20% to Driver distance.

## Course Tiles

| Tile | Physics |
|------|---------|
| Fairway | Light friction — rolls well |
| Green | Near-frictionless — use the putter |
| Rough | Heavy friction — ball stops fast (Rough Ready perk negates this) |
| Sand | Very heavy friction + random deflection on landing |
| Water | +1 stroke penalty, ball reset to previous position |
| Wall / OOB | +1 stroke penalty (Out-of-Bounds), ball reset |

**Wind** nudges the ball continuously during flight. Each hole has a base
wind that shifts ±10% each shot. Wind gusts can fire during a hole —
watch for the diagonal whoosh marks on screen.

## Hole Catalogue (18 Holes)

| # | Name | Par | Signature |
|---|------|-----|-----------|
| 1 | Starter's Green | 3 | Short introductory hole |
| 2 | The Dog-leg | 4 | Gentle left bend |
| 3 | Sandy Shores | 4 | Two sand traps on approach |
| 4 | The Pond | 3 | Water in the direct line |
| 5 | Long Carry | 5 | Driver-required distance |
| 6 | The Maze | 4 | Walled corridors |
| 7 | Windy Peak | 4 | Elevated green, strong wind |
| 8 | The Ravine | 3 | Narrow fairway, rough on sides |
| 9 | Dogleg Right | 4 | Water left, sand-guarded green |
| 10 | The Cliffs | 5 | Three-stage descent |
| 11 | Fairway Split | 4 | Fork in the fairway |
| 12 | Water Approach | 4 | 3-tile water strip at approach |
| 13 | The Island | 3 | Island green surrounded by water |
| 14 | The Bunker | 4 | Sand belt across the fairway |
| 15 | The Canyon | 5 | Long water carry |
| 16 | Switchback | 4 | Double bend |
| 17 | The Peninsula | 3 | Green jutting into water |
| 18 | The Clubhouse | 4 | Dogleg-right, water left, sand-guarded |

**"The Island"** (hole 13) is the signature challenge: the entire approach
is water — only the small island green is safe.

## Perk Shop & Perk Picks

Coins earned during a run unlock perks in the pre-run shop. After each
hole, a random pick of three perks is offered for free.

| Perk | Glyph | Cost | Effect |
|------|-------|------|--------|
| +1 Stamina | +S | $12 | Recover one stroke immediately |
| Wind Breaker | Wb | $18 | Wind effect halved this run |
| Sand Legs | Sl | $14 | No friction penalty in sand |
| Power Swing | Pw | $22 | Driver distance +20% |
| Putter Genius | Pg | $16 | Putter spread −5% |
| Lucky Bounce | Lb | $24 | 25% chance to redirect water shots |
| Stroke Saver | Ss | $20 | Every 4th hole grants +1 stamina |
| Coin Magnet | Cm | $30 | +50% coins from all sources |
| Eagle Eye | Ee | $18 | Longer aim arrow + cup snap helper |
| Storm Caller | Sc | $28 | Wind benefits you, hurts hazards |
| Birdie Bonus | Bb | $14 | Each birdie awards +2 coins |
| Iron Will | Iw | $16 | First water penalty ignored |
| Backspin | Bs | $20 | Ball reverses 20% on green — stops near cup |
| Double Down | Dd | $15 | Birdie or better doubles hole coin reward |
| Rough Ready | Rr | $16 | Rough friction reduced to 1.2 (same as fairway) |
| Albatross Alert | Al | $20 | 2+ under par: bonus +4 coins |

## Coin Economy

| Event | Coins |
|-------|-------|
| Completing any hole | +5 |
| Each stroke under par | +2 per stroke |
| Birdie Bonus perk active | +2 per birdie |
| Double Down perk + birdie | ×2 on hole total |
| Albatross Alert perk + 2+ under | +4 |
| Eagle: with Coin Magnet | all above ×1.5 |

## Special Scores

| Score | Strokes vs par | Visual |
|-------|---------------|--------|
| Albatross | −3 or better | Gold burst |
| Eagle | −2 | Eagle banner + cyan HUD |
| Birdie | −1 | Birdie banner |
| Par | 0 | Par |
| Bogey | +1 | Bogey |
| Double bogey+ | +2 or worse | Red text |

An **eagle or better** in run mode automatically restores +1 stamina.
A **chip-in** (ball airborne when it enters the cup) shows "CHIP-IN!" in gold.

## HUD (during play)

```
Stk 0  H11 Par4  Best+0    Hole 1/9  Stam [##################] 45/45  $0
```

- **Stk** — strokes taken this hole
- **Par** — par for this hole
- **Best** — your best score on this hole in the current run
- **Stam** — stamina bar (green→yellow→red; blinks with "LOW" warning at ≤3)
- **Wind arrow** — direction + tick marks for speed; CALM / BREEZY / GUSTY

## Scorecard

After the last hole, or when viewing the classic tour summary, the scorecard
shows each hole with:
- Strokes taken
- Delta vs par (`+N` / `-N` / `E`)
- Cumulative total (running score)
- Colour coding: cyan under par, red over par

A gold **"★ NEW PERSONAL BEST! ★"** banner appears if you beat your record.

## Visual Highlights

- Top-down course in **Octant** sub-cell pixels
- **Ball flight arc** with pixel trail and 3-D sphere rendering
- **Ball glow halo** (dim yellow disc) while in flight
- **Landing divot ring** — expanding fade ring at touchdown
- **Wind gust whoosh marks** — four diagonal streaks on gust events
- **Cup capture ring** — pulsing green ring at the hole during aiming
- **Hole rating splash** — BIRDIE / EAGLE / etc. in large text for 2 s

## Render Mode

Defaults to **Octant** (sub-cell 2×4 pixels).
Override: `MIAOU_LINKS_PIXEL_MODE=sixel|octant|sextant|half_block|braille`
