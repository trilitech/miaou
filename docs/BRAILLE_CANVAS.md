# Braille Canvas for High-Resolution Terminal Graphics

The `Braille_canvas` module provides a high-resolution canvas abstraction for terminal-based graphics using Unicode Braille patterns (U+2800–U+28FF).

## Overview

Each terminal character cell is typically used to display a single character. Braille patterns allow us to use each cell as a 2×4 grid of dots, effectively quadrupling the vertical resolution and doubling the horizontal resolution compared to character-based rendering.

### Resolution Improvement

- **Character-based**: 1 cell = 1 character
- **Braille-based**: 1 cell = 8 dots (2 columns × 4 rows)

For a terminal of width W and height H cells:
- Character resolution: W × H
- Braille resolution: (W×2) × (H×4) dots

## Braille Pattern Layout

Each braille character encodes 8 dots arranged as follows:

```
1 4
2 5
3 6
7 8
```

Dot positions are numbered 1-8 and correspond to Unicode offsets:
- Dot 1: +0x01, Dot 2: +0x02, Dot 3: +0x04, Dot 4: +0x08
- Dot 5: +0x10, Dot 6: +0x20, Dot 7: +0x40, Dot 8: +0x80

The base Unicode code point for braille is U+2800 (blank braille pattern). Adding combinations of the above offsets produces different patterns.

## Usage Examples

### Basic Canvas

```ocaml
open Miaou_widgets_display

(* Create a 10×5 cell canvas (20×20 dot resolution) *)
let canvas = Braille_canvas.create ~width:10 ~height:5 in

(* Set individual dots *)
Braille_canvas.set_dot canvas ~x:5 ~y:10 ;
Braille_canvas.set_dot canvas ~x:6 ~y:10 ;
Braille_canvas.set_dot canvas ~x:7 ~y:10 ;

(* Render to string *)
let output = Braille_canvas.render canvas in
print_endline output
```

### Drawing Lines

```ocaml
(* Draw a diagonal line *)
let canvas = Braille_canvas.create ~width:20 ~height:10 in
Braille_canvas.draw_line canvas ~x0:0 ~y0:0 ~x1:39 ~y1:39 ;

(* Draw a triangle *)
Braille_canvas.draw_line canvas ~x0:20 ~y0:0 ~x1:0 ~y1:39 ;
Braille_canvas.draw_line canvas ~x0:0 ~y0:39 ~x1:39 ~y1:39 ;

let output = Braille_canvas.render canvas in
print_endline output
```

### Using with Chart Widgets

The braille canvas is automatically used by chart widgets when you select `Braille` mode:

```ocaml
open Miaou_widgets_display

(* Sparkline with braille rendering *)
let sparkline = Sparkline_widget.create ~width:40 ~max_points:80 () in
for i = 0 to 79 do
  let value = 50.0 +. 30.0 *. sin (float_of_int i /. 10.0) in
  Sparkline_widget.push sparkline value
done ;
let output = 
  Sparkline_widget.render 
    sparkline 
    ~focus:false 
    ~show_value:true 
    ~mode:Braille 
    () in
print_endline output

(* Line chart with braille rendering *)
let points = List.init 50 (fun i ->
  let x = float_of_int i in
  let y = x *. x /. 10.0 in
  { Line_chart_widget.x; y; color = None }
) in
let chart = Line_chart_widget.create
  ~width:60
  ~height:20
  ~series:[{ label = "Parabola"; points; color = None }]
  ~title:"y = x²/10"
  () in
let output = 
  Line_chart_widget.render 
    chart 
    ~show_axes:false 
    ~show_grid:false 
    ~mode:Braille 
    () in
print_endline output
```

## API Reference

### Creation

```ocaml
val create : width:int -> height:int -> t
```
Create a new braille canvas with the specified dimensions in cells. The actual dot resolution will be `width * 2` × `height * 4`.

### Dot Manipulation

```ocaml
val set_dot : t -> x:int -> y:int -> unit
```
Set a single dot at the given coordinates. Coordinates are in dots (0-indexed). Out-of-bounds coordinates are silently ignored.

```ocaml
val clear_dot : t -> x:int -> y:int -> unit
```
Clear a single dot at the given coordinates.

```ocaml
val get_dot : t -> x:int -> y:int -> bool
```
Check if a dot is set at the given coordinates. Returns `false` for out-of-bounds.

```ocaml
val clear : t -> unit
```
Clear all dots in the canvas.

### Drawing Primitives

```ocaml
val draw_line : t -> x0:int -> y0:int -> x1:int -> y1:int -> unit
```
Draw a line between two points using Bresenham's algorithm.

### Rendering

```ocaml
val render : t -> string
```
Render the canvas to a string with newlines separating rows. Each cell is rendered as a braille character (U+2800–U+28FF).

### Utilities

```ocaml
val get_dimensions : t -> int * int
```
Get canvas dimensions in cells (not dots).

```ocaml
val get_dot_dimensions : t -> int * int
```
Get canvas dimensions in dots (actual resolution).

## Technical Details

### UTF-8 Encoding

Braille characters are in the Unicode range U+2800–U+28FF, which requires 3 bytes in UTF-8:
- First byte: 0xE0 | (codepoint >> 12)
- Second byte: 0x80 | ((codepoint >> 6) & 0x3F)
- Third byte: 0x80 | (codepoint & 0x3F)

The `render` function handles this encoding automatically.

### Memory Layout

The canvas internally stores cells as an array of arrays of integers, where each integer represents the 8-bit braille pattern for that cell (0-255).

### Performance

- Setting/getting dots: O(1)
- Drawing lines: O(max(dx, dy)) where dx and dy are the line dimensions
- Rendering: O(width × height) cells

## Comparison: ASCII vs Braille

### Sparkline Example

**ASCII Mode** (one character per data point):
```
 ▂▃▄▅▆▇█▇▆▅▄▃▂  
```

**Braille Mode** (higher resolution):
```
⠀⠁⠃⠇⡇⣇⣧⣷⣿⣷⣧⣇⡇⠇⠃⠁
```

### Line Chart Example

**ASCII Mode**:
```
10 │     ●
 8 │   ●─╯
 6 │ ●─╯
 4 │─╯
```

**Braille Mode** (smoother curves):
```
⠀⠀⠀⠀⠀⠀⠀⠀⢀⡠
⠀⠀⠀⠀⣀⡤⠖⠋⠁⠀
⣀⡤⠖⠋⠁⠀⠀⠀⠀⠀
```

## Limitations

1. **Terminal Support**: Not all terminals correctly render braille characters. UTF-8 terminals work best.
2. **Font Requirements**: The terminal font must include braille characters (most modern fonts do).
3. **No Color Per Dot**: While ANSI color codes can be applied to entire cells, individual dots within a cell cannot have different colors.
4. **Readability**: Very fine patterns may be hard to distinguish depending on font size and terminal settings.

## Best Practices

1. **Test in Target Environment**: Always verify braille output in the actual terminal where it will be displayed.
2. **Provide ASCII Fallback**: Offer `render_mode` parameters to switch between ASCII and Braille modes.
3. **Consider Scale**: Braille works best for charts with enough data points to show meaningful patterns at higher resolution.
4. **Document Mode Options**: Make it clear to users when and how to use braille mode vs ASCII mode.

## Related Modules

- `Sparkline_widget`: Compact inline time-series with braille support
- `Line_chart_widget`: Multi-series line charts with braille support
- `Bar_chart_widget`: Vertical bar charts with braille support
