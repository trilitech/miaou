# Miaou Website Media Guide

The website should look playful, but feature media must be honest.

## Rules

- Use real Miaou screenshots, frame captures, asciicasts, GIFs, or videos for widgets, tutorials, and showcases.
- Do not use generated images as substitutes for real widget or game output.
- Generated images are acceptable only for decorative hero/section artwork.
- Game showcases should use short videos or GIFs because motion matters.
- Widget/layout/style showcases can use static SVG/PNG captures when a still frame explains the feature.

## Capture Targets

Recommended initial media set:

- `gallery-overview`: demo launcher navigation.
- `style-system`: theme switching.
- `responsive`: resize/breakpoint behavior.
- `sparkline` or `line_chart`: chart rendering modes.
- `table`: data display and cursor movement.
- `validated_textbox`: forms and validation.
- `miaou_force`: framebuffer game video.
- `miaou_crypt`: raycast game video.
- `miaou_links`: golf physics video.
- `geo_quiz`: map/globe showcase video.

## Commands

After the demo executables are built, static captures can be generated with:

```sh
npm run captures
```

This uses tmux to run actual non-game demo executables and produces lightweight
captures under `website/src/media/captures/`. The responsive layout demo also
gets a small GIF because it specifically demonstrates terminal resizing.

Game captures should use asciinema casts instead of GIF rasterization:

```sh
npm run game-captures
```

This preserves terminal colours and cell geometry for framebuffer output while
using a deliberately small 88x28 terminal. The website embeds these casts with
the asciinema web player.

Frame captures and replay artifacts should use the existing recording helpers:

```sh
./tools/capture_helper.sh --dir recordings -- dune exec -- miaou.demo
./tools/replay_tui.py --keystrokes recordings/example_keystrokes.jsonl --write-cast recordings/example.cast
./tools/convert_cast_to_gif.sh recordings/example.cast website/src/media/captures/example.gif
```

