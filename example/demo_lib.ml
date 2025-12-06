(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)
let register_all () =
  let () = Miaou_example.Mock_system.register () in
  let () = Miaou_example.Mock_service_lifecycle.register () in
  let () = Miaou_example.Mock_logger.register () in
  let () = Miaou_example.Mock_palette.register () in
  Printf.printf "miaou example: registered mocks\n"

let ensure_system_capability () =
  match Miaou_interfaces.System.get () with
  | Some _ -> ()
  | None -> failwith "capability missing: System (demo)"

(* Miaou demo launcher - using Miaou.Core.Tui_driver *)

let launcher_page_name = "miaou.demo.launcher"

module type SELECT_MODAL_SIG = sig
  include Miaou.Core.Tui_page.PAGE_SIG

  val extract_selection : state -> string option
end

module Textbox_modal : Miaou.Core.Tui_page.PAGE_SIG = struct
  type state = Miaou_widgets_input.Textbox_widget.t

  type msg = unit

  let init () =
    Miaou_widgets_input.Textbox_widget.open_centered
      ~width:40
      ~initial:"Initial text"
      ~placeholder:(Some "Type here...")
      ()

  let update s _ = s

  let view s ~focus:_ ~size:_ =
    Miaou_widgets_input.Textbox_widget.render s ~focus:true

  let handle_key s key_str ~size:_ =
    Miaou_widgets_input.Textbox_widget.handle_key s ~key:key_str

  let move s _ = s

  let refresh s = s

  let enter s = s

  let service_select s _ = s

  let service_cycle s _ = s

  let handle_modal_key s _ ~size:_ = s

  let next_page _ = None

  (* legacy key_bindings removed *)

  let keymap (_ : state) = []

  let back s = s

  let has_modal _ = false
end

module Select_modal : SELECT_MODAL_SIG = struct
  type state = string Miaou_widgets_input.Select_widget.t

  type msg = unit

  let init () =
    Miaou_widgets_input.Select_widget.open_centered
      ~cursor:0
      ~title:"Select an option"
      ~items:["Option A"; "Option B"; "Option C"; "Option D"]
      ~to_string:(fun x -> x)
      ()

  let update s _ = s

  let view s ~focus ~size:_ = Miaou_widgets_input.Select_widget.render s ~focus

  let handle_key s key_str ~size:_ =
    Miaou_widgets_input.Select_widget.handle_key s ~key:key_str

  let move s _ = s

  let refresh s = s

  let enter s = s

  let service_select s _ = s

  let service_cycle s _ = s

  let handle_modal_key s _ ~size:_ = s

  let next_page _ = None

  (* legacy key_bindings removed *)

  let keymap (_ : state) = []

  let extract_selection s = Miaou_widgets_input.Select_widget.get_selection s

  let back s = s

  let has_modal _ = false
end

module File_browser_modal : Miaou.Core.Tui_page.PAGE_SIG = struct
  type state = Miaou_widgets_layout.File_browser_widget.t

  type msg = unit

  let init () =
    Miaou_widgets_layout.File_browser_widget.open_centered
      ~path:"./"
      ~dirs_only:false
      ()

  let update s _ = s

  let view s ~focus ~size:_ =
    Miaou_widgets_layout.File_browser_widget.render s ~focus

  let handle_key s key_str ~size:_ =
    Miaou_widgets_layout.File_browser_widget.handle_key s ~key:key_str

  let move s _ = s

  let refresh s = s

  let enter s = s

  let service_select s _ = s

  let service_cycle s _ = s

  let handle_modal_key s _ ~size:_ = s

  let next_page _ = None

  (* legacy key_bindings removed *)

  let keymap (_ : state) = []

  let back s = s

  let has_modal _ = false
end

module Poly_select_modal : SELECT_MODAL_SIG = struct
  type item = {label : string; id : int}

  type state = item Miaou_widgets_input.Select_widget.t

  type msg = unit

  let init () =
    let items =
      [
        {label = "Alpha"; id = 1};
        {label = "Beta"; id = 2};
        {label = "Gamma"; id = 3};
      ]
    in
    Miaou_widgets_input.Select_widget.open_centered
      ~cursor:0
      ~title:"Select a record (poly)"
      ~items
      ~to_string:(fun i -> Printf.sprintf "%s (id=%d)" i.label i.id)
      ()

  let update s _ = s

  let view s ~focus ~size:_ = Miaou_widgets_input.Select_widget.render s ~focus

  let handle_key s key_str ~size:_ =
    Miaou_widgets_input.Select_widget.handle_key s ~key:key_str

  let move s _ = s

  let refresh s = s

  let enter s = s

  let service_select s _ = s

  let service_cycle s _ = s

  let back s = s

  let has_modal _ = false

  let handle_modal_key s _ ~size:_ = s

  let next_page _ = None

  (* legacy key_bindings removed *)

  let keymap (_ : state) = []

  (* Extract the current label (string). Return [Some label]. *)
  let extract_selection (s : state) : string option =
    match Miaou_widgets_input.Select_widget.get_selection s with
    | None -> None
    | Some it -> Some (Printf.sprintf "%s (id=%d)" it.label it.id)
end

module Table_demo_page : Miaou.Core.Tui_page.PAGE_SIG = struct
  type row = string * string * string

  type state = {
    table : row Miaou_widgets_display.Table_widget.Table.t;
    next_page : string option;
  }

  type msg = Move of int | Enter

  let init () =
    let rows : row list =
      [
        ("Alice", "42", "Active");
        ("Bob", "7", "Inactive");
        ("Charlie", "99", "Active");
      ]
    in
    let columns =
      [
        {
          Miaou_widgets_display.Table_widget.Table.header = "Name";
          to_string = (fun (n, _, _) -> n);
        };
        {header = "Score"; to_string = (fun (_, s, _) -> s)};
        {header = "Status"; to_string = (fun (_, _, st) -> st)};
      ]
    in
    {
      table = Miaou_widgets_display.Table_widget.Table.create ~columns ~rows ();
      next_page = None;
    }

  let set_table s table = {s with table}

  let update s = function
    | Move d ->
        let table =
          Miaou_widgets_display.Table_widget.Table.move_cursor s.table d
        in
        set_table s table
    | Enter -> s

  let enter s = s

  let view s ~focus:_ ~size:_ =
    let header =
      Miaou_widgets_display.Widgets.dim
        "↑/↓ to move • Enter logs the selection • Esc returns"
    in
    let body =
      Miaou_widgets_display.Table_widget.render_table_80
        ~cols:(Some 80)
        ~header:("Name", "Score", "Status")
        ~rows:s.table.rows
        ~cursor:s.table.cursor
        ~sel_col:0
    in
    header ^ "\n\n" ^ body

  let log_selection table =
    match Miaou_widgets_display.Table_widget.Table.get_selected table with
    | None -> Logs.info (fun m -> m "No selection")
    | Some (n, sc, st) ->
        Logs.info (fun m -> m "Selected: %s (%s) - %s" n sc st)

  let handle_key s key_str ~size:_ =
    match Miaou.Core.Keys.of_string key_str with
    | Some Miaou.Core.Keys.Up -> update s (Move (-1))
    | Some Miaou.Core.Keys.Down -> update s (Move 1)
    | Some Miaou.Core.Keys.Enter ->
        log_selection s.table ;
        update s Enter
    | Some (Miaou.Core.Keys.Char "q")
    | Some (Miaou.Core.Keys.Char "Q")
    | Some Miaou.Core.Keys.Backspace
    | Some (Miaou.Core.Keys.Char "Esc")
    | Some (Miaou.Core.Keys.Char "Escape") ->
        {s with next_page = Some launcher_page_name}
    | _ -> s

  let move s d = update s (Move d)

  let refresh s = s

  let service_select s _ = s

  let service_cycle s _ = s

  let handle_modal_key s _ ~size:_ = s

  let next_page s = s.next_page

  (* legacy key_bindings removed *)

  let keymap (_ : state) = []

  let back s = {s with next_page = Some launcher_page_name}

  let has_modal _ = false
end

module Poly_table_demo_page : Miaou.Core.Tui_page.PAGE_SIG = struct
  type row = {name : string; score : int; active : bool}

  type state = row Miaou_widgets_display.Table_widget.Table.t

  type msg = Move of int

  let init () =
    let rows =
      [
        {name = "Alice"; score = 42; active = true};
        {name = "Bob"; score = 7; active = false};
      ]
    in
    let columns =
      [
        {
          Miaou_widgets_display.Table_widget.Table.header = "Name";
          to_string = (fun r -> r.name);
        };
        {header = "Score"; to_string = (fun r -> string_of_int r.score)};
        {
          header = "Active";
          to_string = (fun r -> if r.active then "✓" else "✗");
        };
      ]
    in
    Miaou_widgets_display.Table_widget.Table.create ~columns ~rows ()

  let update t = function
    | Move d -> Miaou_widgets_display.Table_widget.Table.move_cursor t d

  let enter t = t

  let view t ~focus:_ ~size:_ =
    Miaou_widgets_display.Table_widget.Table.render t

  let handle_key t key_str ~size:_ =
    match Miaou.Core.Keys.of_string key_str with
    | Some Miaou.Core.Keys.Up -> update t (Move (-1))
    | Some Miaou.Core.Keys.Down -> update t (Move 1)
    | _ -> t

  let move t d = update t (Move d)

  let refresh t = t

  let service_select t _ = t

  let service_cycle t _ = t

  let handle_modal_key t _ ~size:_ = t

  let next_page _ = None

  (* legacy key_bindings removed *)

  let keymap (_ : state) = []

  let back t = t

  let has_modal _ = false
end

module Palette_demo_page : Miaou.Core.Tui_page.PAGE_SIG = struct
  type state = {next_page : string option}

  type msg = unit

  let init () = {next_page = None}

  let update s _ = s

  let _enter s = s

  let view _s ~focus:_ ~size:_ =
    let module P = Miaou_widgets_display.Palette in
    let samples =
      [
        ("Primary", P.fg_primary);
        ("Secondary", P.fg_secondary);
        ("Muted", P.fg_muted);
        ("Stealth", P.fg_stealth);
        ("Slate", P.fg_slate);
        ("Steel", P.fg_steel);
        ("Success", P.fg_success);
        ("Error", P.fg_error);
      ]
    in
    let header =
      Miaou_widgets_display.Widgets.titleize "Palette demo (Esc returns)"
    in
    let body =
      List.map
        (fun (name, color_fn) ->
          Printf.sprintf
            "%s %s"
            (color_fn (Printf.sprintf "%10s" name))
            (color_fn "██████████"))
        samples
    in
    String.concat "\n" (header :: "" :: body)

  let go_home = {next_page = Some launcher_page_name}

  let handle_key s key_str ~size:_ =
    match Miaou.Core.Keys.of_string key_str with
    | Some (Miaou.Core.Keys.Char "Esc")
    | Some (Miaou.Core.Keys.Char "Escape")
    | Some (Miaou.Core.Keys.Char "q") ->
        go_home
    | _ -> s

  let move s _ = s

  let refresh s = s

  let enter s = s

  let service_select s _ = s

  let service_cycle s _ = s

  let handle_modal_key s _ ~size:_ = s

  let next_page s = s.next_page

  (* legacy key_bindings removed *)

  let keymap (_ : state) = []

  let back _ = go_home

  let has_modal _ = false
end

module Logger_demo_page : Miaou.Core.Tui_page.PAGE_SIG = struct
  type state = {lines : string list; next_page : string option}

  type msg = unit

  let base_lines =
    [
      "Logger demo";
      "i => info, w => warn, e => error, c => clear";
      "Esc returns to the launcher";
    ]

  let init () = {lines = base_lines; next_page = None}

  let update s _ = s

  let add_line line s =
    let rec take n lst =
      match (n, lst) with
      | 0, _ | _, [] -> []
      | _, x :: xs -> x :: take (n - 1) xs
    in
    let lines = take 12 (line :: s.lines) in
    {s with lines}

  let emit level text s =
    (match level with
    | `Info -> Logs.info (fun m -> m "%s" text)
    | `Warn -> Logs.warn (fun m -> m "%s" text)
    | `Error -> Logs.err (fun m -> m "%s" text)) ;
    add_line text s

  let view s ~focus:_ ~size:_ = s.lines |> List.rev |> String.concat "\n"

  let handle_key s key_str ~size:_ =
    match Miaou.Core.Keys.of_string key_str with
    | Some (Miaou.Core.Keys.Char "Esc") | Some (Miaou.Core.Keys.Char "Escape")
      ->
        {s with next_page = Some launcher_page_name}
    | Some (Miaou.Core.Keys.Char "i") -> emit `Info "[info] demo message" s
    | Some (Miaou.Core.Keys.Char "w") -> emit `Warn "[warn] demo message" s
    | Some (Miaou.Core.Keys.Char "e") -> emit `Error "[error] demo message" s
    | Some (Miaou.Core.Keys.Char "c") -> {s with lines = base_lines}
    | _ -> s

  let move s _ = s

  let refresh s = s

  let enter s = s

  let service_select s _ = s

  let service_cycle s _ = s

  let handle_modal_key s _ ~size:_ = s

  let next_page s = s.next_page

  (* legacy key_bindings removed *)

  let keymap (_ : state) = []

  let back s = {s with next_page = Some launcher_page_name}

  let has_modal _ = false
end

module Pager_demo_page : Miaou.Core.Tui_page.PAGE_SIG = struct
  module Pager = Miaou_widgets_display.Pager_widget

  type state = {
    pager : Pager.t;
    streaming : bool;
    ticks : int;
    next_page : string option;
  }

  type msg = unit

  let init () =
    let pager =
      Pager.open_lines
        ~title:"/var/log/miaou-demo.log"
        ["Booting demo environment"; "All systems nominal"]
    in
    {pager; streaming = false; ticks = 0; next_page = None}

  let update s _ = s

  let render_pager s ~focus ~size = Pager.render_with_size ~size s.pager ~focus

  let view s ~focus ~size =
    let header_lines =
      [
        "Pager widget demo";
        "a: append line • s: toggle streaming • f: follow mode • Esc: back";
        "";
      ]
    in
    String.concat "\n" header_lines ^ render_pager s ~focus ~size

  let append_line s msg =
    Pager.append_lines s.pager [msg] ;
    s

  let toggle_streaming s =
    if s.streaming then (
      Pager.stop_streaming s.pager ;
      {s with streaming = false})
    else (
      Pager.start_streaming s.pager ;
      {s with streaming = true})

  let win_from size = max 3 (size.LTerm_geom.rows - 4)

  let handle_key s key_str ~size =
    let win = win_from size in
    match Miaou.Core.Keys.of_string key_str with
    | Some (Miaou.Core.Keys.Char "Esc") | Some (Miaou.Core.Keys.Char "Escape")
      ->
        {s with next_page = Some launcher_page_name}
    | Some (Miaou.Core.Keys.Char "a") ->
        let line =
          Printf.sprintf "[%0.3f] new log entry" (Unix.gettimeofday ())
        in
        append_line s line
    | Some (Miaou.Core.Keys.Char "s") -> toggle_streaming s
    | Some (Miaou.Core.Keys.Char "f") ->
        let pager, _ = Pager.handle_key ~win s.pager ~key:"f" in
        {s with pager}
    | Some k ->
        let key = Miaou.Core.Keys.to_string k in
        let pager, _ = Pager.handle_key ~win s.pager ~key in
        {s with pager}
    | None -> s

  let move s _ = s

  let refresh s =
    let ticks = s.ticks + 1 in
    if s.streaming && ticks mod 5 = 0 then (
      Pager.append_lines_batched
        s.pager
        [Printf.sprintf "stream chunk #%d" (ticks / 5)] ;
      Pager.flush_pending_if_needed s.pager) ;
    {s with ticks}

  let enter s = s

  let service_select s _ = s

  let service_cycle s _ = s

  let handle_modal_key s _ ~size:_ = s

  let next_page s = s.next_page

  (* legacy key_bindings removed *)

  let keymap (_ : state) = []

  let back s = {s with next_page = Some launcher_page_name}

  let has_modal _ = false
end

module Tree_demo_page : Miaou.Core.Tui_page.PAGE_SIG = struct
  module Tree = Miaou_widgets_display.Tree_widget

  type state = {tree : Tree.t; next_page : string option}

  type msg = unit

  let sample_json =
    "{\"services\": {\"scheduler\": {\"status\": \"ready\"}, \"worker\": \
     {\"status\": \"syncing\"}}, \"counters\": [1,2,3]}"

  let init () =
    let node = Tree.of_json (Yojson.Safe.from_string sample_json) in
    {tree = Tree.open_root node; next_page = None}

  let update s _ = s

  let view s ~focus:_ ~size:_ =
    let lines =
      ["Tree widget demo (Esc returns)"; ""; Tree.render s.tree ~focus:false]
    in
    String.concat "\n" lines

  let handle_key s key_str ~size:_ =
    match Miaou.Core.Keys.of_string key_str with
    | Some (Miaou.Core.Keys.Char "Esc") | Some (Miaou.Core.Keys.Char "Escape")
      ->
        {s with next_page = Some launcher_page_name}
    | _ -> s

  let move s _ = s

  let refresh s = s

  let enter s = s

  let service_select s _ = s

  let service_cycle s _ = s

  let handle_modal_key s _ ~size:_ = s

  let next_page s = s.next_page

  (* legacy key_bindings removed *)

  let keymap (_ : state) = []

  let back s = {s with next_page = Some launcher_page_name}

  let has_modal _ = false
end

module Layout_demo_page : Miaou.Core.Tui_page.PAGE_SIG = struct
  type state = {next_page : string option}

  type msg = unit

  let init () = {next_page = None}

  let update s _ = s

  let view _ ~focus:_ ~size =
    let module Pane = Miaou_widgets_layout.Pane_layout in
    let module Vsection = Miaou_widgets_layout.Vsection in
    let cols = max 40 size.LTerm_geom.cols in
    let pane =
      Pane.create
        ~left:"Services\n- API: healthy\n- Worker: syncing\n- Scheduler: idle"
        ~right:"Latest logs\nINFO ready\nWARN sync lag\nINFO checkpoint"
        ~left_ratio:0.45
        ()
    in
    let split = Pane.render pane cols in
    let section =
      Vsection.render
        ~size:{size with LTerm_geom.rows = min 20 size.LTerm_geom.rows}
        ~header:["Vsection layout"; "Child area shown between rulers"]
        ~footer:["Footer area"; "Esc returns"]
        ~child:(fun inner ->
          Printf.sprintf "Inner area: %d x %d" inner.rows inner.cols)
    in
    String.concat "\n\n" ["Layout helpers (Esc returns)"; split; section]

  let go_home = {next_page = Some launcher_page_name}

  let handle_key s key_str ~size:_ =
    match Miaou.Core.Keys.of_string key_str with
    | Some (Miaou.Core.Keys.Char "Esc") | Some (Miaou.Core.Keys.Char "Escape")
      ->
        go_home
    | _ -> s

  let move s _ = s

  let refresh s = s

  let enter s = s

  let service_select s _ = s

  let service_cycle s _ = s

  let handle_modal_key s _ ~size:_ = s

  let next_page s = s.next_page

  (* legacy key_bindings removed *)

  let keymap (_ : state) = []

  let back _ = go_home

  let has_modal _ = false
end

module Breadcrumbs_demo_page : Miaou.Core.Tui_page.PAGE_SIG = struct
  module Breadcrumbs = Miaou_widgets_navigation.Breadcrumbs_widget

  type state = {trail : Breadcrumbs.t; info : string; next_page : string option}

  type msg = unit

  let init () =
    let trail =
      Breadcrumbs.make
        [
          Breadcrumbs.crumb ~id:"root" ~label:"Root" ();
          Breadcrumbs.crumb ~id:"cluster" ~label:"Cluster" ();
          Breadcrumbs.crumb
            ~id:"node"
            ~label:"Node-01"
            ~on_enter:(fun () -> ())
            ();
        ]
    in
    {
      trail;
      info = "Use ←/→/Home/End to move, Enter to activate, Esc to return";
      next_page = None;
    }

  let update s (_ : msg) = s

  let view s ~focus:_ ~size:_ =
    let module W = Miaou_widgets_display.Widgets in
    let header = W.titleize "Breadcrumbs" in
    let trail = Breadcrumbs.render s.trail ~focus:true in
    String.concat "\n\n" [header; trail; W.dim s.info]

  let go_home s = {s with next_page = Some launcher_page_name}

  let handle_key s key_str ~size:_ =
    match Miaou.Core.Keys.of_string key_str with
    | Some (Miaou.Core.Keys.Char "Esc") | Some (Miaou.Core.Keys.Char "Escape")
      ->
        go_home s
    | _ ->
        let trail, handled = Breadcrumbs.handle_key s.trail ~key:key_str in
        let info =
          match handled with
          | `Handled ->
              let current =
                Breadcrumbs.current trail |> Option.map Breadcrumbs.id
                |> Option.value ~default:"(none)"
              in
              "Selected " ^ current
          | `Ignored -> s.info
        in
        {s with trail; info}

  let move s delta =
    let dir = if delta < 0 then `Left else `Right in
    {s with trail = Breadcrumbs.move s.trail dir}

  let refresh s = s

  let enter s = s

  let service_select s _ = s

  let service_cycle s _ = s

  let handle_modal_key s _ ~size:_ = s

  let next_page s = s.next_page

  (* legacy key_bindings removed *)

  let keymap (_ : state) = []

  let back s = go_home s

  let has_modal _ = false
end

module Tabs_demo_page : Miaou.Core.Tui_page.PAGE_SIG = struct
  module Tabs = Miaou_widgets_navigation.Tabs_widget

  type state = {tabs : Tabs.t; note : string; next_page : string option}

  type msg = unit

  let init () =
    let tabs =
      Tabs.make
        [
          Tabs.tab ~id:"dashboard" ~label:"Dashboard";
          Tabs.tab ~id:"logs" ~label:"Logs";
          Tabs.tab ~id:"settings" ~label:"Settings";
        ]
    in
    {
      tabs;
      note = "Use ←/→/Home/End, Enter to confirm, Esc to return";
      next_page = None;
    }

  let update s (_ : msg) = s

  let view s ~focus:_ ~size:_ =
    let module W = Miaou_widgets_display.Widgets in
    let current_label =
      match Tabs.current s.tabs with
      | None -> W.dim "(no tabs)"
      | Some t -> Printf.sprintf "Selected: %s" (Tabs.label t)
    in
    let header = W.titleize "Tabs navigation" in
    let rendered = Tabs.render s.tabs ~focus:true in
    String.concat "\n\n" [header; rendered; W.dim s.note; current_label]

  let go_home s = {s with next_page = Some launcher_page_name}

  let handle_key s key_str ~size:_ =
    match Miaou.Core.Keys.of_string key_str with
    | Some (Miaou.Core.Keys.Char "Esc") | Some (Miaou.Core.Keys.Char "Escape")
      ->
        go_home s
    | Some Miaou.Core.Keys.Enter ->
        let msg =
          match Tabs.current s.tabs with
          | None -> "No selection"
          | Some t -> Printf.sprintf "Confirmed %s" (Tabs.label t)
        in
        {s with note = msg}
    | _ ->
        let tabs = Tabs.handle_key s.tabs ~key:key_str in
        {s with tabs}

  let move s delta =
    let dir = if delta < 0 then `Left else `Right in
    {s with tabs = Tabs.move s.tabs dir}

  let refresh s = s

  let enter s = s

  let service_select s _ = s

  let service_cycle s _ = s

  let handle_modal_key s _ ~size:_ = s

  let next_page s = s.next_page

  (* legacy key_bindings removed *)

  let keymap (_ : state) = []

  let back s = go_home s

  let has_modal _ = false
end

module Toast_demo_page : Miaou.Core.Tui_page.PAGE_SIG = struct
  module Toast = Miaou_widgets_layout.Toast_widget

  type state = {toasts : Toast.t; next_page : string option}

  type msg = unit

  let init () = {toasts = Toast.empty (); next_page = None}

  let update s (_ : msg) = s

  let positions = [|`Top_left; `Top_right; `Bottom_right; `Bottom_left|]

  let cycle_position p =
    let rec loop i =
      if i >= Array.length positions then 0
      else if positions.(i) = p then i
      else loop (i + 1)
    in
    positions.((loop 0 + 1) mod Array.length positions)

  let go_home s = {s with next_page = Some launcher_page_name}

  let add severity label s =
    let idx = List.length (Toast.to_list s.toasts) + 1 in
    let message = Printf.sprintf "%s #%d" label idx in
    {s with toasts = Toast.enqueue s.toasts severity message}

  let dismiss_oldest s =
    match Toast.to_list s.toasts with
    | [] -> s
    | t :: _ -> {s with toasts = Toast.dismiss s.toasts ~id:t.id}

  let set_position s =
    let next = cycle_position s.toasts.position in
    {s with toasts = Toast.with_position s.toasts next}

  let view s ~focus:_ ~size =
    let module W = Miaou_widgets_display.Widgets in
    let header = W.titleize "Toast notifications" in
    let tips =
      W.dim
        "1: info • 2: ok • 3: warn • 4: error • d: dismiss • p: position • \
         Esc: back"
    in
    let rendered = Toast.render s.toasts ~cols:size.LTerm_geom.cols in
    String.concat "\n" [header; tips; ""; rendered]

  let handle_key s key_str ~size:_ =
    match Miaou.Core.Keys.of_string key_str with
    | Some (Miaou.Core.Keys.Char "Esc") | Some (Miaou.Core.Keys.Char "Escape")
      ->
        go_home s
    | Some (Miaou.Core.Keys.Char "1") -> add Toast.Info "Info" s
    | Some (Miaou.Core.Keys.Char "2") -> add Toast.Success "Success" s
    | Some (Miaou.Core.Keys.Char "3") -> add Toast.Warn "Warning" s
    | Some (Miaou.Core.Keys.Char "4") -> add Toast.Error "Error" s
    | Some (Miaou.Core.Keys.Char "d") -> dismiss_oldest s
    | Some (Miaou.Core.Keys.Char "p") -> set_position s
    | _ -> s

  let move s _ = s

  let refresh s = {s with toasts = Toast.tick s.toasts}

  let enter s = s

  let service_select s _ = s

  let service_cycle s _ = refresh s

  let handle_modal_key s _ ~size:_ = s

  let next_page s = s.next_page

  (* legacy key_bindings removed *)

  let keymap (_ : state) = []

  let back s = go_home s

  let has_modal _ = false
end

module Spinner_progress_demo_page : Miaou.Core.Tui_page.PAGE_SIG = struct
  module Spinner = Miaou_widgets_layout.Spinner_widget
  module Progress = Miaou_widgets_layout.Progress_widget

  type state = {
    spinner : Spinner.t;
    progress : Progress.t;
    pct : float;
    running : bool;
    next_page : string option;
  }

  type msg = unit

  let init () =
    let spinner = Spinner.open_centered ~label:"Fetching data" () in
    let progress = Progress.open_inline ~width:30 ~label:"Download" () in
    {spinner; progress; pct = 0.; running = true; next_page = None}

  let update s _ = s

  let view s ~focus:_ ~size =
    let progress_line = Progress.render s.progress ~cols:size.LTerm_geom.cols in
    let spinner_line = Spinner.render s.spinner in
    let lines =
      ["Space: toggle run • r: reset • Esc: back"; spinner_line; progress_line]
    in
    String.concat "\n" lines

  let handle_key s key_str ~size:_ =
    match Miaou.Core.Keys.of_string key_str with
    | Some (Miaou.Core.Keys.Char "Esc") | Some (Miaou.Core.Keys.Char "Escape")
      ->
        {s with next_page = Some launcher_page_name}
    | Some (Miaou.Core.Keys.Char " ") -> {s with running = not s.running}
    | Some (Miaou.Core.Keys.Char "r") ->
        let progress = Progress.set_progress s.progress 0. in
        {s with pct = 0.; progress; running = true}
    | _ -> s

  let move s _ = s

  let advance s =
    if s.running then
      let spinner = Spinner.tick s.spinner in
      let pct = min 1. (s.pct +. 0.02) in
      let progress = Progress.set_progress s.progress pct in
      {s with spinner; pct; progress; running = pct < 1.}
    else s

  let refresh s = advance s

  let enter s = s

  let service_select s _ = s

  let service_cycle s _ = advance s

  let handle_modal_key s _ ~size:_ = s

  let next_page s = s.next_page

  (* legacy key_bindings removed *)

  let keymap (_ : state) = []

  let back s = {s with next_page = Some launcher_page_name}

  let has_modal _ = false
end

module Description_list_demo : Miaou.Core.Tui_page.PAGE_SIG = struct
  type state = {
    widget : Miaou_widgets_display.Description_list.t;
    next_page : string option;
  }

  type msg = unit

  let init () =
    let items =
      [("Name", "Alice"); ("Role", "Developer"); ("Location", "Remote")]
    in
    let widget =
      Miaou_widgets_display.Description_list.create ~title:"Profile" ~items ()
    in
    {widget; next_page = None}

  let update s _ = s

  let view s ~focus:_ ~size:_ =
    let body =
      Miaou_widgets_display.Description_list.render s.widget ~focus:false
    in
    let footer = "Press Esc to return to the launcher" in
    body ^ "\n\n" ^ footer

  let handle_key s key_str ~size:_ =
    match Miaou.Core.Keys.of_string key_str with
    | Some (Miaou.Core.Keys.Char "Esc")
    | Some (Miaou.Core.Keys.Char "Escape")
    | Some (Miaou.Core.Keys.Char "q") ->
        {s with next_page = Some launcher_page_name}
    | _ -> s

  let move s _ = s

  let refresh s = s

  let enter s = s

  let service_select s _ = s

  let service_cycle s _ = s

  let handle_modal_key s _ ~size:_ = s

  let next_page s = s.next_page

  (* legacy key_bindings removed *)

  let keymap (_ : state) = []

  let back s = {s with next_page = Some launcher_page_name}

  let has_modal _ = false
end

module Card_sidebar_demo_page : Miaou.Core.Tui_page.PAGE_SIG = struct
  module Card = Miaou_widgets_layout.Card_widget
  module Sidebar = Miaou_widgets_layout.Sidebar_widget

  type state = {next_page : string option; sidebar_open : bool}

  type msg = unit

  let init () = {next_page = None; sidebar_open = true}

  let update s _ = s

  let view s ~focus:_ ~size =
    let module W = Miaou_widgets_display.Widgets in
    let cols = max 50 size.LTerm_geom.cols in
    let card =
      Card.create
        ~title:"Card title"
        ~footer:"Footer"
        ~accent:81
        ~body:"Body text"
        ()
      |> fun c -> Card.render c ~cols
    in
    let sidebar =
      Sidebar.create
        ~sidebar:"Navigation\n- Item 1\n- Item 2"
        ~main:"Main content\nThis is the main panel."
        ~sidebar_open:s.sidebar_open
        ()
      |> fun layout -> Sidebar.render layout ~cols
    in
    let hint =
      if s.sidebar_open then "Tab: collapse sidebar" else "Tab: expand sidebar"
    in
    String.concat
      "\n\n"
      ["Card & Sidebar demo (Esc returns)"; card; sidebar; W.dim hint]

  let go_home sidebar_open = {next_page = Some launcher_page_name; sidebar_open}

  let handle_key s key_str ~size:_ =
    match Miaou.Core.Keys.of_string key_str with
    | Some (Miaou.Core.Keys.Char "Esc") | Some (Miaou.Core.Keys.Char "Escape")
      ->
        go_home s.sidebar_open
    | Some Miaou.Core.Keys.Tab
    | Some (Miaou.Core.Keys.Char "Tab")
    | Some (Miaou.Core.Keys.Char "NextPage") ->
        {s with sidebar_open = not s.sidebar_open}
    | _ -> {s with next_page = None}

  let move s _ = s

  let refresh s = s

  let enter s = s

  let service_select s _ = s

  let service_cycle s _ = s

  let handle_modal_key s _ ~size:_ = s

  let next_page s = s.next_page

  (* legacy key_bindings removed *)

  let keymap (_ : state) = []

  let back s = go_home s.sidebar_open

  let has_modal _ = false
end

module rec Page : Miaou.Core.Tui_page.PAGE_SIG = struct
  type step = {title : string}

  type state = {cursor : int; next_page : string option}

  type msg = Move of int

  let demos =
    [
      {title = "Textbox Widget"};
      {title = "Select Widget"};
      {title = "File Browser"};
      {title = "Table Widget"};
      {title = "Palette Sampler"};
      {title = "Logger Demo"};
      {title = "Key Handling"};
      {title = "Select Widget (records)"};
      {title = "Description List"};
      {title = "Pager Widget"};
      {title = "Tree Viewer"};
      {title = "Layout Helpers"};
      {title = "Breadcrumbs"};
      {title = "Tabs Navigation"};
      {title = "Toast Notifications"};
      {title = "Card & Sidebar"};
      {title = "Spinner & Progress"};
    ]

  let init () = {cursor = 0; next_page = None}

  let update s = function
    | Move d ->
        let hi = max 0 (List.length demos - 1) in
        {s with cursor = max 0 (min hi (s.cursor + d))}

  let open_demo s idx =
    let goto name page s =
      if not (Miaou.Core.Registry.exists name) then
        Miaou.Core.Registry.register name page ;
      {s with next_page = Some name}
    in
    match idx with
    | 0 ->
        Miaou.Core.Modal_manager.push
          (module Textbox_modal)
          ~init:(Textbox_modal.init ())
          ~ui:
            {
              title = "Textbox Demo";
              left = Some 20;
              max_width = Some 60;
              dim_background = true;
            }
          ~commit_on:["Enter"; "Tab"]
          ~cancel_on:["Esc"]
          ~on_close:(fun _ -> function
            | `Commit -> Logs.info (fun m -> m "Textbox committed")
            | `Cancel -> Logs.info (fun m -> m "Textbox cancelled")) ;
        s
    | 1 ->
        Miaou.Core.Modal_manager.confirm_with_extract
          (module Select_modal)
          ~init:(Select_modal.init ())
          ~title:"Select Demo"
          ~left:20
          ~max_width:60
          ~dim_background:true
          ~extract:Select_modal.extract_selection
          ~on_result:(fun res ->
            match res with
            | Some sel -> Logs.info (fun m -> m "Select committed: %s" sel)
            | None -> Logs.info (fun m -> m "Select cancelled"))
          () ;
        s
    | 2 ->
        Miaou.Core.Modal_manager.push
          (module File_browser_modal)
          ~init:(File_browser_modal.init ())
          ~ui:
            {
              title = "File Browser Demo";
              left = Some 10;
              max_width = Some 80;
              dim_background = true;
            }
          ~commit_on:["Commit"]
          ~cancel_on:["Esc"]
          ~on_close:(fun _ -> function
            | `Commit -> Logs.info (fun m -> m "File browser committed")
            | `Cancel -> Logs.info (fun m -> m "File browser cancelled")) ;
        s
    | 3 ->
        goto
          "demo_table"
          (module Table_demo_page : Miaou.Core.Tui_page.PAGE_SIG)
          s
    | 4 ->
        goto
          "demo_palette"
          (module Palette_demo_page : Miaou.Core.Tui_page.PAGE_SIG)
          s
    | 5 ->
        goto
          "demo_logger"
          (module Logger_demo_page : Miaou.Core.Tui_page.PAGE_SIG)
          s
    | 6 ->
        goto
          "demo_keys"
          (module Key_handling_demo_page : Miaou.Core.Tui_page.PAGE_SIG)
          s
    | 7 ->
        Miaou.Core.Modal_manager.confirm_with_extract
          (module Poly_select_modal)
          ~init:(Poly_select_modal.init ())
          ~title:"Select Demo (poly)"
          ~left:20
          ~max_width:60
          ~dim_background:true
          ~extract:Poly_select_modal.extract_selection
          ~on_result:(fun res ->
            match res with
            | Some sel -> Logs.info (fun m -> m "Poly select committed: %s" sel)
            | None -> Logs.info (fun m -> m "Poly select cancelled"))
          () ;
        s
    | 8 ->
        goto
          "demo_description_list"
          (module Description_list_demo : Miaou.Core.Tui_page.PAGE_SIG)
          s
    | 9 ->
        goto
          "demo_pager"
          (module Pager_demo_page : Miaou.Core.Tui_page.PAGE_SIG)
          s
    | 10 ->
        goto
          "demo_tree"
          (module Tree_demo_page : Miaou.Core.Tui_page.PAGE_SIG)
          s
    | 11 ->
        goto
          "demo_layout"
          (module Layout_demo_page : Miaou.Core.Tui_page.PAGE_SIG)
          s
    | 12 ->
        goto
          "demo_breadcrumbs"
          (module Breadcrumbs_demo_page : Miaou.Core.Tui_page.PAGE_SIG)
          s
    | 13 ->
        goto
          "demo_tabs"
          (module Tabs_demo_page : Miaou.Core.Tui_page.PAGE_SIG)
          s
    | 14 ->
        goto
          "demo_toast"
          (module Toast_demo_page : Miaou.Core.Tui_page.PAGE_SIG)
          s
    | 15 ->
        goto
          "demo_card_sidebar"
          (module Card_sidebar_demo_page : Miaou.Core.Tui_page.PAGE_SIG)
          s
    | 16 ->
        goto
          "demo_spinner"
          (module Spinner_progress_demo_page : Miaou.Core.Tui_page.PAGE_SIG)
          s
    | _ -> s

  let view s ~focus:_ ~size:_ =
    let module W = Miaou_widgets_display.Widgets in
    let header = W.titleize "MIAOU demo launcher" in
    let instructions =
      W.dim "Use ↑/↓ (or j/k) to move, Enter to launch a demo, q or Esc to exit"
    in
    let items =
      List.mapi
        (fun i d ->
          if i = s.cursor then W.green ("❯ " ^ d.title) else "  " ^ d.title)
        demos
    in
    String.concat "\n" (header :: instructions :: "" :: items)

  let handle_key s key_str ~size:_ =
    match Miaou.Core.Keys.of_string key_str with
    | Some Miaou.Core.Keys.Up -> update s (Move (-1))
    | Some Miaou.Core.Keys.Down -> update s (Move 1)
    | Some Miaou.Core.Keys.Left -> update s (Move (-1))
    | Some Miaou.Core.Keys.Right -> update s (Move 1)
    | Some Miaou.Core.Keys.Enter -> open_demo s s.cursor
    | Some (Miaou.Core.Keys.Char "q")
    | Some (Miaou.Core.Keys.Char "Esc")
    | Some (Miaou.Core.Keys.Char "Escape") ->
        {s with next_page = Some "__QUIT__"}
    | Some (Miaou.Core.Keys.Char " ") -> open_demo s s.cursor
    | None -> s
    | _ -> s

  let move s delta = update s (Move delta)

  let refresh s = s

  let enter s = open_demo s s.cursor

  let service_select s _ = s

  let service_cycle s _ = s

  let handle_modal_key s _ ~size:_ = s

  let next_page s = s.next_page

  (* legacy key_bindings removed *)

  let keymap (_ : state) = []

  let back s = s

  let has_modal _ = Miaou.Core.Modal_manager.has_active ()
end

and Key_handling_demo_page : Miaou.Core.Tui_page.PAGE_SIG = struct
  type state = {message : string; next_page : string option}

  type msg = KeyPressed of string

  let init () = {message = "Press any key..."; next_page = None}

  let update s = function
    | KeyPressed k -> {s with message = Printf.sprintf "Last key: %s" k}

  let view s ~focus:_ ~size:_ =
    s.message ^ "\n\n" ^ "Esc returns to the launcher"

  let handle_key s key_str ~size:_ =
    match Miaou.Core.Keys.of_string key_str with
    | Some (Miaou.Core.Keys.Char "Esc") | Some (Miaou.Core.Keys.Char "Escape")
      ->
        {s with next_page = Some launcher_page_name}
    | Some k -> update s (KeyPressed (Miaou.Core.Keys.to_string k))
    | None -> s

  let move s _ = s

  let refresh s = s

  let enter s = s

  let service_select s _ = s

  let service_cycle s _ = s

  let handle_modal_key s _ ~size:_ = s

  let next_page s = s.next_page

  (* legacy key_bindings removed *)

  let keymap (_ : state) = []

  let back s = {s with next_page = Some launcher_page_name}

  let has_modal _ = Miaou.Core.Modal_manager.has_active ()
end

let page : Miaou.Core.Registry.page =
  (module Page : Miaou.Core.Tui_page.PAGE_SIG)

let register_page () =
  if not (Miaou.Core.Registry.exists launcher_page_name) then
    Miaou.Core.Registry.register launcher_page_name page
