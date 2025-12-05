# Sample capture artifacts

The files in this directory are reference captures used for regression testing,
documentation, and screencast generation:

- `miaou_logging_create_keystrokes.jsonl` – manual keystrokes for the node
  creation flow (file logging with rotation).
- `miaou_logging_switch_keystrokes.jsonl` – keystrokes for switching a node from
  journald to file logging and back.
- `miaou_logging_switch_frames.jsonl` – a single-frame dump used by
  `tools/replay_screencast.sh`.
- `miaou_logging_switch.cast` – asciinema v2 recording produced by replaying the
  keystrokes above (suitable input for `tools/convert_cast_to_gif.sh`).

Feel free to regenerate these artifacts with `./tools/capture_helper.sh` followed
by `./tools/replay_tui.py --keystrokes … --write-cast …`. If you do so, please
keep the filenames stable so downstream documentation and scripts keep working.
