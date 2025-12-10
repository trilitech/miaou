# Add Charts Widgets to MIAOU

**Goal**: Add terminal-based charting capabilities for monitoring and data visualization in octez-manager/octez-setup.

**Context**: Mosaic has `Mosaic_charts` with sparklines and plot capabilities. MIAOU needs similar functionality for real-time monitoring (CPU, memory, network) and historical metrics visualization.

**Timeline**: 7-10 days
- Days 1-2: Foundation and API design
- Days 3-5: Sparkline widget
- Days 6-7: Line chart widget
- Days 8-10: Polish and optional features (bar chart, braille rendering)

---

## Target Use Cases

### Primary (octez-manager monitoring):
- Real-time resource monitoring (CPU, memory, disk, network)
- Node performance metrics over time
- Baker statistics (blocks, endorsements, rewards)
- Blockchain sync progress visualization
- Network health (peer count, bandwidth trends)

### Secondary:
- Historical data analysis (operations/sec, gas usage)
- Comparative metrics (multiple nodes, time periods)
- Alert thresholds visualization

---

## Widgets to Implement

### 1. Sparkline Widget (Priority: 🔴 CRITICAL)

**Location**: `src/miaou_widgets_display/sparkline_widget.ml` + `.mli`

**Purpose**: Compact inline time-series visualization using Unicode block characters.

**API Design**:
```ocaml
type t

(** Create a sparkline with fixed width.
    @param width Display width in characters
    @param max_points Maximum data points to retain (circular buffer)
    @param min_value Optional fixed minimum (default: auto-scale)
    @param max_value Optional fixed maximum (default: auto-scale)
*)
val create :
  width:int ->
  max_points:int ->
  ?min_value:float ->
  ?max_value:float ->
  unit -> t

(** Add a data point to the sparkline. Older points are dropped when max_points exceeded. *)
val push : t -> float -> unit

(** Render the sparkline using block characters (▁▂▃▄▅▆▇█).
    @param focus Whether to highlight (bold/color)
    @param show_value If true, append current value as text
*)
val render : t -> focus:bool -> show_value:bool -> string

(** Render with a label prefix. Example: "CPU: [▁▂▃▄▅▆▇█] 78%" *)
val render_with_label : t -> label:string -> focus:bool -> string

(** Get current statistics *)
val stats : t -> (float * float * float)  (* min, max, current *)

(** Clear all data points *)
val clear : t -> unit
```

**Implementation Details**:

1. **Data Storage**:
   - Use `float Queue.t` for circular buffer (efficient push/pop)
   - Track `min_val` and `max_val` for auto-scaling
   - Store `max_points` to limit memory

2. **Rendering Algorithm**:
   ```ocaml
   (* Use 8-level Unicode block characters *)
   let blocks = [|" "; "▁"; "▂"; "▃"; "▄"; "▅"; "▆"; "▇"; "█"|]

   (* Normalize value to 0-8 range *)
   let normalize value min_val max_val =
     let range = max_val -. min_val in
     if range = 0. then 4  (* Middle block for flat line *)
     else
       let ratio = (value -. min_val) /. range in
       min 8 (max 0 (int_of_float (ratio *. 8.)))

   (* Render each data point *)
   let render_point value = blocks.(normalize value min_val max_val)
   ```

3. **Color Support** (optional):
   - Green for low values (< 33%)
   - Yellow for medium values (33-66%)
   - Red for high values (> 66%)
   - Use `Palette` module for colors

4. **Label Formatting**:
   ```ocaml
   let render_with_label t ~label ~focus =
     let spark = render t ~focus ~show_value:false in
     let current = Queue.peek_tail t.data in
     Printf.sprintf "%s: [%s] %.1f%%" label spark current
   ```

**Tests** (`test/test_charts.ml`):
- [ ] Empty sparkline renders as spaces
- [ ] Single value renders middle block
- [ ] Ascending values render ▁▂▃▄▅▆▇█
- [ ] Descending values render █▇▆▅▄▃▂▁
- [ ] Flat line renders same block
- [ ] Circular buffer drops oldest when max_points exceeded
- [ ] Auto-scaling adjusts to data range
- [ ] Fixed min/max clamps values

**Demo Usage**:
```ocaml
(* In octez-manager demo *)
let cpu_spark = Sparkline_widget.create ~width:30 ~max_points:30 () in
let mem_spark = Sparkline_widget.create ~width:30 ~max_points:30 () in

(* Update on timer *)
let update_metrics () =
  Sparkline_widget.push cpu_spark (get_cpu_usage ());
  Sparkline_widget.push mem_spark (get_mem_usage ());

(* Render in view *)
Sparkline_widget.render_with_label cpu_spark ~label:"CPU" ~focus:true
Sparkline_widget.render_with_label mem_spark ~label:"MEM" ~focus:false
```

**Expected Output**:
```
CPU: [▁▂▃▄▅▆▇█▇▆▅▄▃▂▁▂▃▄▅▆▇] 68.3%
MEM: [▄▄▄▅▅▅▆▆▆▇▇▇███████▇▇] 87.1%
NET: [▁▁▁▂▂▃▄▅▃▂▂▁▁▁▁▁▁▁▁▁] 2.4MB/s
```

---

### 2. Line Chart Widget (Priority: 🔴 CRITICAL)

**Location**: `src/miaou_widgets_display/line_chart_widget.ml` + `.mli`

**Purpose**: Multi-line time-series chart with axes, labels, and grid.

**API Design**:
```ocaml
type point = { x: float; y: float }

type series = {
  label: string;
  points: point list;
  color: Palette.color option;
}

type axis_config = {
  show_labels: bool;
  x_label: string;
  y_label: string;
  x_ticks: int;  (* Number of tick marks on X axis *)
  y_ticks: int;  (* Number of tick marks on Y axis *)
}

type t

(** Create a line chart.
    @param width Chart width in characters
    @param height Chart height in rows
    @param series List of data series to plot
    @param title Optional chart title
*)
val create :
  width:int ->
  height:int ->
  series:series list ->
  ?title:string ->
  unit -> t

(** Render the chart.
    @param show_axes Whether to draw axes with ticks and labels
    @param show_grid Whether to draw background grid lines
*)
val render : t -> show_axes:bool -> show_grid:bool -> string

(** Update a series by label *)
val update_series : t -> label:string -> points:point list -> unit

(** Add a single point to a series *)
val add_point : t -> label:string -> point:point -> unit

(** Configure axes *)
val set_axes : t -> axis_config -> unit
```

**Implementation Details**:

1. **Coordinate Mapping**:
   ```ocaml
   (* Map data coordinates to terminal grid coordinates *)
   let map_x x x_min x_max width =
     let ratio = (x -. x_min) /. (x_max -. x_min) in
     int_of_float (ratio *. float_of_int (width - 1))

   let map_y y y_min y_max height =
     let ratio = (y -. y_min) /. (y_max -. y_min) in
     (* Invert Y because terminal coordinates go top-down *)
     height - 1 - int_of_float (ratio *. float_of_int (height - 1))
   ```

2. **Grid Representation**:
   ```ocaml
   type cell = {
     mutable char: string;
     mutable style: Palette.style option;
   }

   let grid = Array.make_matrix height width { char = " "; style = None }
   ```

3. **Line Drawing** (Bresenham's algorithm simplified):
   ```ocaml
   let draw_line grid x1 y1 x2 y2 char =
     let dx = abs (x2 - x1) in
     let dy = abs (y2 - y1) in
     let sx = if x1 < x2 then 1 else -1 in
     let sy = if y1 < y2 then 1 else -1 in
     let rec loop x y err =
       if x >= 0 && x < width && y >= 0 && y < height then
         grid.(y).(x).char <- char;
       if x = x2 && y = y2 then ()
       else
         let e2 = 2 * err in
         let (x', err') =
           if e2 > -dy then (x + sx, err - dy) else (x, err)
         in
         let (y', err'') =
           if e2 < dx then (y + sy, err' + dx) else (y, err')
         in
         loop x' y' err''
     in
     loop x1 y1 (dx - dy)
   ```

4. **Axis Rendering**:
   ```ocaml
   let render_y_axis grid y_min y_max y_ticks height =
     (* Draw vertical line on left *)
     for y = 0 to height - 1 do
       grid.(y).(0).char <- "│"
     done;

     (* Draw tick marks and labels *)
     for i = 0 to y_ticks do
       let y = i * height / y_ticks in
       grid.(y).(0).char <- "├";
       let value = y_max -. (float_of_int i /. float_of_int y_ticks) *. (y_max -. y_min) in
       (* Format and draw label to the left *)
     done;
     grid.(height - 1).(0).char <- "└"

   let render_x_axis grid x_min x_max x_ticks width height =
     (* Draw horizontal line on bottom *)
     for x = 0 to width - 1 do
       grid.(height - 1).(x).char <- "─"
     done;

     (* Draw tick marks *)
     for i = 0 to x_ticks do
       let x = i * width / x_ticks in
       grid.(height - 1).(x).char <- "┴"
     done;
     grid.(height - 1).(0).char <- "└"
   ```

5. **Grid Lines** (optional background):
   ```ocaml
   let render_grid grid x_ticks y_ticks =
     (* Horizontal grid lines *)
     for i = 1 to y_ticks - 1 do
       let y = i * height / y_ticks in
       for x = 1 to width - 1 do
         if grid.(y).(x).char = " " then
           grid.(y).(x).char <- "·"  (* or "┈" for dashed *)
       done
     done;
     (* Vertical grid lines similarly *)
   ```

6. **Multi-Series Rendering**:
   ```ocaml
   let plot_symbols = [|"●"; "■"; "▲"; "◆"; "★"|]  (* Different per series *)

   List.iteri (fun idx series ->
     let symbol = plot_symbols.(idx mod 5) in
     List.iter (fun point ->
       let x = map_x point.x x_min x_max width in
       let y = map_y point.y y_min y_max height in
       if x >= 0 && x < width && y >= 0 && y < height then
         grid.(y).(x).char <- symbol;
         grid.(y).(x).style <- series.color
     ) series.points
   ) t.series
   ```

**Tests** (`test/test_charts.ml`):
- [ ] Empty chart renders empty box
- [ ] Single point renders correctly
- [ ] Two points draw a line
- [ ] Horizontal line renders correctly
- [ ] Vertical line renders correctly
- [ ] Diagonal line renders correctly
- [ ] Multiple series don't overwrite each other
- [ ] Axes render with correct tick positions
- [ ] Labels are formatted correctly
- [ ] Out-of-bounds points are clipped
- [ ] Auto-scaling finds correct min/max

**Demo Usage**:
```ocaml
(* Historical block times *)
let block_times = [
  { x = 0.; y = 2.1 };
  { x = 1.; y = 2.3 };
  { x = 2.; y = 1.9 };
  (* ... *)
] in

let chart = Line_chart_widget.create
  ~width:60
  ~height:15
  ~series:[
    { label = "Block Time"; points = block_times; color = Some green };
  ]
  ~title:"Block Production Time (seconds)"
  () in

Line_chart_widget.render chart ~show_axes:true ~show_grid:false
```

**Expected Output**:
```
Block Production Time (seconds)
2.5 │       ╭●╮
2.0 │    ╭──╯ ╰──●─╮
1.5 │  ●─╯         ╰─●
1.0 │╭─╯              ╰─
0.5 │╯
    └────────────────────
    0   5   10  15   20
        Time (blocks)
```

---

### 3. Bar Chart Widget (Priority: 🟡 NICE-TO-HAVE)

**Location**: `src/miaou_widgets_display/bar_chart_widget.ml` + `.mli`

**Purpose**: Compare discrete values (peer counts, operation types, etc.)

**API Design**:
```ocaml
type bar = {
  label: string;
  value: float;
  color: Palette.color option;
}

type orientation = Horizontal | Vertical

type t

val create :
  bars:bar list ->
  ?orientation:orientation ->
  ?width:int ->
  ?height:int ->
  ?title:string ->
  unit -> t

val render : t -> string

val update_bar : t -> label:string -> value:float -> unit
```

**Implementation Details**:

1. **Horizontal Bars** (easier to implement first):
   ```ocaml
   (* Each bar is one row *)
   let render_horizontal_bar bar max_width max_value =
     let bar_width = int_of_float (bar.value /. max_value *. float_of_int max_width) in
     let filled = String.make bar_width '█' in
     let empty = String.make (max_width - bar_width) '░' in
     Printf.sprintf "%-15s │%s%s│ %.1f" bar.label filled empty bar.value
   ```

2. **Vertical Bars** (more complex, column-based):
   ```ocaml
   (* Build grid where each column is a bar *)
   (* Use block characters for partial fills: ▁▂▃▄▅▆▇█ *)
   ```

**Tests**:
- [ ] Single bar renders correctly
- [ ] Multiple bars scale to max value
- [ ] Zero-value bar renders empty
- [ ] Labels are aligned
- [ ] Colors are applied
- [ ] Horizontal and vertical modes work

**Demo Usage**:
```ocaml
let peer_stats = Bar_chart_widget.create
  ~bars:[
    { label = "Mainnet"; value = 45.0; color = Some green };
    { label = "Testnet"; value = 23.0; color = Some yellow };
    { label = "Private"; value = 12.0; color = Some blue };
  ]
  ~orientation:Horizontal
  ~title:"Active Peers by Network"
  () in

Bar_chart_widget.render peer_stats
```

**Expected Output**:
```
Active Peers by Network
Mainnet         │████████████████████████████████░░░░░│ 45
Testnet         │████████████████░░░░░░░░░░░░░░░░░░░░░│ 23
Private         │████████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░│ 12
```

---

### 4. Braille Sparkline (Priority: 🟢 OPTIONAL)

**Location**: `src/miaou_widgets_display/braille_sparkline_widget.ml` + `.mli`

**Purpose**: Higher-resolution sparklines using Braille Unicode (2×4 sub-pixel grid per character)

**API Design**: Same as `Sparkline_widget` but with `use_braille:bool` parameter

**Implementation Details**:

1. **Braille Encoding**:
   ```ocaml
   (* Braille Unicode: U+2800 - U+28FF *)
   (* Each character has 8 dots in 2×4 grid:
      ┌─┬─┐
      │1│4│
      ├─┼─┤
      │2│5│
      ├─┼─┤
      │3│6│
      ├─┼─┤
      │7│8│
      └─┴─┘
   *)

   let braille_base = 0x2800

   let make_braille dots =
     (* dots is a list of positions 1-8 *)
     let code = List.fold_left (fun acc dot ->
       acc lor (1 lsl (dot - 1))
     ) 0 dots in
     Uchar.to_int (Uchar.of_int (braille_base + code))

   (* For sparkline, use dots 1-4 for left half, 5-8 for right half *)
   let render_braille_sparkline values =
     (* Each character holds 2 data points (left and right columns) *)
     (* Map value to height level 0-4, then set dots *)
   ```

2. **Resolution Advantage**:
   - Normal: 1 value per character (8 levels)
   - Braille: 2 values per character, 4 levels each
   - Effectively doubles horizontal resolution

**Tests**:
- [ ] Braille rendering produces valid Unicode
- [ ] Two values per character works
- [ ] Height levels map correctly
- [ ] Comparison with block-char version

**Expected Output**:
```
CPU: ⣀⣤⣶⣿⣿⣿⣶⣤⣀ 78%  (vs block: ▁▃▅▇███▇▅▃▁)
```

---

## Module Structure

```
src/miaou_widgets_display/
├── sparkline_widget.ml        # Block-character sparklines
├── sparkline_widget.mli
├── line_chart_widget.ml       # Multi-line charts with axes
├── line_chart_widget.mli
├── bar_chart_widget.ml        # Horizontal/vertical bar charts
├── bar_chart_widget.mli
├── braille_sparkline_widget.ml  # (optional) Higher-res sparklines
├── braille_sparkline_widget.mli
└── chart_utils.ml             # Shared helpers (scaling, formatting)

test/
├── test_charts.ml             # All chart widget tests
└── test_chart_rendering.ml    # Visual regression tests

example/
└── demo_lib.ml                # Add "Charts Demo" entry
```

---

## Shared Utilities (`chart_utils.ml`)

```ocaml
(** Shared charting utilities *)

(** Find min/max in a list of floats *)
val bounds : float list -> (float * float)

(** Scale a value from data range to display range *)
val scale : value:float -> min_val:float -> max_val:float -> display_max:int -> int

(** Format a float for display (smart precision) *)
val format_value : float -> string

(** Format axis label with units *)
val format_label : value:float -> unit:string -> string

(** Generate tick positions *)
val tick_positions : count:int -> max:int -> int list

(** Round to nice numbers for axis labels *)
val nice_number : float -> round_up:bool -> float
```

---

## Integration with Existing Widgets

### In `miaou_widgets_display/dune`:
```lisp
(library
 (name miaou_widgets_display)
 (public_name miaou.widgets.display)
 (libraries miaou_core miaou_interfaces miaou_helpers)
 (modules
   widgets
   palette
   table_widget
   tree_widget
   pager_widget
   description_list
   sparkline_widget          ;; ADD
   line_chart_widget         ;; ADD
   bar_chart_widget          ;; ADD
   braille_sparkline_widget  ;; ADD (optional)
   chart_utils))             ;; ADD
```

### In `src/miaou.ml` (umbrella):
```ocaml
module Widgets = struct
  module Display = struct
    (* existing *)
    module Table = Miaou_widgets_display.Table_widget
    module Tree = Miaou_widgets_display.Tree_widget
    (* ... *)

    (* NEW *)
    module Sparkline = Miaou_widgets_display.Sparkline_widget
    module Line_chart = Miaou_widgets_display.Line_chart_widget
    module Bar_chart = Miaou_widgets_display.Bar_chart_widget
  end
end
```

---

## Demo Page

**Add to `example/demo_lib.ml`**:

```ocaml
(* Charts Demo Page *)
module Charts_demo_page : Tui_page.PAGE_SIG = struct
  type state = {
    cpu_spark: Sparkline_widget.t;
    mem_spark: Sparkline_widget.t;
    net_spark: Sparkline_widget.t;
    tick_count: int;
  }

  type msg = Tick | Quit

  let init () =
    {
      cpu_spark = Sparkline_widget.create ~width:40 ~max_points:40 ();
      mem_spark = Sparkline_widget.create ~width:40 ~max_points:40 ();
      net_spark = Sparkline_widget.create ~width:40 ~max_points:40 ();
      tick_count = 0;
    }

  let update st = function
    | Tick ->
        (* Simulate random metrics *)
        let cpu = 30. +. Random.float 40. in
        let mem = 60. +. Random.float 30. in
        let net = Random.float 100. in
        Sparkline_widget.push st.cpu_spark cpu;
        Sparkline_widget.push st.mem_spark mem;
        Sparkline_widget.push st.net_spark net;
        { st with tick_count = st.tick_count + 1 }
    | Quit -> st

  let view st ~focus ~size =
    let header = "Charts Demo - Press 'q' to quit" in
    let sep = String.make 60 '─' in

    let sparklines = [
      "";
      "Real-time Metrics (Sparklines):";
      "";
      Sparkline_widget.render_with_label st.cpu_spark ~label:"CPU Usage" ~focus;
      Sparkline_widget.render_with_label st.mem_spark ~label:"Memory" ~focus;
      Sparkline_widget.render_with_label st.net_spark ~label:"Network" ~focus;
      "";
      sep;
    ] in

    (* TODO: Add line chart example *)
    (* TODO: Add bar chart example *)

    let lines = header :: sep :: sparklines in
    String.concat "\n" lines

  (* ... rest of PAGE_SIG implementation ... *)
end

(* Register in launcher *)
let () = Registry.register "Charts Demo" (module Charts_demo_page)
```

---

## Testing Strategy

### Unit Tests (`test/test_charts.ml`):
```ocaml
open Alcotest

let test_sparkline_empty () =
  let sp = Sparkline_widget.create ~width:10 ~max_points:10 () in
  let output = Sparkline_widget.render sp ~focus:false ~show_value:false in
  check string "empty sparkline" (String.make 10 ' ') output

let test_sparkline_ascending () =
  let sp = Sparkline_widget.create ~width:8 ~max_points:8 () in
  for i = 0 to 7 do
    Sparkline_widget.push sp (float_of_int i)
  done;
  let output = Sparkline_widget.render sp ~focus:false ~show_value:false in
  check string "ascending" "▁▂▃▄▅▆▇█" output

let test_line_chart_single_point () =
  let chart = Line_chart_widget.create
    ~width:10
    ~height:5
    ~series:[{ label = "test"; points = [{ x = 5.; y = 2.5 }]; color = None }]
    () in
  let output = Line_chart_widget.render chart ~show_axes:false ~show_grid:false in
  (* Check that point is rendered in center *)
  check (list string) "single point" [...] (String.split_on_char '\n' output)

(* Add 20+ more tests covering edge cases *)
```

### Visual Regression Tests (`test/test_chart_rendering.ml`):
```ocaml
(* Using headless driver to capture rendered output *)
let test_sparkline_visual () =
  let sp = Sparkline_widget.create ~width:20 ~max_points:20 () in
  (* Push known data pattern *)
  let pattern = [10.; 20.; 30.; 40.; 50.; 60.; 70.; 80.; 70.; 60.; 50.; 40.; 30.; 20.; 10.] in
  List.iter (Sparkline_widget.push sp) pattern;

  let output = Sparkline_widget.render sp ~focus:false ~show_value:false in

  (* Compare with golden/expected output *)
  check string "visual sparkline" "▁▂▃▄▅▆▇█▇▆▅▄▃▂▁" output
```

---

## Documentation

### Each widget `.mli` should include:

1. **Module docstring** with purpose
2. **Type documentation** for all exposed types
3. **Function documentation** with `@param` and `@return`
4. **Usage example** in comment block:
   ```ocaml
   (** {1 Usage Example}

       {[
         let spark = Sparkline_widget.create ~width:30 ~max_points:30 () in
         for i = 1 to 30 do
           Sparkline_widget.push spark (Random.float 100.)
         done;
         print_endline (Sparkline_widget.render spark ~focus:true ~show_value:true)
       ]}

       Output: [▁▃▄▆▇█▇▅▃▂▁▂▃▅▆▇█▇▆▄▃▂▁] 42.3%
   *)
   ```
5. **Key bindings** if applicable (none for these widgets)

---

## Performance Considerations

### Sparkline:
- **Memory**: O(max_points) - circular buffer
- **Render time**: O(width) - single pass over data
- **Target**: <1ms for typical size (width=30)

### Line Chart:
- **Memory**: O(series_count × points_per_series) + O(width × height) for grid
- **Render time**: O(series × points) for plotting + O(width × height) for grid conversion
- **Target**: <5ms for typical chart (60×15, 3 series, 50 points each)

### Optimization notes:
- Use `Buffer.t` for string building, not `String.concat`
- Pre-allocate grid array
- Cache min/max values (don't recalculate on every render)
- Consider lazy re-rendering (only if data changed)

---

## Migration Path

### Phase 1 (Days 1-5): Sparklines
1. Implement `sparkline_widget.ml`
2. Add tests
3. Add to demo
4. Document in `.mli`

### Phase 2 (Days 6-7): Line Charts
1. Implement `chart_utils.ml` (shared helpers)
2. Implement `line_chart_widget.ml`
3. Add tests
4. Add to demo
5. Document in `.mli`

### Phase 3 (Days 8-10): Polish
1. Add bar charts (if time permits)
2. Add braille sparklines (if time permits)
3. Performance profiling and optimization
4. Complete documentation
5. Update main README with chart examples

---

## Success Criteria

### Functional:
- [ ] Sparkline widget renders correctly with test data
- [ ] Line chart widget draws axes and plots accurately
- [ ] Bar chart widget (optional) displays comparisons
- [ ] All widgets have complete `.mli` files with examples
- [ ] Demo page shows all chart types with live updates
- [ ] Tests achieve 85%+ coverage of chart code

### Performance:
- [ ] Sparkline renders in <1ms
- [ ] Line chart renders in <5ms
- [ ] No noticeable lag in demo with real-time updates (10 FPS)

### Documentation:
- [ ] Each widget has usage example in `.mli`
- [ ] Main README updated with chart examples
- [ ] Demo shows off capabilities

### Integration:
- [ ] Can be used in octez-manager for real monitoring
- [ ] Works in headless driver for testing
- [ ] Compatible with existing widget patterns (render, handle_key)

---

## Open Questions

1. **Color scheme**: Use palette module colors or hardcode chart-specific colors?
   - **Recommendation**: Use `Palette` for consistency, add chart-specific helpers if needed

2. **Unicode support**: Assume UTF-8 terminal or provide ASCII fallback?
   - **Recommendation**: Use `W.prefer_ascii` pattern from existing widgets

3. **Real-time updates**: Should charts handle animation/interpolation or just discrete updates?
   - **Recommendation**: Start with discrete, add smoothing later if needed

4. **Data source**: Should widgets poll data or receive push updates?
   - **Recommendation**: Push model (caller updates via `push`/`add_point`), widgets are passive

5. **Scrolling**: Should line charts support panning/zooming?
   - **Recommendation**: Not in v1, keep simple. Add in v2 if needed.

---

## References

### Mosaic Implementation:
- `mosaic/lib/mosaic_charts/sparkline.ml` - Reference implementation
- `mosaic/examples/x-dashboard/main.ml` - Usage examples

### Terminal Graphics Resources:
- Unicode block characters: U+2580 - U+259F
- Unicode braille patterns: U+2800 - U+28FF
- Box drawing characters: U+2500 - U+257F

### Similar Projects (for inspiration):
- **asciichart** (JavaScript): Simple ASCII line charts
- **termgraph** (Python): Terminal bar/line/pie charts
- **spark** (shell): Original sparklines implementation
- **tui-rs charts** (Rust): Full TUI charting library

---

## Estimated LOC

- `sparkline_widget.ml`: ~200 LOC
- `line_chart_widget.ml`: ~400 LOC
- `bar_chart_widget.ml`: ~200 LOC
- `braille_sparkline_widget.ml`: ~150 LOC
- `chart_utils.ml`: ~100 LOC
- Tests: ~500 LOC
- **Total**: ~1,550 LOC

**Compared to Mosaic charts**: ~14,000 LOC (they have full canvas + many chart types)

**Trade-off**: We build focused widgets (1.5k LOC) vs general framework (14k LOC). Good enough for monitoring use case.
