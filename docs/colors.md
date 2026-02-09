# Color Guide

Miaou chart widgets that expose a `color : string option` field expect ANSI SGR
foreground payloads as strings.

Use values that can appear inside `\027[<payload>m`.

- Basic ANSI colors: `"30"` .. `"37"`
- Bright ANSI colors: `"90"` .. `"97"`
- 256-color foreground: `"38;5;<n>"` where `<n>` is `0..255`

Do not pass raw palette indices like `"196"`; use `"38;5;196"`.

## Line Chart precedence

- Point `color` overrides series `color`
- Series `color` overrides thresholds
- Thresholds apply only when both point and series colors are absent

## Sparkline precedence

- Matching threshold color is used first
- Then the render `~color` argument
- Then widget fallback color

## Advanced example: diagnostics panel

```ocaml
module LC = Miaou_widgets_display.Line_chart_widget
module SP = Miaou_widgets_display.Sparkline_widget

let mk_latency_chart ~samples =
  let points =
    List.mapi
      (fun i y ->
        let point_color = if y > 120.0 then Some "38;5;196" else None in
        {LC.x = float_of_int i; y; color = point_color})
      samples
  in
  let series =
    {
      LC.label = "Render latency";
      points;
      color = Some "38;5;81";
    }
  in
  LC.create ~width:64 ~height:14 ~series:[series] ~title:"Latency (ms)" ()

let render_cpu_spark spark =
  SP.render
    spark
    ~focus:true
    ~show_value:true
    ~color:"38;5;45"
    ~thresholds:
      [
        {SP.value = 50.0; color = "38;5;226"};
        {SP.value = 80.0; color = "38;5;196"};
      ]
    ()
```
