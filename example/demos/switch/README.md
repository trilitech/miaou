# Switch widget

This switch shares the same input contract as checkbox/radio: it reacts to `"Enter"` and `"Space"` (driver-normalized).

```ocaml
let handle_key s key_str ~size:_ =
  match Miaou.Core.Keys.of_string key_str with
  | Some (Miaou.Core.Keys.Char " ") | Some Miaou.Core.Keys.Enter ->
      {s with switch = Switch.handle_key s.switch ~key:"Enter"}
  | _ -> s
```

- `Switch.render` already embeds focus styling, so demos simply pass `~focus:true`.
- When wiring your own pages, keep the key parsing in the page and call `Switch.handle_key` with canonical `"Enter"`/`"Space"` strings.
