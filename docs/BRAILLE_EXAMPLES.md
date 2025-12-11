# Braille Chart Rendering Examples

This document shows visual examples of ASCII vs Braille chart rendering modes.

## Sparkline Comparison

### ASCII Mode
Uses Unicode block characters ( ▂▃▄▅▆▇█) - one character per data point:

```
 ▂▃▄▅▆▇█▇▆▅▄▃▂ ▂▃▄▅▆▇█▇▆▅▄▃▂ ▂▃▄▅▆▇█ 63.5
```

### Braille Mode
Uses Unicode Braille patterns - 2×4 dots per cell for higher resolution:

```
⢀⡠⠤⠒⠉⠉⠉⠉⠒⠤⢄⡀⠀⢀⡠⠤⠒⠉⠉⠉⠉⠒⠤⢄⡀⠀⢀⡠⠤⠒⠉⠉ 63.5
```

The braille version shows smoother transitions between values due to higher resolution.

## Line Chart Comparison

### ASCII Mode
Uses symbols (●) and line characters:

```
Sine Wave Chart
        ●
      ●─╯
    ●─╯
  ●─╯
●─╯
╰─●
  ╰─●
    ╰─●
      ╰─●
        ●
```

### Braille Mode
Uses braille dots for smoother curves:

```
Sine Wave Chart
⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⡠⠤⠒⠒⠒⠒⠤⢄⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⢀⡠⠤⠒⠋⠁⠀⠀⠀⠀⠀⠀⠀⠀⠈⠉⠒⠤⢄⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⢀⡠⠤⠒⠉⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠉⠒⠤⢄⡀⠀⠀⠀⠀⠀
⠋⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠉⠒⠤⢄⡀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈
```

The braille mode creates a much smoother, more continuous curve.

## Bar Chart Comparison

### ASCII Mode
Uses block characters (█▀):

```
Weekly Sales
█      ███
█   █████
█ ██████
████████
████████
████████
████████
████████
Mon Tue Wed Thu Fri Sat Sun
```

### Braille Mode
Uses braille patterns for higher vertical resolution:

```
Weekly Sales
⠀⠀⠀⠀⠀⠀⠀⣿⣿⣿⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⣿⣿⣿⣿⣿⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⣿⣿⣿⣿⣿⣿⣿⣿⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⣿⣿⠀⠀⠀⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⠀⠀⠀⠀⠀⣿⣿⠀⠀⠀⣿⣿
⣿⣿⠀⠀⠀⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⠀⠀⠀⠀⠀⣿⣿⠀⠀⠀⣿⣿
Mon    Tue    Wed    Thu    Fri    Sat    Sun
```

Braille mode provides smoother gradations in bar height.

## Key Benefits of Braille Mode

1. **Higher Resolution**: 4× vertical resolution (2×4 dots vs 1 char)
2. **Smoother Curves**: Better representation of continuous data
3. **More Data Points**: Can show more detail in the same space
4. **Professional Look**: Cleaner, more polished appearance

## When to Use Each Mode

### Use ASCII Mode When:
- Maximum terminal compatibility is needed
- The terminal font doesn't support braille characters well
- Printing/exporting charts to systems that may not render braille
- Simple, bold visualization is preferred

### Use Braille Mode When:
- You need smoother, higher-resolution charts
- Terminal supports UTF-8 and has good braille font coverage
- Visualizing continuous data or smooth curves
- Maximum information density is important
- Professional/polished appearance is desired

## Terminal Compatibility

Braille mode works best with:
- Modern terminal emulators (iTerm2, Windows Terminal, GNOME Terminal, etc.)
- Monospace fonts with good Unicode coverage (Fira Code, JetBrains Mono, Cascadia Code)
- UTF-8 encoding enabled

Most modern terminals (2020+) support braille characters out of the box.
