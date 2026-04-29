# Inline CLI Demo

A small "What's in this directory?" listing rendered as a normal MIAOU page.

What makes this demo "inline" is **how it's launched**, not the page itself:
the matrix driver honours `MIAOU_INLINE_MODE=1`, which skips the alt-screen
escape sequences. The TUI then renders over the current terminal contents and
the final frame stays in the user's scrollback after quit — like a classic CLI
output.

## Running

The provided `run.sh` script sets the right environment variables:

```sh
./example/demos/inline_cli/run.sh
```

That is equivalent to:

```sh
MIAOU_DRIVER=matrix MIAOU_INLINE_MODE=1 \
  dune exec example/demos/inline_cli/main.exe
```

After you press `q` to quit, the listing remains visible in your terminal's
scrollback — try scrolling up after it exits.

You can still launch the demo from the gallery launcher; it works perfectly
in alt-screen mode too. The "inline" idiom is purely about the launcher
script that sets the environment variable.

## Keys

- `r` — refresh the directory listing.
- `q` or `Esc` — quit.
- `t` — open this tutorial.

## Limitations

The page lists at most the first 10 entries of `Sys.readdir "."` (sorted) so
the inline strip stays short.
