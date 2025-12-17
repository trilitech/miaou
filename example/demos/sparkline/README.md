# Sparkline Widgets

Sparklines display compact time-series data using Unicode block characters.

## Usage Pattern

```ocaml
let cpu = Sparkline_widget.create ~width:40 ~max_points:40 
  ~min_value:0.0 ~max_value:100.0 () in
Sparkline_widget.push cpu (get_cpu_usage ());
Sparkline_widget.render_with_label cpu ~label:"CPU" ~focus:true
```

## Key Features

- **Circular buffer**: Automatically drops oldest values when `max_points` exceeded
- **Scaling modes**:
  - Auto-scaling (default): Fits to data min/max - good for varying ranges
  - Fixed scaling: Set `~min_value`/`~max_value` - required for percentages (0-100)
- **Label support**: Use `render_with_label` to show metric name and current value

## Integration Tips

- Implement `service_cycle` to auto-update sparklines every ~150ms
- Combine multiple sparklines vertically for dashboard layouts
- Use `stats` function to get (min, max, current) for custom displays
- Call `clear` to reset data when switching contexts

## Auto-Refresh Pattern

```ocaml
let service_cycle s _ = 
  (* Called automatically by driver every ~150ms when idle *)
  let cpu = System_metrics.get_cpu_usage () in
  Sparkline.push s.cpu_spark cpu;
  {s with tick_count = s.tick_count + 1}
```

This demo reads real system metrics from `/proc` (Linux) and auto-updates the display.
