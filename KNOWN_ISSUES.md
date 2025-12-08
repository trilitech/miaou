# Known Issues and Limitations

## Bar Chart UTF-8 Display Issues

**Symptoms:** Bar chart blocks appear as mangled characters (`����`) instead of proper Unicode blocks (█, ▀).

**Cause:** This is a terminal encoding configuration issue, not a Miaou bug. The terminal must be configured to use UTF-8 encoding.

**Solutions:**
1. Ensure your terminal is set to UTF-8 encoding (most modern terminals default to this)
2. Check your `LANG` environment variable: `echo $LANG` (should contain `UTF-8`)
3. If using bash, add to `~/.bashrc`: `export LANG=en_US.UTF-8`
4. For zsh, add to `~/.zshrc`: `export LANG=en_US.UTF-8`
5. As a workaround, set `MIAOU_ASCII=1` to use ASCII characters instead of Unicode blocks

## Mouse Mode Not Disabled on Abnormal Exit

**Symptoms:** After pressing Ctrl+C in a demo, the terminal reports "unbound keyseq mouse" errors when using the mouse wheel.

**Cause:** Signal handlers that cleanup mouse tracking modes are installed, but in some cases (especially with nested signal handlers or when running under debuggers), the cleanup may not execute.

**Solutions:**
1. Run `reset` command to restore terminal to default state
2. Or manually disable mouse tracking: `printf '\033[?1000l\033[?1002l\033[?1003l'`
3. Use proper exit methods (Esc key, q key) instead of Ctrl+C when possible

**Status:** The drivers properly install signal handlers for cleanup. This issue may be environment-specific or related to how the demo is terminated.

## Help Hint Documentation

The Help_hint module is fully documented in `src/miaou_core/help_hint.mli`. Key points:

- The driver intercepts "?" key presses before they reach your `handle_key` function
- Use `Help_hint.set`, `Help_hint.push`, and `Help_hint.pop` to manage contextual help
- See examples in the .mli file for usage patterns

This is working as designed and is well-documented.
