# Color Usage Guide

This document explains how to use colors in Miaou widgets, particularly for charts and sparklines.

## ANSI SGR Color Codes

Miaou widgets use **ANSI SGR (Select Graphic Rendition) color codes** as strings for coloring elements. These are **not** terminal palette indices (0-255).

### Basic Foreground Colors

Use these string values for the `color` parameter:

| Code   | Color         | Example Usage                    |
|--------|---------------|----------------------------------|
| `"30"` | Black         | `color = Some "30"`              |
| `"31"` | Red           | `color = Some "31"`              |
| `"32"` | Green         | `color = Some "32"`              |
| `"33"` | Yellow        | `color = Some "33"`              |
| `"34"` | Blue          | `color = Some "34"`              |
| `"35"` | Magenta       | `color = Some "35"`              |
| `"36"` | Cyan          | `color = Some "36"`              |
| `"37"` | White         | `color = Some "37"`              |

### Bright Foreground Colors

For brighter, more vivid colors:

| Code   | Color             | Example Usage                    |
|--------|-------------------|----------------------------------|
| `"90"` | Bright Black/Gray | `color = Some "90"`              |
| `"91"` | Bright Red        | `color = Some "91"`              |
| `"92"` | Bright Green      | `color = Some "92"`              |
| `"93"` | Bright Yellow     | `color = Some "93"`              |
| `"94"` | Bright Blue       | `color = Some "94"`              |
| `"95"` | Bright Magenta    | `color = Some "95"`              |
| `"96"` | Bright Cyan       | `color = Some "96"`              |
| `"97"` | Bright White      | `color = Some "97"`              |

## Common Pitfalls

### ❌ Incorrect: Using palette indices
```ocaml
(* This will NOT work as expected *)
let point = { x = 1.0; y = 2.0; color = Some "10" }  (* Not a valid color *)
```

### ✅ Correct: Using ANSI SGR codes
```ocaml
(* Use ANSI color code numbers as strings *)
let point = { x = 1.0; y = 2.0; color = Some "32" }  (* Green *)
```

## Widget-Specific Color Usage

### Line Charts

Line charts support colors at multiple levels with a specific precedence:

**Color Precedence (highest to lowest):**
1. **Point-level color** - Individual point's `color` field
2. **Series-level color** - The series' default `color` field
3. **Threshold-based color** - Applied based on Y-axis values when point and series colors are `None`

**Example:**
```ocaml
open Miaou_widgets_display

(* Create points with mixed coloring *)
let points = [
  { x = 1.0; y = 20.0; color = Some "32" };  (* Green - point-level override *)
  { x = 2.0; y = 50.0; color = None };       (* Will use series color *)
  { x = 3.0; y = 85.0; color = None };       (* Will use series color *)
] in

(* Create a series with a default red color *)
let series = {
  label = "Temperature";
  points;
  color = Some "31";  (* Red - series-level default *)
} in

(* Define thresholds (only apply when point and series colors are None) *)
let thresholds = [
  { value = 70.0; color = "33" };  (* Yellow for values > 70 *)
  { value = 90.0; color = "31" };  (* Red for values > 90 *)
] in

let chart = Line_chart_widget.create
  ~width:60
  ~height:15
  ~series:[series]
  ~title:"System Temperature"
  () in

Line_chart_widget.render chart
  ~show_axes:true
  ~show_grid:true
  ~thresholds
  ()
```

In this example:
- The first point (y=20) will be **green** (point-level color)
- The second point (y=50) will be **red** (series-level color)
- The third point (y=85) will be **red** (series-level color)
- If series color were `None`, points 2 and 3 would use threshold colors (yellow for y=50, red for y=85)

### Sparklines

Sparklines support:
- A default color for the entire sparkline
- Threshold-based coloring for segments exceeding certain values

**Example:**
```ocaml
open Miaou_widgets_display

let spark = Sparkline_widget.create ~width:30 ~max_points:30 () in

(* Add some data *)
List.iter (Sparkline_widget.push spark) [
  10.; 25.; 50.; 75.; 90.; 85.; 60.; 30.; 15.;
] in

(* Define color thresholds: green->yellow->red gradient *)
let thresholds = [
  { value = 50.0; color = "33" };  (* Yellow for values > 50 *)
  { value = 80.0; color = "31" };  (* Red for values > 80 *)
] in

(* Render with default green color and thresholds *)
let output = Sparkline_widget.render spark
  ~focus:true
  ~show_value:true
  ~color:"32"  (* Default green for values <= 50 *)
  ~thresholds
  () in

print_endline output
```

This creates a sparkline where:
- Values ≤ 50 are green
- Values > 50 and ≤ 80 are yellow
- Values > 80 are red

### Bar Charts

Bar charts support color for individual bars:

```ocaml
open Miaou_widgets_display

let bars = [
  { label = "p50"; value = 12.3; color = Some "32" };  (* Green *)
  { label = "p90"; value = 45.8; color = Some "33" };  (* Yellow *)
  { label = "p99"; value = 89.2; color = Some "31" };  (* Red *)
] in

let chart = Bar_chart_widget.create
  ~title:"Response Time Percentiles (ms)"
  ~bars
  () in

Bar_chart_widget.render chart
```

## Best Practices

### 1. Consistent Color Semantics
Use colors consistently across your application:
- 🟢 Green (`"32"`, `"92"`) - Good/Normal/Success
- 🟡 Yellow (`"33"`, `"93"`) - Warning/Moderate
- 🔴 Red (`"31"`, `"91"`) - Critical/Error/High
- 🔵 Blue (`"34"`, `"94"`) - Info/Neutral
- ⚪ Cyan (`"36"`, `"96"`) - Secondary information

### 2. Accessibility
- Use bright colors (`"9x"`) for better visibility on dark terminals
- Don't rely solely on color to convey information (use labels, values, or symbols too)
- Test your UI in different terminal color schemes

### 3. Terminal Compatibility
- ANSI SGR codes are widely supported across modern terminals
- Basic colors (`"30"`-`"37"`) have the best compatibility
- Bright colors (`"90"`-`"97"`) are supported in most modern terminals
- The SDL2 backend supports full RGB colors with enhanced rendering

### 4. Gradients and Thresholds
For metrics that have natural ranges (CPU %, temperature, latency):

```ocaml
(* Example: CPU usage coloring *)
let cpu_thresholds = [
  { value = 50.0; color = "33" };   (* Yellow at 50% *)
  { value = 80.0; color = "91" };   (* Bright red at 80% *)
] in

(* Values below 50% will use default color (e.g., green) *)
let default_color = "32"  (* Green *)
```

## Reference Examples

See the following files for practical examples:
- `example/demo_lib.ml` - Charts with various color configurations
- `example/system_metrics.ml` - Real-time metrics with color thresholds
- `example/diagnostics_dashboard.ml` - Advanced multi-chart dashboard (if available)

## Further Reading

- [ANSI escape codes (Wikipedia)](https://en.wikipedia.org/wiki/ANSI_escape_code)
- Miaou widget documentation in `src/miaou_widgets_display/*.mli`
- [SDL2 backend color guide](../src/miaou_widgets_display/SDL_CHARTS_README.md)
