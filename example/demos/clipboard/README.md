# Clipboard Demo

This demo shows how a Miaou application can copy text through the Clipboard
capability.

## What It Covers

- Quick-copy actions for fixed sample values
- A modal textbox workflow for user-entered text
- Driver capability checks before reporting success
- Toast feedback for successful, unavailable, and disabled clipboard states

## Controls

- `Space` or `Enter`: open the copy modal
- `1` to `5`: copy a predefined sample
- `t`: open this tutorial
- `Esc`: return to the launcher

## Notes

Drivers register the clipboard capability with
`Miaou_interfaces.Clipboard.register`. The default terminal drivers try native
clipboard tools first, then fall back to OSC 52 when native tools are missing.
