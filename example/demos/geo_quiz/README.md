# Geo Quiz

Place the prompted city on the world map. Score depends on **how close** your
guess is to the real location, and **how quickly** you commit (you have 30 s
per round).

## How to play

1. **Menu** — pick a difficulty (`◀`/`▶` or arrow keys). Press `Enter` to start.
2. **Round** — the prompt shows the city. Move the cyan crosshair (`+`) with
   the arrow keys (Shift+arrow = bigger jump). Press `Enter` to lock in your
   guess. The 30-second clock counts down at the bottom — running out of time
   scores zero for the round.
3. **Round end** — the truth pin (red) is revealed; your guess pin (cyan) is
   shown. Press `Enter` to advance, `Esc` to quit to menu.
4. **Game over** — after 10 rounds, a bar chart shows your per-round scores.

## Difficulty tiers

| Tier | Pool |
|------|------|
| Easy   | Capitals of countries with population > 30 M (~25 cities) |
| Normal | All capitals (~200) |
| Hard   | Capitals + cities > 1 M (~700) |
| Expert | Cities > 100 K (~5 000) |
| Master | Cities > 15 K (~25 000) |

For `Easy`/`Normal`/`Hard` the prompt also shows the country. Higher tiers
give the city name only.

## Scoring

- **Distance score** = `1000 × (1 − distance_km / max_d)`, clamped to 0..1000.
  `max_d` is 5 000 km for the easy tiers (1–3) and 2 500 km for the harder
  tiers (4–5).
- **Time bonus** = remaining seconds × 10, capped at 300.
- **Round total** = distance + time. **Game total** is the sum across rounds
  (max ≈ 13 000).

## Keys

| Key | Action |
|-----|--------|
| Arrows         | Move crosshair / cycle difficulty |
| Shift+Arrows   | Move crosshair faster |
| Enter          | Start / lock in / advance |
| Esc            | Cancel / back |
| t              | Open this tutorial |

## Data

The world coastline comes from Natural Earth (`ne_110m_coastline`,
public domain). The city list comes from GeoNames (`cities15000.txt`,
CC BY 4.0). See `data/ATTRIBUTIONS.md` for details.
