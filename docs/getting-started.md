# Getting Started with MIAOU

This guide walks you through building your first MIAOU terminal application.

## Prerequisites

- OCaml 5.1 or later (5.3.x recommended)
- opam 2.x
- dune >= 3.15

## Installation

### Terminal-only (no SDL dependency)

```bash
opam install miaou-tui
```

### Full installation (with SDL support)

```bash
# Install system dependencies first
# Ubuntu/Debian:
sudo apt install libsdl2-dev libsdl2-ttf-dev libsdl2-image-dev

# macOS:
brew install sdl2 sdl2_ttf sdl2_image

# Then install MIAOU
opam install miaou
```

## Project Setup

Create a new project:

```bash
mkdir my-tui-app
cd my-tui-app
```

### dune-project

```lisp
(lang dune 3.15)
(name my_tui_app)

(package
 (name my_tui_app)
 (depends
  (ocaml (>= 5.1))
  (miaou-tui (>= 0.1))))
```

### dune

```lisp
(executable
 (name main)
 (libraries miaou-tui miaou-core.helpers logs.fmt))

(rule
 (deps README.md)
 (targets readme_blob.ml)
 (action
  (with-stdout-to %{targets}
   (progn
    (echo "let content = {blob|")
    (cat README.md)
    (echo "|blob}")))))
```

## Your First Page

### page.ml

```ocaml
(* A simple counter page *)

module W = Miaou_widgets_display.Widgets
module Button = Miaou_widgets_input.Button_widget

type state = {
  count : int;
  button : Button.t;
  next_page : string option;
}

type msg = Increment | Decrement

let init () =
  let button = Button.create ~label:"Increment" ~on_click:(fun () -> ()) () in
  { count = 0; button; next_page = None }

let update s = function
  | Increment -> { s with count = s.count + 1 }
  | Decrement -> { s with count = max 0 (s.count - 1) }

let view s ~focus:_ ~size:_ =
  let title = W.titleize "My Counter App" in
  let counter = Printf.sprintf "Count: %s" (W.bold (string_of_int s.count)) in
  let button_view = Button.render s.button ~focus:true in
  let help = W.dim "Press Enter to increment, Backspace to decrement, q to quit" in
  String.concat "\n\n" [title; counter; button_view; help]

let handle_key s key_str ~size:_ =
  match Miaou.Core.Keys.of_string key_str with
  | Some Miaou.Core.Keys.Enter ->
      let button, _ = Button.handle_key s.button ~key:key_str in
      update { s with button } Increment
  | Some Miaou.Core.Keys.Backspace ->
      update s Decrement
  | Some (Miaou.Core.Keys.Char "q") ->
      { s with next_page = Some "__QUIT__" }
  | _ -> s

(* Required PAGE_SIG functions *)
let move s _ = s
let refresh s = s
let enter s = update s Increment
let service_select s _ = s
let service_cycle s _ = s
let handle_modal_key s _ ~size:_ = s
let next_page s = s.next_page
let keymap _ = []
let handled_keys () = []
let back s = { s with next_page = Some "__QUIT__" }
let has_modal _ = false
```

### main.ml

```ocaml
let () =
  (* Set up logging *)
  Fmt_tty.setup_std_outputs ();
  Logs.set_reporter (Logs_fmt.reporter ());
  Logs.set_level (Some Logs.Info);

  (* Run with Eio *)
  Eio_main.run @@ fun env ->
  Eio.Switch.run @@ fun sw ->

  (* Initialize MIAOU runtime *)
  Miaou_helpers.Fiber_runtime.init ~env ~sw;

  (* Run the application *)
  let page : Miaou.Core.Registry.page = (module Page : Miaou.Core.Tui_page.PAGE_SIG) in
  ignore (Miaou_runner_tui.Runner_tui.run page)
```

### Build and Run

```bash
dune build
dune exec ./main.exe
```

## Adding Widgets

Let's enhance our app with more widgets:

### page.ml (enhanced)

```ocaml
module W = Miaou_widgets_display.Widgets
module Button = Miaou_widgets_input.Button_widget
module Checkbox = Miaou_widgets_input.Checkbox_widget
module Progress = Miaou_widgets_layout.Progress_widget

type state = {
  count : int;
  button : Button.t;
  checkbox : Checkbox.t;
  auto_increment : bool;
  next_page : string option;
}

type msg = Increment | Decrement | ToggleAuto

let init () = {
  count = 0;
  button = Button.create ~label:"Increment" ~on_click:(fun () -> ()) ();
  checkbox = Checkbox.create ~label:"Auto-increment" ~checked:false ();
  auto_increment = false;
  next_page = None;
}

let update s = function
  | Increment -> { s with count = s.count + 1 }
  | Decrement -> { s with count = max 0 (s.count - 1) }
  | ToggleAuto -> { s with auto_increment = not s.auto_increment }

let view s ~focus:_ ~size =
  let title = W.titleize "Enhanced Counter" in

  (* Progress bar showing count (0-100) *)
  let progress_pct = float_of_int (min 100 s.count) /. 100.0 in
  let progress_bar = Progress.render
    ~width:(min 40 (size.LTerm_geom.cols - 10))
    ~progress:progress_pct
    ~style:`Blocks
    ()
  in

  let counter = Printf.sprintf "Count: %s / 100"
    (W.bold (string_of_int s.count))
  in

  let button_view = Button.render s.button ~focus:true in
  let checkbox_view = Checkbox.render s.checkbox ~focus:false in

  let status = if s.auto_increment
    then W.green "Auto-increment: ON"
    else W.dim "Auto-increment: OFF"
  in

  let help = W.dim "Enter: +1 | Backspace: -1 | Space: toggle auto | q: quit" in

  String.concat "\n\n" [
    title;
    progress_bar;
    counter;
    button_view;
    checkbox_view;
    status;
    help;
  ]

let handle_key s key_str ~size:_ =
  match Miaou.Core.Keys.of_string key_str with
  | Some Miaou.Core.Keys.Enter ->
      let button, _ = Button.handle_key s.button ~key:key_str in
      update { s with button } Increment
  | Some Miaou.Core.Keys.Backspace ->
      update s Decrement
  | Some (Miaou.Core.Keys.Char " ") ->
      let checkbox, toggled = Checkbox.handle_key s.checkbox ~key:key_str in
      let s = { s with checkbox } in
      if toggled then update s ToggleAuto else s
  | Some (Miaou.Core.Keys.Char "q") ->
      { s with next_page = Some "__QUIT__" }
  | _ -> s

(* ... rest unchanged ... *)
```

## Using Modals

Add a confirmation dialog:

```ocaml
(* In page.ml, add a reset confirmation *)

let show_reset_confirm s =
  (* Create a simple confirmation modal *)
  Miaou.Core.Modal_manager.confirm
    (module struct
      type state = unit
      type msg = unit
      let init () = ()
      let update s _ = s
      let view _ ~focus:_ ~size:_ =
        "Are you sure you want to reset the counter?\n\n" ^
        W.dim "Enter: Yes | Esc: No"
      let move s _ = s
      let refresh s = s
      let enter s = s
      let service_select s _ = s
      let service_cycle s _ = s
      let handle_modal_key s _ ~size:_ = s
      let handle_key s _ ~size:_ = s
      let next_page _ = None
      let keymap _ = []
      let handled_keys () = []
      let back s = s
      let has_modal _ = false
    end)
    ~init:()
    ~title:"Confirm Reset"
    ~on_result:(fun confirmed ->
      if confirmed then
        Logs.info (fun m -> m "Counter reset!")
      (* Note: In real code you'd update state via a ref or callback *)
    )
    ()
```

## Using Capabilities

Register a system capability for file operations:

### main.ml (with capabilities)

```ocaml
let register_system_capability () =
  Miaou_interfaces.System.set {
    file_exists = Sys.file_exists;
    is_directory = Sys.is_directory;
    read_file = (fun path ->
      try
        let ic = open_in path in
        let len = in_channel_length ic in
        let content = really_input_string ic len in
        close_in ic;
        Ok content
      with e -> Error (Printexc.to_string e)
    );
    write_file = (fun path content ->
      try
        let oc = open_out path in
        output_string oc content;
        close_out oc;
        Ok ()
      with e -> Error (Printexc.to_string e)
    );
    mkdir = (fun path ->
      try Unix.mkdir path 0o755; Ok ()
      with e -> Error (Printexc.to_string e)
    );
    run_command = (fun ~argv ~cwd:_ ->
      (* Simplified - real impl would use Unix.create_process *)
      Ok { exit_code = 0; stdout = ""; stderr = "" }
    );
    get_current_user_info = (fun () ->
      Ok (Unix.getlogin (), Sys.getenv "HOME")
    );
    get_disk_usage = (fun ~path ->
      try
        let st = Unix.stat path in
        Ok (Int64.of_int st.Unix.st_size)
      with e -> Error (Printexc.to_string e)
    );
    list_dir = (fun path ->
      try Ok (Array.to_list (Sys.readdir path))
      with e -> Error (Printexc.to_string e)
    );
    probe_writable = (fun ~path ->
      try
        let tmp = Filename.concat path ".probe" in
        let oc = open_out tmp in
        close_out oc;
        Sys.remove tmp;
        Ok true
      with _ -> Ok false
    );
    get_env_var = Sys.getenv_opt;
  }

let () =
  Fmt_tty.setup_std_outputs ();
  Logs.set_reporter (Logs_fmt.reporter ());

  Eio_main.run @@ fun env ->
  Eio.Switch.run @@ fun sw ->
  Miaou_helpers.Fiber_runtime.init ~env ~sw;

  (* Register capabilities before running *)
  register_system_capability ();

  let page = (module Page : Miaou.Core.Tui_page.PAGE_SIG) in
  ignore (Miaou_runner_tui.Runner_tui.run page)
```

## Multi-Page Navigation

Create multiple pages and navigate between them:

### home_page.ml

```ocaml
type state = { next_page : string option }
type msg = unit

let init () = { next_page = None }
let update s _ = s

let view _ ~focus:_ ~size:_ =
  let module W = Miaou_widgets_display.Widgets in
  String.concat "\n" [
    W.titleize "Home";
    "";
    "1. Go to Settings";
    "2. Go to About";
    "";
    W.dim "Press 1, 2, or q to quit"
  ]

let handle_key s key_str ~size:_ =
  match Miaou.Core.Keys.of_string key_str with
  | Some (Miaou.Core.Keys.Char "1") -> { next_page = Some "settings" }
  | Some (Miaou.Core.Keys.Char "2") -> { next_page = Some "about" }
  | Some (Miaou.Core.Keys.Char "q") -> { next_page = Some "__QUIT__" }
  | _ -> s

(* ... other PAGE_SIG functions ... *)
```

### main.ml (multi-page)

```ocaml
let () =
  (* ... setup ... *)

  (* Register all pages *)
  Miaou.Core.Registry.register "home" (module Home_page : Miaou.Core.Tui_page.PAGE_SIG);
  Miaou.Core.Registry.register "settings" (module Settings_page : Miaou.Core.Tui_page.PAGE_SIG);
  Miaou.Core.Registry.register "about" (module About_page : Miaou.Core.Tui_page.PAGE_SIG);

  (* Start with home page *)
  let page = (module Home_page : Miaou.Core.Tui_page.PAGE_SIG) in
  ignore (Miaou_runner_tui.Runner_tui.run page)
```

## Using Flex Layout

Create responsive layouts:

```ocaml
let view s ~focus:_ ~size =
  let module Flex = Miaou_widgets_layout.Flex_layout in
  let module W = Miaou_widgets_display.Widgets in

  (* Two-column layout *)
  let left_panel = String.concat "\n" [
    W.bold "Navigation";
    "─────────────";
    "• Home";
    "• Settings";
    "• About";
  ] in

  let right_panel = String.concat "\n" [
    W.bold "Content";
    "─────────────";
    Printf.sprintf "Count: %d" s.count;
    "";
    "More content here...";
  ] in

  let layout = Flex.create
    ~direction:Row
    ~gap:2
    ~children:[
      { basis = Px 20; content = left_panel };
      { basis = Fill; content = right_panel };
    ]
    ()
  in

  Flex.render layout
    ~width:size.LTerm_geom.cols
    ~height:(size.LTerm_geom.rows - 2)
```

## Next Steps

- Browse the [Examples](../example/README.md) for more widget demos
- Read the [Architecture Guide](architecture.md) for deeper understanding
- Learn about [Capabilities](capabilities.md) for dependency injection
- Check [CONTRIBUTING.md](../CONTRIBUTING.md) to contribute

## Quick Reference

### Key Handling

```ocaml
match Miaou.Core.Keys.of_string key_str with
| Some Keys.Enter -> (* enter pressed *)
| Some Keys.Up -> (* up arrow *)
| Some Keys.Down -> (* down arrow *)
| Some (Keys.Char "q") -> (* 'q' key *)
| Some (Keys.Ctrl 'c') -> (* Ctrl+C *)
| _ -> s (* return state unchanged *)
```

### Styling

```ocaml
let module W = Miaou_widgets_display.Widgets in
W.bold "Important"
W.dim "Secondary"
W.green "Success"
W.red "Error"
W.yellow "Warning"
W.titleize "Header"
```

### Page Navigation

```ocaml
(* Navigate to another page *)
{ s with next_page = Some "target_page" }

(* Quit the application *)
{ s with next_page = Some "__QUIT__" }
```

### Modal Dialogs

```ocaml
(* Simple alert *)
Modal_manager.alert (module Alert_page) ~init:() ~title:"Info" ()

(* Confirmation *)
Modal_manager.confirm (module Confirm_page) ~init:()
  ~title:"Confirm"
  ~on_result:(fun yes -> if yes then (* confirmed *))
  ()

(* Input prompt *)
Modal_manager.prompt (module Input_page) ~init:()
  ~title:"Enter name"
  ~extract:(fun st -> Some st.text)
  ~on_result:(fun opt -> match opt with Some v -> (* use v *) | None -> ())
  ()
```
