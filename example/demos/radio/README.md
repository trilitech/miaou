# Radio Button Widget

Radio buttons allow selecting exactly one option from a group.

## Usage

```ocaml
let options = [
  Radio.create ~label:"Option A" ~selected:true ();
  Radio.create ~label:"Option B" ();
  Radio.create ~label:"Option C" ();
]
```

## Key Features

- Single selection: selecting one automatically deselects others
- Focus chain support for keyboard navigation
- Number shortcuts (1/2/3) for quick selection
- Tab key cycles through options
