# Line Chart Widgets

Line charts display data series on a coordinate plane with axes and optional grid.

## Usage Pattern

```ocaml
let points = List.init 20 (fun i ->
  let x = float_of_int i in
  { Line_chart.x; y = sin(x /. 3.0) *. 50.0 +. 50.0; color = None }
) in
let chart = Line_chart.create ~width:60 ~height:15 
  ~series:[{ label = "Sine Wave"; points; color = None }]
  ~title:"Sine Function" () in
Line_chart.render chart ~show_axes:true ~show_grid:true ()
```

## Key Features

- **Multi-series**: Plot multiple data series with different symbols
- **Axes**: Optional X/Y axes with tick marks
- **Grid**: Optional grid lines for easier reading
- **Colors**: Optional ANSI color codes per series
- **Dynamic updates**: Use `update_series` or `add_point`

## Keys

- Space - Add more points
- b - Toggle Braille rendering mode
- t - Show tutorial
- Esc - Return to launcher

## When to Use

- Historical trends over time
- Comparing multiple metrics
- Visualizing functions or formulas
- Performance graphs (response times, throughput)
