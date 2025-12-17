# Tabs Widget Demo

Tab-based navigation for switching between views.

## Keys

- ←/→ - Switch tabs
- Home/End - Jump to first/last tab
- Enter - Confirm selection
- Esc - Return to launcher

## Usage

```ocaml
let tabs = Tabs.make [
  Tabs.tab ~id:"dashboard" ~label:"Dashboard";
  Tabs.tab ~id:"logs" ~label:"Logs";
  Tabs.tab ~id:"settings" ~label:"Settings";
]
```
