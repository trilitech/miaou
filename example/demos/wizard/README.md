# Wizard Demo

A three-step setup wizard powered by `Miaou_widgets_layout.Wizard_widget`.

## Steps

1. **Pick a backend** — cycle through `matrix` / `term` / `sdl` / `web` with
   `←` / `→`. Advance is blocked until a backend is picked.
2. **Name it** — type a project name. Use `Backspace` to correct. Advance is
   blocked while empty.
3. **Review** — confirms the chosen backend and name. Press `Enter` to finish.

## Keys

- `Enter` — validate and advance / finish on the last step.
- `Shift+Tab` — return to the previous step.
- `Esc` — cancel the wizard.
- `t` — open this tutorial.

The wizard intercepts `Enter`, `Escape`, `Shift+Tab`, and `C-Left`. Every other
key is forwarded to the active step's `on_key` handler — so each step can
embed any input widget.
