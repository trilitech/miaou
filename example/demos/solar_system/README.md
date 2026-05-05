# Solar System

A real-time visual simulation of the inner and outer planets orbiting the
Sun. Each body moves along its true orbital period, axial rotation periods
are shown via a small surface marker, and bodies are drawn at scaled-but-
proportional sizes so even Mercury stays visible while Jupiter and Saturn
still feel imposing.

## Controls

- `1`–`5` — set time speed (×1 / ×10 / ×100 / ×1000 / ×10000 days per
  second)
- `Space` / `p` — pause / resume
- `o` — toggle orbit rings
- `l` — toggle planet labels
- `r` — reset simulated time to today
- `Tab` — show / hide the side panel
- `Esc` — back to the launcher

## Notes

Distances are compressed using a square-root scale so the inner planets
don't bunch into the Sun while Neptune still fits on screen. Body radii
use a cube-root compression: Jupiter is visibly the largest, Mercury the
smallest, but the dynamic range is squashed enough that nothing
disappears at typical terminal sizes.

The simulation is purely visual — no physics integration; positions are
analytic (`angle = 2π · t / period`).
