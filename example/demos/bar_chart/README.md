# Bar Chart Widgets

Bar charts display values as vertical bars, perfect for comparing categories or showing rankings.

## Usage Pattern

```ocaml
let data = [
  ("Product A", 1250.0, None);
  ("Product B", 2100.0, Some "32");  (* green ANSI code *)
  ("Product C", 1800.0, None);
  ("Product D", 900.0, None);
] in
let chart = Bar_chart.create ~width:60 ~height:15 
  ~data ~title:"Sales by Product" () in
Bar_chart.render chart ~show_values:true
```

## Key Features

- **Category comparison**: Compare discrete values across categories
- **Value labels**: Optionally display values on top of bars
- **Fixed or auto scaling**: Set min/max or let it auto-scale
- **Color support**: Optional ANSI colors for visual emphasis
- **Dynamic updates**: Use `update_data` to refresh

## Keys

- Space - Randomize data
- t - Show tutorial
- Esc - Return to launcher

## When to Use

- Comparing sales, revenue, or metrics by category
- Rankings (top performers, popular items)
- Resource usage by service/component
- Survey results or voting data
