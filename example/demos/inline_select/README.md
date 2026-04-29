# Inline Select Demo

Wraps `Miaou_widgets_input.Select_widget.open_centered` in a regular page so
the user can pick from a list "inline" — that is, the selector is part of the
page body rather than a centred modal dialog.

The page is still rendered on the alt-screen; "inline" here is purely a visual
idiom: the selector pops up in the page rather than as a dialog over a dimmed
backdrop.

## Steps

1. Use `Up` / `Down` (or `j` / `k`) to move the cursor.
2. Press `Enter` to confirm. The chosen value is shown below the selector.
3. Press `r` to reset and pick again.
4. Press `Esc` to return to the launcher.
5. Press `t` to open this tutorial.
