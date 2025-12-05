[@@@warning "-32-34-37-69"]
[@@@coverage off]

open Tui_page

let available = false

let run (_page : (module PAGE_SIG)) : [`Quit | `SwitchTo of string] =
  failwith "HTML driver not built in this configuration"
