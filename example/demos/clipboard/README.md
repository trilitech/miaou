# Clipboard

The Clipboard capability allows terminal applications to copy text to the system clipboard using OSC 52 escape sequences.

## Features

- **OSC 52 support**: Works with modern terminals (iTerm2, Alacritty, kitty, WezTerm, Windows Terminal, tmux)
- **Native fallback**: Automatically uses `wl-copy`, `xclip`, `xsel`, or `pbcopy` as fallback
- **Primary selection**: Also copies to X11 primary selection for middle-click paste
- **Modal workflow**: Enter text in a modal and press Enter to copy

## Usage

```ocaml
(* Get the clipboard capability *)
let clipboard = Clipboard.require () in

(* Copy text to clipboard *)
clipboard.copy "Hello, world!"

(* Check if clipboard is available *)
if clipboard.copy_available () then
  clipboard.copy "Text to copy"
```

## Modal Pattern

This demo shows a common pattern: opening a modal to collect input, then copying it to clipboard on commit (Enter):

```ocaml
Miaou.Core.Modal_manager.push
  (module My_textbox_modal)
  ~init:(My_textbox_modal.init ())
  ~ui:{title = "Enter text"; ...}
  ~commit_on:["Enter"]
  ~cancel_on:["Esc"]
  ~on_close:(fun modal_ps outcome ->
    match outcome with
    | `Commit ->
        let text = get_text_from_modal modal_ps in
        (match Clipboard.get () with
        | Some clip -> clip.copy text
        | None -> ())
    | `Cancel -> ())
```

## Terminal Support

The OSC 52 sequence is supported by:
- iTerm2
- Alacritty
- kitty
- WezTerm
- Windows Terminal
- tmux (with `set-clipboard on`)
- Most modern terminal emulators

## Implementation Notes

- **Write-only**: Reading from clipboard (paste) is not supported because it requires asynchronous terminal responses. Use your terminal's native paste (Ctrl+Shift+V or Cmd+V) instead.
- **Driver registration**: Drivers must register the clipboard capability using `Clipboard.register ~write:(fun s -> output_string stdout s)`.
- **Fallback**: If OSC 52 is not available, miaou attempts to use native clipboard commands in the following order: `wl-copy` (Wayland), `xclip` (X11), `xsel` (X11), `pbcopy` (macOS).

## Interactive Demo

- **Space/Enter**: Open modal to enter text to copy
- **Enter in modal**: Copy the text and close modal
- **Esc in modal**: Cancel without copying
- **1-5**: Copy predefined samples directly
- **t**: Show this tutorial
- **Esc**: Return to launcher

Try opening the modal, typing text, and pressing Enter to copy it to your clipboard. Then paste in another application with Ctrl+V!
