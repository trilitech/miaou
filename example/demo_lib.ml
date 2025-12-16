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
  if Sys.getenv_opt "MIAOU_DEBUG" = Some "1" then
    Printf.printf "miaou example: registered mocks\n"

let ensure_system_capability () =
  match Miaou_interfaces.System.get () with
  | Some _ -> ()
  | None -> failwith "capability missing: System (demo)"

module Fibers = Miaou_helpers.Fiber_runtime

(* Miaou demo launcher - using Miaou.Core.Tui_driver *)

let launcher_page_name = "miaou.demo.launcher"

let show_tutorial_modal ~title ~markdown =
  Tutorial_modal.show ~title ~markdown ()

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

  let handled_keys () = []

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

  let handled_keys () = []

  let extract_selection s = Miaou_widgets_input.Select_widget.get_selection s

  let back s = s

  let has_modal _ = false
end

module File_browser_modal : sig
  include
    Miaou.Core.Tui_page.PAGE_SIG
      with type state = Miaou_widgets_layout.File_browser_widget.t

  val selection_summary : state -> string
end = struct
  module FB = Miaou_widgets_layout.File_browser_widget

  type state = FB.t

  type msg = unit

  let init () =
    Miaou_widgets_layout.File_browser_widget.open_centered
      ~path:"./"
      ~dirs_only:false
      ()

  let update s _ = s

  let view s ~focus ~size = FB.render_with_size s ~focus ~size

  let handle_key s key_str ~size:_ = FB.handle_key s ~key:key_str

  let move s _ = s

  let refresh s = s

  let enter s = s

  let service_select s _ = s

  let service_cycle s _ = s

  let handle_modal_key s _ ~size:_ = s

  let selection_summary (s : state) =
    match FB.get_selection s with Some path -> path | None -> "<none>"

  let next_page _ = None

  (* legacy key_bindings removed *)

  let keymap (_ : state) = []

  let handled_keys () = []

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

  let handled_keys () = []

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

  let handled_keys () = []

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

  let handled_keys () = []

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

  let handled_keys () = []

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

  let handled_keys () = []

  let back s = {s with next_page = Some launcher_page_name}

  let has_modal _ = false
end

module Pager_demo_page : Miaou.Core.Tui_page.PAGE_SIG = struct
  module Pager = Miaou_widgets_display.Pager_widget
  module File_pager = Miaou_widgets_display.File_pager

  (* Cancellation for temp writer fiber *)
  let temp_writer_stop = ref (fun () -> ())

  type state = {
    pager : Pager.t;
    file : File_pager.t option;
    streaming : bool;
    ticks : int;
    next_page : string option;
  }

  type msg = unit

  let write_lines path lines =
    let oc =
      open_out_gen [Open_creat; Open_trunc; Open_wronly; Open_text] 0o644 path
    in
    List.iter
      (fun l ->
        output_string oc l ;
        output_char oc '\n')
      lines ;
    close_out_noerr oc

  let start_temp_writer path =
    let stopped = ref false in
    let _, sw = Fibers.require_runtime () in
    let cancel_promise, cancel_resolver = Eio.Promise.create () in
    (temp_writer_stop :=
       fun () ->
         if not !stopped then (
           stopped := true ;
           Eio.Promise.resolve cancel_resolver ())) ;
    Eio.Fiber.fork ~sw (fun () ->
        Fibers.with_env (fun env ->
            Eio.Fiber.first
              (fun () ->
                let rec loop n =
                  if !stopped then ()
                  else (
                    Eio.Time.sleep env#clock 0.2 ;
                    if !stopped then ()
                    else
                      let line =
                        Printf.sprintf
                          "[demo %04d] %0.3f"
                          n
                          (Eio.Time.now env#clock)
                      in
                      (try
                         let oc =
                           open_out_gen
                             [Open_creat; Open_wronly; Open_append; Open_text]
                             0o644
                             path
                         in
                         output_string oc line ;
                         output_char oc '\n' ;
                         close_out_noerr oc
                       with _ -> ()) ;
                      loop (n + 1))
                in
                loop 1)
              (fun () -> Eio.Promise.await cancel_promise)))

  let init () =
    (* Try to load a real system log file for demonstration *)
    let log_files =
      [
        "/var/log/pacman.log";
        (* Arch Linux package manager *)
        "/var/log/alternatives.log";
        (* Debian/Ubuntu *)
        "/var/log/dpkg.log";
        (* Debian/Ubuntu *)
        "/var/log/bootstrap.log";
        (* Debian/Ubuntu *)
        "/var/log/haskell-register.log";
        (* Haskell toolchain *)
      ]
    in
    let rec try_load_log = function
      | [] -> None
      | path :: rest -> (
          try
            let ic = open_in path in
            let lines = ref [] in
            (try
               while true do
                 lines := input_line ic :: !lines
               done
             with End_of_file -> close_in ic) ;
            let loaded_lines = List.rev !lines in
            if List.length loaded_lines > 0 then Some (path, loaded_lines)
            else try_load_log rest
          with _ -> try_load_log rest)
    in
    (* Try journalctl as fallback if no log file works *)
    let try_journalctl () =
      try
        let ic =
          Unix.open_process_in "journalctl --user -n 100 --no-pager 2>/dev/null"
        in
        let lines = ref [] in
        (try
           while true do
             lines := input_line ic :: !lines
           done
         with End_of_file -> ignore (Unix.close_process_in ic)) ;
        if List.length !lines > 10 then
          Some ("journalctl --user (last 100 entries)", List.rev !lines)
        else None
      with _ -> None
    in
    let _source, _title, _lines =
      match try_load_log log_files with
      | Some (path, log_lines) -> (`File path, path, log_lines)
      | None -> (
          match try_journalctl () with
          | Some (jctl_title, jctl_lines) -> (`External, jctl_title, jctl_lines)
          | None ->
              (* Final fallback to demo content *)
              ( `Demo,
                "/var/log/miaou-demo.log (demo)",
                ["Booting demo environment"; "All systems nominal"] ))
    in
    let temp_path = Filename.temp_file "miaou-pager-demo" ".log" in
    let initial_lines =
      [
        "Demo pager tail (temp file)";
        "New entries added every 200ms:";
        "";
        Printf.sprintf "Tailing %s (demo writer appends every 200ms)" temp_path;
      ]
    in
    write_lines temp_path initial_lines ;
    start_temp_writer temp_path ;
    let file =
      match File_pager.open_file ~follow:true temp_path with
      | Ok fp -> Some fp
      | Error _ -> None
    in
    let pager =
      match file with
      | Some fp -> File_pager.pager fp
      | None -> Pager.open_lines ~title:temp_path initial_lines
    in
    {pager; file; streaming = Option.is_some file; ticks = 0; next_page = None}

  let update s _ = s

  let close_file_if_any s =
    (* Stop the temp writer fiber *)
    !temp_writer_stop () ;
    match s.file with
    | Some fp ->
        File_pager.close fp ;
        {s with file = None}
    | None -> s

  let render_pager s ~focus ~size = Pager.render_with_size ~size s.pager ~focus

  let view s ~focus ~size =
    let header_lines =
      [
        "Pager widget demo - Real system log viewer";
        "/ search • n/p next/prev • f follow mode • a append • s streaming • \
         Esc back";
        "";
      ]
    in
    String.concat "\n" header_lines ^ render_pager s ~focus ~size

  let append_line s msg =
    Pager.append_lines s.pager [msg] ;
    s

  let toggle_streaming s =
    match s.file with
    | Some _ -> s (* Streaming driven by tailing; ignore manual toggle *)
    | None ->
        if s.streaming then (
          Pager.stop_streaming s.pager ;
          {s with streaming = false})
        else (
          Pager.start_streaming s.pager ;
          {s with streaming = true})

  let win_from size = max 3 (size.LTerm_geom.rows - 4)

  let handle_key s key_str ~size =
    let win = win_from size in
    (* Check if pager is in search mode first - if so, let it handle all keys except global Esc *)
    let pager_input_mode =
      match s.pager.Pager.input_mode with `Search_edit -> true | _ -> false
    in
    match Miaou.Core.Keys.of_string key_str with
    | Some (Miaou.Core.Keys.Char "Esc") | Some (Miaou.Core.Keys.Char "Escape")
      ->
        (* If pager is in search mode, let it handle Esc to close search bar *)
        if pager_input_mode then
          let pager, _ = Pager.handle_key ~win s.pager ~key:key_str in
          {s with pager}
        else
          (* Otherwise, Esc exits the demo *)
          s |> close_file_if_any |> fun s ->
          {s with next_page = Some launcher_page_name}
    | Some (Miaou.Core.Keys.Char "a") when not pager_input_mode ->
        let line =
          Printf.sprintf "[%0.3f] new log entry" (Unix.gettimeofday ())
        in
        append_line s line
    | Some (Miaou.Core.Keys.Char "s") when not pager_input_mode ->
        toggle_streaming s
    | Some (Miaou.Core.Keys.Char "f") when not pager_input_mode ->
        let pager, _ = Pager.handle_key ~win s.pager ~key:"f" in
        {s with pager}
    | Some k ->
        let key = Miaou.Core.Keys.to_string k in
        if Sys.getenv_opt "MIAOU_DEBUG" = Some "1" then
          Printf.eprintf
            "[DEMO] handle_key: raw='%s' parsed='%s' input_mode=%b\n%!"
            key_str
            key
            pager_input_mode ;
        let pager, _ = Pager.handle_key ~win s.pager ~key in
        {s with pager}
    | None ->
        if Sys.getenv_opt "MIAOU_DEBUG" = Some "1" then
          Printf.eprintf "[DEMO] handle_key: raw='%s' -> None\n%!" key_str ;
        s

  let move s _ = s

  let refresh s =
    (* Background file_pager fiber handles file reading; refresh just flushes. *)
    let s =
      match s.file with
      | None -> s
      | Some _ ->
          Pager.flush_pending_if_needed s.pager ;
          {s with streaming = true}
    in
    let ticks = s.ticks + 1 in
    if s.streaming && s.file = None && ticks mod 5 = 0 then (
      Pager.append_lines_batched
        s.pager
        [Printf.sprintf "stream chunk #%d" (ticks / 5)] ;
      Pager.flush_pending_if_needed s.pager) ;
    {s with ticks}

  let enter s = s

  let service_select s _ = s

  let service_cycle s _ = s

  let handle_modal_key s key ~size =
    (* Forward Enter to pager when in search mode *)
    let win = win_from size in
    let pager, _ = Pager.handle_key ~win s.pager ~key in
    {s with pager}

  let next_page s =
    match s.next_page with
    | Some _ ->
        let s = close_file_if_any s in
        s.next_page
    | None -> None

  (* legacy key_bindings removed *)

  let keymap (_ : state) = []

  let handled_keys () = []

  let back s =
    let s = close_file_if_any s in
    {s with next_page = Some launcher_page_name}

  let has_modal s =
    match s.pager.Pager.input_mode with `Search_edit -> true | _ -> false
end

module Tree_demo_page : Miaou.Core.Tui_page.PAGE_SIG = struct
  module Tree = Miaou_widgets_display.Tree_widget

  type state = {tree : Tree.t; next_page : string option}

  type msg = unit

  let sample_json =
    "{\"services\": {\"scheduler\": {\"status\": \"ready\"}, \"worker\":      \
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

  let handled_keys () = []

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

  let handled_keys () = []

  let back _ = {next_page = Some launcher_page_name}

  let has_modal _ = false
end

module Link_demo_page : Miaou.Core.Tui_page.PAGE_SIG = struct
  module Link = Miaou_widgets_navigation.Link_widget

  type state = {
    link : Link.t;
    target : Link.target;
    message : string;
    next_page : string option;
  }

  type msg = unit

  let init () =
    let target = Link.Internal "docs" in
    let link =
      Link.create ~label:"Open internal page" ~target ~on_navigate:(fun _ -> ())
    in
    {
      link;
      target;
      message = "Press Enter or Space to activate";
      next_page = None;
    }

  let update s (_ : msg) = s

  let view s ~focus:_ ~size:_ =
    let module W = Miaou_widgets_display.Widgets in
    let header = W.titleize "Link widget" in
    let body = Link.render s.link ~focus:true in
    String.concat "\n\n" [header; body; W.dim s.message]

  let go_home s = {s with next_page = Some launcher_page_name}

  let handle_key s key_str ~size:_ =
    match Miaou.Core.Keys.of_string key_str with
    | Some k ->
        let key = Miaou.Core.Keys.to_string k in
        let link, acted = Link.handle_key s.link ~key in
        let message =
          if acted then
            match s.target with
            | Link.Internal id -> Printf.sprintf "Navigated to %s" id
            | Link.External url -> Printf.sprintf "Would open %s" url
          else s.message
        in
        {s with link; message}
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

  let handled_keys () = []

  let back s = go_home s

  let has_modal _ = false
end

module Checkbox_demo_page : Miaou.Core.Tui_page.PAGE_SIG = struct
  module Checkbox = Miaou_widgets_input.Checkbox_widget
  module Focus_chain = Miaou_internals.Focus_chain

  let tutorial_markdown =
    {| 
# Checkbox widget quick tour

## Keyboard + focus flow
- Terminal, SDL, and headless drivers normalize `"Enter"`/`"Space"`, so the page only forwards those canonical strings to each checkbox.
- `Tab`/`BackTab` are delegated to [`Focus_chain`](../src/miaou_internals/focus_chain.ml), which keeps wrap-around behavior consistent with the other input demos.
- Small demo sets can expose number shortcuts (1/2/3 here) to make toggling instant without moving focus.

## Rendering patterns
- Prefix each checkbox with a dimmed label (e.g., `"1) "`) to hint at shortcuts while keeping widths stable.
- Compose checkboxes with `Flex_layout` when you need multi-column grids—the widget renders a short ANSI snippet so alignment is predictable.
- Highlight the focused entry by dimming the unfocused ones rather than inserting extra glyphs; this keeps reflow minimal when resizing.

## State management & testing
- Keep your model as `Checkbox.t list` plus the focus chain; updates are just `List.mapi` passes that call `Checkbox.handle_key`.
- Lifted state can be serialized for configuration panes, and snapshot tests of `Checkbox.render ~focus:true` are cheap regressions for styling changes.
- Add headless tests that simulate `"Enter"`/`" "` events and Tab rotation so driver tweaks cannot silently break the interaction contract.
|}

  type state = {
    boxes : Checkbox.t list;
    focus : Focus_chain.t;
    next_page : string option;
  }

  type msg = unit

  let init () =
    let boxes =
      [
        Checkbox.create ~label:"Enable metrics" ();
        Checkbox.create ~label:"Enable RPCs" ();
        Checkbox.create ~label:"Enable baking" ~checked_:true ();
      ]
    in
    {
      boxes;
      focus = Focus_chain.create ~total:(List.length boxes);
      next_page = None;
    }

  let update s (_ : msg) = s

  let view s ~focus:_ ~size:_ =
    let module W = Miaou_widgets_display.Widgets in
    let items =
      List.mapi
        (fun i cb ->
          let prefix = W.dim (Printf.sprintf "%d) " (i + 1)) in
          let focus = Focus_chain.current s.focus = Some i in
          prefix ^ Checkbox.render cb ~focus)
        s.boxes
    in
    let hint =
      W.dim
        "Tab rotates focus • 1/2/3 toggle • Space/Enter toggles focused • t \
         opens tutorial • Esc returns"
    in
    String.concat "\n" ((W.titleize "Checkboxes" :: items) @ [hint])

  let toggle idx s =
    let boxes =
      List.mapi
        (fun i cb ->
          if i = idx then Checkbox.handle_key cb ~key:"Space" else cb)
        s.boxes
    in
    {s with boxes}

  let toggle_focused key s =
    match Focus_chain.current s.focus with
    | Some idx ->
        let boxes =
          List.mapi
            (fun i cb -> if i = idx then Checkbox.handle_key cb ~key else cb)
            s.boxes
        in
        {s with boxes}
    | None -> s

  let go_home s = {s with next_page = Some launcher_page_name}

  let handle_key s key_str ~size:_ =
    match Miaou.Core.Keys.of_string key_str with
    | Some (Miaou.Core.Keys.Char "Esc") | Some (Miaou.Core.Keys.Char "Escape")
      ->
        go_home s
    | Some Miaou.Core.Keys.Tab | Some (Miaou.Core.Keys.Char "Tab") ->
        let focus, _ = Focus_chain.handle_key s.focus ~key:"Tab" in
        {s with focus}
    | Some (Miaou.Core.Keys.Char k) when String.lowercase_ascii k = "t" ->
        show_tutorial_modal
          ~title:"Checkbox tutorial"
          ~markdown:tutorial_markdown ;
        s
    | Some (Miaou.Core.Keys.Char n) -> (
        match int_of_string_opt n with
        | Some d when d >= 1 && d <= List.length s.boxes -> toggle (d - 1) s
        | _ -> toggle_focused key_str s)
    | _ -> toggle_focused key_str s

  let move s _ = s

  let refresh s = s

  let enter s = toggle_focused "Enter" s

  let service_select s _ = s

  let service_cycle s _ = s

  let handle_modal_key s _ ~size:_ = s

  let next_page s = s.next_page

  let keymap (_ : state) = []

  let handled_keys () = []

  let back s = go_home s

  let has_modal _ = false
end

module Radio_demo_page : Miaou.Core.Tui_page.PAGE_SIG = struct
  module Radio = Miaou_widgets_input.Radio_button_widget
  module Focus_chain = Miaou_internals.Focus_chain

  type state = {
    options : Radio.t list;
    focus : Focus_chain.t;
    next_page : string option;
  }

  type msg = unit

  let init () =
    let options =
      [
        Radio.create ~label:"Mainnet" ~selected:true ();
        Radio.create ~label:"Ghostnet" ();
        Radio.create ~label:"Custom" ();
      ]
    in
    {
      options;
      focus = Focus_chain.create ~total:(List.length options);
      next_page = None;
    }

  let update s (_ : msg) = s

  let view s ~focus:_ ~size:_ =
    let module W = Miaou_widgets_display.Widgets in
    let items =
      List.mapi
        (fun i r ->
          let prefix = W.dim (Printf.sprintf "%d) " (i + 1)) in
          let focus = Focus_chain.current s.focus = Some i in
          prefix ^ Radio.render r ~focus)
        s.options
    in
    String.concat "\n" (W.titleize "Radio buttons" :: items)

  let select idx s =
    let options =
      List.mapi
        (fun i r ->
          if i = idx then Radio.handle_key r ~key:"Enter"
          else Radio.set_selected r false)
        s.options
    in
    {s with options}

  let go_home s = {s with next_page = Some launcher_page_name}

  let handle_key s key_str ~size:_ =
    match Miaou.Core.Keys.of_string key_str with
    | Some (Miaou.Core.Keys.Char "Esc") | Some (Miaou.Core.Keys.Char "Escape")
      ->
        go_home s
    | Some Miaou.Core.Keys.Tab | Some (Miaou.Core.Keys.Char "Tab") ->
        let focus, _ = Focus_chain.handle_key s.focus ~key:"Tab" in
        {s with focus}
    | Some (Miaou.Core.Keys.Char n) -> (
        match int_of_string_opt n with
        | Some d when d >= 1 && d <= List.length s.options -> select (d - 1) s
        | _ -> s)
    | _ -> (
        match Focus_chain.current s.focus with
        | Some idx ->
            let options =
              List.mapi
                (fun i r ->
                  if i = idx then Radio.handle_key r ~key:key_str
                  else Radio.set_selected r false)
                s.options
            in
            {s with options}
        | None -> s)

  let move s _ = s

  let refresh s = s

  let enter s = s

  let service_select s _ = s

  let service_cycle s _ = s

  let handle_modal_key s _ ~size:_ = s

  let next_page s = s.next_page

  let keymap (_ : state) = []

  let handled_keys () = []

  let back s = go_home s

  let has_modal _ = false
end

module Switch_demo_page : Miaou.Core.Tui_page.PAGE_SIG = struct
  module Switch = Miaou_widgets_input.Switch_widget

  let tutorial_markdown =
    {| 
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
|}

  type state = {switch : Switch.t; next_page : string option}

  type msg = unit

  let init () =
    let switch = Switch.create ~label:"Auto-update" ~on:false () in
    {switch; next_page = None}

  let update s (_ : msg) = s

  let view s ~focus:_ ~size:_ =
    let module W = Miaou_widgets_display.Widgets in
    let header = W.titleize "Switch" in
    let body = Switch.render s.switch ~focus:true in
    let hint = W.dim "Space/Enter toggles • t opens tutorial • Esc returns" in
    String.concat "\n\n" [header; body; hint]

  let go_home s = {s with next_page = Some launcher_page_name}

  let handle_key s key_str ~size:_ =
    match Miaou.Core.Keys.of_string key_str with
    | Some (Miaou.Core.Keys.Char "Esc") | Some (Miaou.Core.Keys.Char "Escape")
      ->
        go_home s
    | Some (Miaou.Core.Keys.Char k) when String.lowercase_ascii k = "t" ->
        show_tutorial_modal ~title:"Switch tutorial" ~markdown:tutorial_markdown ;
        s
    | Some (Miaou.Core.Keys.Char " ") | Some Miaou.Core.Keys.Enter ->
        {s with switch = Switch.handle_key s.switch ~key:"Enter"}
    | _ -> s

  let move s _ = s

  let refresh s = s

  let enter s = s

  let service_select s _ = s

  let service_cycle s _ = s

  let handle_modal_key s _ ~size:_ = s

  let next_page s = s.next_page

  let keymap (_ : state) = []

  let handled_keys () = []

  let back s = go_home s

  let has_modal _ = false
end

module Button_demo_page : Miaou.Core.Tui_page.PAGE_SIG = struct
  module Button = Miaou_widgets_input.Button_widget

  type state = {button : Button.t; clicks : int; next_page : string option}

  type msg = unit

  let init () =
    let clicks = 0 in
    let button =
      Button.create
        ~label:"Deploy"
        ~on_click:(fun () -> Logs.info (fun m -> m "Clicked"))
        ()
    in
    {button; clicks; next_page = None}

  let update s (_ : msg) = s

  let view s ~focus:_ ~size:_ =
    let module W = Miaou_widgets_display.Widgets in
    let header = W.titleize "Button" in
    let body = Button.render s.button ~focus:true in
    let info = W.dim (Printf.sprintf "Clicks: %d" s.clicks) in
    String.concat "\n\n" [header; body; info]

  let go_home s = {s with next_page = Some launcher_page_name}

  let handle_key s key_str ~size:_ =
    let button, fired = Button.handle_key s.button ~key:key_str in
    let clicks = if fired then s.clicks + 1 else s.clicks in
    match Miaou.Core.Keys.of_string key_str with
    | Some (Miaou.Core.Keys.Char "Esc") | Some (Miaou.Core.Keys.Char "Escape")
      ->
        go_home {s with button; clicks}
    | _ -> {s with button; clicks}

  let move s _ = s

  let refresh s = s

  let enter s = s

  let service_select s _ = s

  let service_cycle s _ = s

  let handle_modal_key s _ ~size:_ = s

  let next_page s = s.next_page

  let keymap (_ : state) = []

  let handled_keys () = []

  let back s = go_home s

  let has_modal _ = false
end

module Validated_textbox_demo_page : Miaou.Core.Tui_page.PAGE_SIG = struct
  module Vtextbox = Miaou_widgets_input.Validated_textbox_widget

  type state = {box : int Vtextbox.t; next_page : string option}

  type msg = unit

  let validate_int s =
    match int_of_string_opt s with
    | Some v when v >= 0 -> Vtextbox.Valid v
    | _ -> Vtextbox.Invalid "Enter a non-negative integer"

  let init () =
    let box =
      Vtextbox.create
        ~title:"Instances"
        ~placeholder:(Some "e.g. 3")
        ~validator:validate_int
        ()
    in
    {box; next_page = None}

  let update s (_ : msg) = s

  let view s ~focus:_ ~size:_ =
    let module W = Miaou_widgets_display.Widgets in
    let header = W.titleize "Validated textbox" in
    let body = Vtextbox.render s.box ~focus:true in
    let status =
      match Vtextbox.validation_result s.box with
      | Vtextbox.Valid v -> W.green (Printf.sprintf "Valid: %d" v)
      | Vtextbox.Invalid msg -> W.red ("Error: " ^ msg)
    in
    String.concat "\n\n" [header; body; status]

  let go_home s = {s with next_page = Some launcher_page_name}

  let handle_key s key_str ~size:_ =
    match Miaou.Core.Keys.of_string key_str with
    | Some (Miaou.Core.Keys.Char "Esc") | Some (Miaou.Core.Keys.Char "Escape")
      ->
        go_home s
    | Some k ->
        let key = Miaou.Core.Keys.to_string k in
        {s with box = Vtextbox.handle_key s.box ~key}
    | None -> s

  let move s _ = s

  let refresh s = s

  let enter s = s

  let service_select s _ = s

  let service_cycle s _ = s

  let handle_modal_key s _ ~size:_ = s

  let next_page s = s.next_page

  let keymap (_ : state) = []

  let handled_keys () = []

  let back s = go_home s

  let has_modal _ = false
end

module Breadcrumbs_demo_page : Miaou.Core.Tui_page.PAGE_SIG = struct
  module Breadcrumbs = Miaou_widgets_navigation.Breadcrumbs_widget

  type state = {
    trail : Breadcrumbs.t;
    info : string;
    bubbled : int;
    next_page : string option;
  }

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
      bubbled = 0;
      next_page = None;
    }

  let update s (_ : msg) = s

  let view s ~focus:_ ~size:_ =
    let module W = Miaou_widgets_display.Widgets in
    let header = W.titleize "Breadcrumbs" in
    let trail = Breadcrumbs.render s.trail ~focus:true in
    let bubble_info =
      W.dim
        (Printf.sprintf "Bubbled keys handled by page: %d (press x)" s.bubbled)
    in
    String.concat "\n\n" [header; trail; W.dim s.info; bubble_info]

  let go_home s = {s with next_page = Some launcher_page_name}

  let handle_key s key_str ~size:_ =
    match Miaou.Core.Keys.of_string key_str with
    | Some (Miaou.Core.Keys.Char "Esc") | Some (Miaou.Core.Keys.Char "Escape")
      ->
        go_home s
    | _ ->
        let trail, handled =
          Breadcrumbs.handle_event ~bubble_unhandled:true s.trail ~key:key_str
        in
        let info =
          match handled with
          | `Handled ->
              let current =
                Breadcrumbs.current trail |> Option.map Breadcrumbs.id
                |> Option.value ~default:"(none)"
              in
              "Selected " ^ current
          | `Bubble when String.equal key_str "x" ->
              Printf.sprintf "Page handled bubbled key: %s" key_str
          | `Bubble -> s.info
        in
        let bubbled =
          match handled with
          | `Bubble when String.equal key_str "x" -> s.bubbled + 1
          | _ -> s.bubbled
        in
        {s with trail; info; bubbled}

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

  let handled_keys () = []

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

  let handled_keys () = []

  let back s = go_home s

  let has_modal _ = false
end

module Toast_demo_page : Miaou.Core.Tui_page.PAGE_SIG = struct
  module Toast = Miaou_widgets_layout.Toast_widget
  module Flash_bus = Lib_miaou_internal.Flash_bus
  module Flash_toast = Lib_miaou_internal.Flash_toast_renderer

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
        "1: info • 2: ok • 3: warn • 4: error • b: flash bus • d: dismiss • p: \n\
        \         position • Esc: back"
    in
    let rendered = Toast.render s.toasts ~cols:size.LTerm_geom.cols in
    let bus_block =
      let snapshot = Flash_bus.snapshot () in
      if snapshot = [] then W.dim "(flash bus empty)"
      else
        Flash_toast.render_snapshot
          ~position:`Bottom_right
          ~cols:size.LTerm_geom.cols
          snapshot
    in
    String.concat "\n" [header; tips; ""; rendered; ""; bus_block]

  let handle_key s key_str ~size:_ =
    match Miaou.Core.Keys.of_string key_str with
    | Some (Miaou.Core.Keys.Char "Esc") | Some (Miaou.Core.Keys.Char "Escape")
      ->
        go_home s
    | Some (Miaou.Core.Keys.Char "1") -> add Toast.Info "Info" s
    | Some (Miaou.Core.Keys.Char "2") -> add Toast.Success "Success" s
    | Some (Miaou.Core.Keys.Char "3") -> add Toast.Warn "Warning" s
    | Some (Miaou.Core.Keys.Char "4") -> add Toast.Error "Error" s
    | Some (Miaou.Core.Keys.Char "b") ->
        Flash_bus.push ~level:Flash_bus.Warn "Bus warning" ;
        s
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

  let handled_keys () = []

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

  let handled_keys () = []

  let back s = {s with next_page = Some launcher_page_name}

  let has_modal _ = false
end

module Flex_demo_page : Miaou.Core.Tui_page.PAGE_SIG = struct
  module Flex = Miaou_widgets_layout.Flex_layout
  module W = Miaou_widgets_display.Widgets

  type state = {next_page : string option}

  type msg = unit

  let init () = {next_page = None}

  let render_box title basis ~size =
    String.concat
      "\n"
      [
        W.titleize title;
        W.dim
          (Printf.sprintf
             "slot %dx%d · %s"
             size.LTerm_geom.cols
             size.rows
             basis);
      ]

  let row size =
    let children =
      [
        {
          Flex.render = render_box "Fixed" "Px 10";
          basis = Flex.Px 10;
          cross = None;
        };
        {
          Flex.render = render_box "Percent" "30%";
          basis = Flex.Percent 30.;
          cross = None;
        };
        {
          Flex.render = render_box "Ratio" "2x share";
          basis = Flex.Ratio 2.;
          cross = None;
        };
        {
          Flex.render = render_box "Fill" "Auto";
          basis = Flex.Fill;
          cross = None;
        };
      ]
    in
    Flex.create
      ~direction:Flex.Row
      ~gap:{h = 2; v = 0}
      ~padding:{left = 2; right = 2; top = 0; bottom = 0}
      ~align_items:Flex.Center
      ~justify:Flex.Space_between
      children
    |> fun flex -> Flex.render flex ~size

  let column size =
    let children =
      [
        {
          Flex.render = render_box "Top" "Fill";
          basis = Flex.Fill;
          cross = Some {width = Some 24; height = None};
        };
        {
          Flex.render = render_box "Middle" "Percent 40%";
          basis = Flex.Percent 40.;
          cross = None;
        };
        {
          Flex.render = render_box "Bottom" "Px 3";
          basis = Flex.Px 3;
          cross = None;
        };
      ]
    in
    Flex.create
      ~direction:Flex.Column
      ~gap:{h = 0; v = 1}
      ~padding:{left = 2; right = 2; top = 1; bottom = 1}
      ~align_items:Flex.Center
      ~justify:Flex.Center
      children
    |> fun flex -> Flex.render flex ~size

  let update s _ = s

  let view _ ~focus:_ ~size =
    let header = W.titleize "Flex layout (Esc returns)" in
    let desc =
      W.dim
        "Row: px + percent + ratio + fill with gaps | Column: centered \
         children. Resize to see wrap/stretch."
    in
    let row_height =
      if size.LTerm_geom.rows < 20 then 4 else max 4 (size.LTerm_geom.rows / 3)
    in
    let col_height =
      if size.LTerm_geom.rows < 20 then 6 else max 8 (size.LTerm_geom.rows / 2)
    in
    let row_block =
      row {LTerm_geom.cols = size.LTerm_geom.cols; rows = row_height}
    in
    let col_block =
      column {LTerm_geom.cols = size.LTerm_geom.cols; rows = col_height}
    in
    String.concat "\n\n" [header; desc; row_block; col_block]

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

  let handled_keys () = []

  let back _ = {next_page = Some launcher_page_name}

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
      [
        ("Name", "Alice in Wonderland");
        ("Role", "Developer");
        ( "Location",
          "Remote · Available for emergencies across multiple timezones" );
      ]
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

  let handled_keys () = []

  let back s = {s with next_page = Some launcher_page_name}

  let has_modal _ = false
end

module Card_sidebar_demo_page : Miaou.Core.Tui_page.PAGE_SIG = struct
  module Card = Miaou_widgets_layout.Card_widget
  module Sidebar = Miaou_widgets_layout.Sidebar_widget

  let tutorial_markdown =
    {| 
# Card + Sidebar layout

Use ↑/↓ to scroll this tutorial if needed.

- `Card_widget.render` wraps content with title/footer/accent styling.
- `Sidebar_widget.render` arranges a navigation column + main panel; we flip `~sidebar_open` on Tab.

```ocaml
let view s ~focus:_ ~size = 
  let cols = max 50 size.LTerm_geom.cols in 
  let card = Card.create ~title:"Card title" ~footer:"Footer" () |> Card.render ~cols in 
  let sidebar = 
    Sidebar.create ~sidebar:"Navigation…" ~main:"Main content…" ~sidebar_open:s.sidebar_open () 
    |> Sidebar.render ~cols 
  in 
  String.concat "\n\n" ["Card & Sidebar demo"; card; sidebar]
```
|}

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
    let hint = W.dim (Printf.sprintf "%s • t opens tutorial" hint) in
    String.concat
      "\n\n"
      ["Card & Sidebar demo (Esc returns)"; card; sidebar; hint]

  let go_home sidebar_open = {next_page = Some launcher_page_name; sidebar_open}

  let handle_key s key_str ~size:_ =
    match Miaou.Core.Keys.of_string key_str with
    | Some (Miaou.Core.Keys.Char "Esc") | Some (Miaou.Core.Keys.Char "Escape")
      ->
        go_home s.sidebar_open
    | Some (Miaou.Core.Keys.Char k) when String.lowercase_ascii k = "t" ->
        show_tutorial_modal
          ~title:"Card & Sidebar tutorial"
          ~markdown:tutorial_markdown ;
        s
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

  let handled_keys () = []

  let back s = go_home s.sidebar_open

  let has_modal _ = false
end

module Sparkline_demo_page : Miaou.Core.Tui_page.PAGE_SIG = struct
  module Sparkline = Miaou_widgets_display.Sparkline_widget

  let tutorial_markdown =
    {| 
# Sparkline Widgets

Sparklines display compact time-series data using Unicode block characters ( ▂▃▄▅▆▇█).

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
|}

  type state = {
    cpu_spark : Sparkline.t;
    mem_spark : Sparkline.t;
    net_spark : Sparkline.t;
    tick_count : int;
    next_page : string option;
  }

  type msg = unit

  let init () =
    {
      cpu_spark =
        Sparkline.create
          ~width:50
          ~max_points:50
          ~min_value:0.0
          ~max_value:100.0
          ();
      mem_spark =
        Sparkline.create
          ~width:50
          ~max_points:50
          ~min_value:0.0
          ~max_value:100.0
          ();
      net_spark = Sparkline.create ~width:50 ~max_points:50 ();
      tick_count = 0;
      next_page = None;
    }

  let update s (_ : msg) = s

  let simulate_tick s =
    (* Use real system metrics if available, otherwise simulate *)
    let cpu, mem, net =
      if Miaou_example.System_metrics.is_supported () then
        ( Miaou_example.System_metrics.get_cpu_usage (),
          Miaou_example.System_metrics.get_memory_usage (),
          Miaou_example.System_metrics.get_network_usage () )
      else
        (* Fallback to simulation on non-Linux systems *)
        (30. +. Random.float 40., 60. +. Random.float 30., Random.float 100.)
    in
    Sparkline.push s.cpu_spark cpu ;
    Sparkline.push s.mem_spark mem ;
    Sparkline.push s.net_spark net ;
    {s with tick_count = s.tick_count + 1}

  let view s ~focus:_ ~size:_ =
    let module W = Miaou_widgets_display.Widgets in
    let header = W.titleize "Sparkline Charts Demo" in
    let sep = String.make 60 '-' in
    let source =
      if Miaou_example.System_metrics.is_supported () then "Real system metrics"
      else "Simulated data (Linux /proc not available)"
    in
    let cpu_thresholds =
      [{Sparkline.value = 90.0; color = "31"}; {value = 75.0; color = "33"}]
    in
    let sparklines =
      [
        "";
        W.bold "Real-time Metrics:";
        W.dim source;
        "";
        Sparkline.render_with_label
          s.cpu_spark
          ~label:"CPU Usage"
          ~focus:true
          ~color:"32"
          ~thresholds:cpu_thresholds
          ();
        Sparkline.render_with_label
          s.mem_spark
          ~label:"Memory   "
          ~focus:false
          ~color:"34"
          ();
        Sparkline.render_with_label
          s.net_spark
          ~label:"Network  "
          ~focus:false
          ();
        "";
        sep;
        "";
        W.dim
          (Printf.sprintf
             "Data points: %d • Auto-updating (~150ms) • t tutorial • Esc \
              returns"
             s.tick_count);
      ]
    in

    String.concat "\n" (header :: sep :: sparklines)

  let go_home s = {s with next_page = Some launcher_page_name}

  let handle_key s key_str ~size:_ =
    match Miaou.Core.Keys.of_string key_str with
    | Some (Miaou.Core.Keys.Char "Esc") | Some (Miaou.Core.Keys.Char "Escape")
      ->
        go_home s
    | Some (Miaou.Core.Keys.Char k) when String.lowercase_ascii k = "t" ->
        show_tutorial_modal
          ~title:"Sparkline tutorial"
          ~markdown:tutorial_markdown ;
        s
    | Some (Miaou.Core.Keys.Char " ") -> simulate_tick s
    | Some (Miaou.Core.Keys.Char k) when String.lowercase_ascii k = "r" ->
        simulate_tick s
    | _ -> s

  let move s _ = s

  let refresh s = simulate_tick s

  let enter s = s

  let service_select s _ = s

  let service_cycle s _ = simulate_tick s

  let handle_modal_key s _ ~size:_ = s

  let next_page s = s.next_page

  let keymap (_ : state) = []

  let handled_keys () = []

  let back s = go_home s

  let has_modal _ = false
end

module Line_chart_demo_page : Miaou.Core.Tui_page.PAGE_SIG = struct
  module Line_chart = Miaou_widgets_display.Line_chart_widget

  let tutorial_markdown =
    {| 
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

- **Multi-series**: Plot multiple data series with different symbols (●■▲◆★)
- **Axes**: Optional X/Y axes with tick marks
- **Grid**: Optional grid lines for easier reading
- **Colors**: Optional ANSI color codes per series
- **Dynamic updates**: Use `update_series` or `add_point`

## When to Use

- Historical trends over time
- Comparing multiple metrics
- Visualizing functions or formulas
- Performance graphs (response times, throughput)

This demo shows sine/cosine waves. Press Space to add more points.
|}

  type state = {
    chart : Line_chart.t;
    point_count : int;
    mode : Line_chart.render_mode;
    next_page : string option;
  }

  type msg = unit

  let generate_sine_points count =
    List.init count (fun i ->
        let x = float_of_int i in
        let y = (sin (x /. 3.0) *. 30.0) +. 50.0 in
        let color = if y > 75.0 then Some "31" else None in
        {Line_chart.x; y; color})

  let generate_cosine_points count =
    List.init count (fun i ->
        let x = float_of_int i in
        let y = (cos (x /. 3.0) *. 30.0) +. 50.0 in
        {Line_chart.x; y; color = None})

  let init () =
    let sine_series =
      {
        Line_chart.label = "Sine";
        points = generate_sine_points 15;
        color = Some "32";
      }
    in
    let cosine_series =
      {
        Line_chart.label = "Cosine";
        points = generate_cosine_points 15;
        color = Some "34";
      }
    in
    {
      chart =
        Line_chart.create
          ~width:70
          ~height:18
          ~series:[sine_series; cosine_series]
          ~title:"Trigonometric Functions"
          ();
      point_count = 15;
      mode = Line_chart.ASCII;
      next_page = None;
    }

  let update s (_ : msg) = s

  let add_points s =
    let new_count = s.point_count + 5 in
    let chart =
      s.chart
      |> Line_chart.update_series
           ~label:"Sine"
           ~points:(generate_sine_points new_count)
      |> Line_chart.update_series
           ~label:"Cosine"
           ~points:(generate_cosine_points new_count)
    in
    {s with chart; point_count = new_count}

  let view s ~focus:_ ~size:_ =
    let module W = Miaou_widgets_display.Widgets in
    let header = W.titleize "Line Chart Demo" in
    let thresholds =
      [{Line_chart.value = 80.0; color = "31"}; {value = 60.0; color = "33"}]
    in
    let mode_label =
      match s.mode with Line_chart.ASCII -> "ASCII" | Braille -> "Braille"
    in
    let chart_output =
      Line_chart.render
        s.chart
        ~show_axes:true
        ~show_grid:true
        ~thresholds
        ~mode:s.mode
        ()
    in
    let hint =
      W.dim
        (Printf.sprintf
           "Points: %d • Space to add more • b toggle Braille (%s) • t \
            tutorial • Esc returns"
           s.point_count
           mode_label)
    in
    String.concat "\n" [header; ""; chart_output; ""; hint]

  let go_home s = {s with next_page = Some launcher_page_name}

  let handle_key s key_str ~size:_ =
    match Miaou.Core.Keys.of_string key_str with
    | Some (Miaou.Core.Keys.Char "Esc") | Some (Miaou.Core.Keys.Char "Escape")
      ->
        go_home s
    | Some (Miaou.Core.Keys.Char k) when String.lowercase_ascii k = "t" ->
        show_tutorial_modal
          ~title:"Line chart tutorial"
          ~markdown:tutorial_markdown ;
        s
    | Some (Miaou.Core.Keys.Char k) when String.lowercase_ascii k = "b" ->
        let mode =
          match s.mode with
          | Line_chart.ASCII -> Line_chart.Braille
          | Braille -> Line_chart.ASCII
        in
        {s with mode}
    | Some (Miaou.Core.Keys.Char " ") -> add_points s
    | _ -> s

  let move s _ = s

  let refresh s = s

  let enter s = s

  let service_select s _ = s

  let service_cycle s _ = s

  let handle_modal_key s _ ~size:_ = s

  let next_page s = s.next_page

  let keymap (_ : state) = []

  let handled_keys () = []

  let back s = go_home s

  let has_modal _ = false
end

module System_monitor_demo_page : Miaou.Core.Tui_page.PAGE_SIG = struct
  module Sparkline = Miaou_widgets_display.Sparkline_widget
  module Line_chart = Miaou_widgets_display.Line_chart_widget
  module Desc_list = Miaou_widgets_display.Description_list
  module SDL_render = System_monitor_sdl

  type state = {
    cpu_spark : Sparkline.t;
    mem_spark : Sparkline.t;
    net_spark : Sparkline.t;
    cpu_history : Line_chart.point list;
    tick_count : int;
    mode : Line_chart.render_mode;
    next_page : string option;
  }

  type msg = unit

  let init () =
    {
      cpu_spark =
        Sparkline.create
          ~width:35
          ~max_points:35
          ~min_value:0.0
          ~max_value:100.0
          ();
      mem_spark =
        Sparkline.create
          ~width:35
          ~max_points:35
          ~min_value:0.0
          ~max_value:100.0
          ();
      net_spark = Sparkline.create ~width:35 ~max_points:35 ();
      cpu_history = [];
      tick_count = 0;
      mode = Line_chart.ASCII;
      next_page = None;
    }

  let update s (_ : msg) = s

  let format_uptime seconds =
    let hours = int_of_float (seconds /. 3600.0) in
    let minutes = int_of_float (mod_float seconds 3600.0 /. 60.0) in
    Printf.sprintf "%dh %dm" hours minutes

  let update_metrics s =
    let cpu, mem, net =
      if Miaou_example.System_metrics.is_supported () then
        ( Miaou_example.System_metrics.get_cpu_usage (),
          Miaou_example.System_metrics.get_memory_usage (),
          Miaou_example.System_metrics.get_network_usage () )
      else (30. +. Random.float 40., 60. +. Random.float 30., Random.float 100.)
    in
    Sparkline.push s.cpu_spark cpu ;
    Sparkline.push s.mem_spark mem ;
    Sparkline.push s.net_spark net ;
    (* Keep last 50 points for line chart *)
    let new_point =
      {Line_chart.x = float_of_int s.tick_count; y = cpu; color = None}
    in
    let cpu_history =
      let hist = s.cpu_history @ [new_point] in
      if List.length hist > 50 then List.tl hist else hist
    in
    {s with cpu_history; tick_count = s.tick_count + 1}

  let view s ~focus:_ ~size =
    let module W = Miaou_widgets_display.Widgets in
    let width = size.LTerm_geom.cols in

    (* System info section *)
    let uptime = Miaou_example.System_metrics.get_uptime () in
    let load1, load5, load15 =
      Miaou_example.System_metrics.get_load_average ()
    in
    let sys_info =
      Desc_list.create
        ~title:"System Information"
        ~key_width:15
        ~items:
          [
            ("Hostname", try Unix.gethostname () with _ -> "unknown");
            ("Uptime", format_uptime uptime);
            ( "Load (1/5/15)",
              Printf.sprintf "%.2f / %.2f / %.2f" load1 load5 load15 );
            ("Updates", Printf.sprintf "%d ticks" s.tick_count);
          ]
        ()
    in
    (* Real-time metrics section *)
    let cpu_thresholds =
      [{Sparkline.value = 90.0; color = "31"}; {value = 75.0; color = "33"}]
    in
    let mode_label =
      match s.mode with Line_chart.ASCII -> "ASCII" | Braille -> "Braille"
    in

    (* Combine system info (left) with metrics (right) *)
    (* Calculate widths based on terminal size *)
    let separator_width = 3 in
    (* "│  " - no space before, two after *)
    let left_width = min 50 (width / 2) in
    let right_width = width - left_width - separator_width in

    (* Adjust sparkline widths dynamically - reserve space for labels and values *)
    let sparkline_width = max 20 (right_width - 25) in
    (* Reserve 25 chars for "NET: " + " 100.4 KB/s" *)
    let s_cpu_adjusted =
      Sparkline.create
        ~width:sparkline_width
        ~max_points:sparkline_width
        ~min_value:0.0
        ~max_value:100.0
        ()
    in
    let s_mem_adjusted =
      Sparkline.create
        ~width:sparkline_width
        ~max_points:sparkline_width
        ~min_value:0.0
        ~max_value:100.0
        ()
    in
    let s_net_adjusted =
      Sparkline.create ~width:sparkline_width ~max_points:sparkline_width ()
    in

    (* Copy data to adjusted sparklines *)
    Sparkline.get_data s.cpu_spark |> List.iter (Sparkline.push s_cpu_adjusted) ;
    Sparkline.get_data s.mem_spark |> List.iter (Sparkline.push s_mem_adjusted) ;
    Sparkline.get_data s.net_spark |> List.iter (Sparkline.push s_net_adjusted) ;

    (* Get current values *)
    let _, _, cpu_val = Sparkline.get_bounds s_cpu_adjusted in
    let _, _, mem_val = Sparkline.get_bounds s_mem_adjusted in
    let _, _, net_val = Sparkline.get_bounds s_net_adjusted in

    let spark_mode =
      match s.mode with
      | Line_chart.ASCII -> Sparkline.ASCII
      | Braille -> Braille
    in

    let cpu_line_adj =
      Printf.sprintf "CPU: %5.1f " cpu_val
      ^ Sparkline.render
          s_cpu_adjusted
          ~focus:false
          ~show_value:false
          ~thresholds:cpu_thresholds
          ~color:"32"
          ~mode:spark_mode
          ()
    in
    let mem_line_adj =
      Printf.sprintf "MEM: %5.1f " mem_val
      ^ Sparkline.render
          s_mem_adjusted
          ~focus:false
          ~show_value:false
          ~thresholds:[]
          ~color:"34"
          ~mode:spark_mode
          ()
    in
    let net_line_adj =
      Printf.sprintf "NET: %5.1f KB/s " net_val
      ^ Sparkline.render
          s_net_adjusted
          ~focus:false
          ~show_value:false
          ~thresholds:[]
          ~color:"35"
          ~mode:spark_mode
          ()
    in

    let sys_info_lines =
      String.split_on_char
        '\n'
        (Desc_list.render ~cols:left_width ~wrap:false sys_info ~focus:false)
    in
    let metrics_title_line =
      "  " ^ W.fg 45 "★" ^ " " ^ W.fg 213 (W.bold "Real-Time Metrics")
    in
    let metrics_lines =
      [metrics_title_line; ""; cpu_line_adj; mem_line_adj; net_line_adj]
    in

    let combined_info =
      let max_lines =
        max (List.length sys_info_lines) (List.length metrics_lines)
      in
      let pad_list lst len =
        lst @ List.init (len - List.length lst) (fun _ -> "")
      in
      let sys_padded = pad_list sys_info_lines max_lines in
      let metrics_padded = pad_list metrics_lines max_lines in
      List.mapi
        (fun i (left, right) ->
          (* Strip ANSI codes to calculate actual visible length *)
          let stripped =
            Str.global_replace (Str.regexp "\027\\[[0-9;]*m") "" left
          in
          let visible_len = String.length stripped in
          (* Title line (i=0) needs MORE padding *)
          let padding =
            max
              0
              (if i = 0 then left_width - visible_len + 2
               else left_width - visible_len)
          in
          let left_padded = left ^ String.make padding ' ' in
          left_padded ^ " " ^ W.dim "│" ^ " " ^ right)
        (List.combine sys_padded metrics_padded)
      |> String.concat "\n"
    in

    (* Historical CPU chart *)
    let cpu_chart =
      if List.length s.cpu_history >= 2 then
        let series =
          {
            Line_chart.label = "CPU %";
            points = s.cpu_history;
            color = Some "32";
          }
        in
        let chart =
          Line_chart.create
            ~width:(min 80 width)
            ~height:8
            ~series:[series]
            ~title:"CPU Usage History (last 50 samples)"
            ()
        in
        let thresholds =
          [
            {Line_chart.value = 90.0; color = "31"}; {value = 75.0; color = "33"};
          ]
        in
        "\n"
        ^ Line_chart.render
            chart
            ~show_axes:false
            ~show_grid:false
            ~thresholds
            ~mode:s.mode
            ()
      else ""
    in

    (* Assemble view *)
    let header = W.titleize "System Monitor" in
    let sep = String.make width '-' in
    let hint =
      W.dim
        (Printf.sprintf
           "Auto-updating every ~150ms • b toggle Braille (%s) • Esc to return"
           mode_label)
    in

    String.concat
      "\n"
      [header; sep; combined_info; ""; cpu_chart; ""; sep; hint]

  let go_home s = {s with next_page = Some launcher_page_name}

  let handle_key s key_str ~size:_ =
    match Miaou.Core.Keys.of_string key_str with
    | Some (Miaou.Core.Keys.Char "Esc") | Some (Miaou.Core.Keys.Char "Escape")
      ->
        go_home s
    | Some (Miaou.Core.Keys.Char k) when String.lowercase_ascii k = "b" ->
        let mode =
          match s.mode with
          | Line_chart.ASCII -> Line_chart.Braille
          | Braille -> Line_chart.ASCII
        in
        {s with mode}
    | _ -> s

  let move s _ = s

  let refresh s = update_metrics s

  let enter s = s

  let service_select s _ = s

  let service_cycle s _ = update_metrics s

  let handle_modal_key s _ ~size:_ = s

  let next_page s = s.next_page

  let keymap (_ : state) = []

  let handled_keys () = []

  let back s = go_home s

  let has_modal _ = false
end

module Bar_chart_demo_page : Miaou.Core.Tui_page.PAGE_SIG = struct
  module Bar_chart = Miaou_widgets_display.Bar_chart_widget

  let tutorial_markdown =
    {| 
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

## When to Use

- Comparing sales, revenue, or metrics by category
- Rankings (top performers, popular items)
- Resource usage by service/component
- Survey results or voting data

This demo shows daily sales. Press Space to randomize data.
|}

  type state = {data : Bar_chart.bar list; next_page : string option}

  type msg = unit

  let initial_data : Bar_chart.bar list =
    [
      ("Monday", 1250.0, None);
      ("Tuesday", 1800.0, None);
      ("Wednesday", 2100.0, Some "32");
      ("Thursday", 1650.0, None);
      ("Friday", 2400.0, Some "32");
      ("Saturday", 1900.0, None);
      ("Sunday", 1100.0, None);
    ]

  let init () = {data = initial_data; next_page = None}

  let update s (_ : msg) = s

  let randomize_data s =
    let new_data =
      List.map
        (fun (label, _, _) -> (label, 800.0 +. Random.float 1800.0, None))
        s.data
    in
    {s with data = new_data}

  let view s ~focus:_ ~size:_ =
    let module W = Miaou_widgets_display.Widgets in
    let header = W.titleize "Bar Chart Demo" in
    let thresholds =
      [{Bar_chart.value = 2000.0; color = "31"}; {value = 1500.0; color = "33"}]
    in
    let chart =
      Bar_chart.create
        ~width:70
        ~height:15
        ~data:s.data
        ~title:"Daily Sales ($)"
        ()
    in
    let chart_output =
      Bar_chart.render chart ~show_values:true ~thresholds ()
    in
    let hint = W.dim "Space to randomize • t for tutorial • Esc to return" in
    String.concat "\n" [header; ""; chart_output; ""; hint]

  let go_home s = {s with next_page = Some launcher_page_name}

  let handle_key s key_str ~size:_ =
    match Miaou.Core.Keys.of_string key_str with
    | Some (Miaou.Core.Keys.Char "Esc") | Some (Miaou.Core.Keys.Char "Escape")
      ->
        go_home s
    | Some (Miaou.Core.Keys.Char k) when String.lowercase_ascii k = "t" ->
        show_tutorial_modal
          ~title:"Bar chart tutorial"
          ~markdown:tutorial_markdown ;
        s
    | Some (Miaou.Core.Keys.Char " ") -> randomize_data s
    | _ -> s

  let move s _ = s

  let refresh s = s

  let enter s = s

  let service_select s _ = s

  let service_cycle s _ = s

  let handle_modal_key s _ ~size:_ = s

  let next_page s = s.next_page

  let keymap (_ : state) = []

  let handled_keys () = []

  let back s = go_home s

  let has_modal _ = false
end

module Qr_code_demo_page : Miaou.Core.Tui_page.PAGE_SIG = struct
  module QR = Miaou_widgets_display.Qr_code_widget

  let tutorial_markdown =
    {|
# QR Code Widgets

QR codes encode text or URLs into scannable 2D barcodes. Useful for sharing links, configuration, or data.

## Usage Pattern

```ocaml
match Qr_code_widget.create ~data:"https://example.com" ~scale:2 () with
| Ok qr ->
    let output = Qr_code_widget.render qr ~focus:true in
    print_endline output
| Error err ->
    Printf.eprintf "QR generation failed: %s\n" err
```

## Key Features

- **Automatic error correction**: Built-in error correction (M level by default)
- **Version auto-selection**: Automatically chooses QR version based on data size
- **Scale parameter**: Control visual size (1-4x recommended for terminal)
- **Quiet zone**: Automatic 4-module border as per QR spec
- **Terminal-friendly**: Uses block characters (█) for terminal display

## Integration Tips

- Use `update_data` to change QR content dynamically
- Scale of 1 for compact display, 2-3 for easy scanning
- Combine with modals for "Share" functionality
- Check return value - data might be too large for QR encoding

## Use Cases

- Share URLs or configuration in TUI apps
- Display API keys or tokens for mobile capture
- Quick data transfer to mobile devices
- 2FA setup flows (TOTP secrets)

This demo shows QR codes for different types of data. Press 1-4 to switch between examples.
|}

  type example = {label : string; data : string}

  type state = {
    examples : example list;
    current : int;
    next_page : string option;
  }

  type msg = unit

  let examples =
    [
      {label = "URL"; data = "miaou.dev"};
      {label = "Text"; data = "MIAOU"};
      {label = "Number"; data = "12345"};
      {label = "Email"; data = "hi@miaou.dev"};
    ]

  let init () = {examples; current = 0; next_page = None}

  let update s (_ : msg) = s

  let view s ~focus:_ ~size:_ =
    let module W = Miaou_widgets_display.Widgets in
    let header = W.titleize "QR Code Demo" in

    let example = List.nth s.examples s.current in
    let qr_result = QR.create ~data:example.data ~scale:1 () in

    let qr_lines =
      match qr_result with
      | Ok qr -> String.split_on_char '\n' (QR.render qr ~focus:true)
      | Error err -> ["QR Error: " ^ err]
    in

    (* Info panel to display on the right *)
    let info_lines =
      [
        W.bold
          (Printf.sprintf
             "Example %d/%d"
             (s.current + 1)
             (List.length s.examples));
        "";
        W.bold "Type: " ^ example.label;
        W.bold "Data: " ^ W.dim example.data;
        "";
        "Scan this QR code with";
        "your phone's camera to";
        "access the content.";
        "";
        W.dim "Keys:";
        W.dim "  1-4: Switch example";
        W.dim "  ?: Help";
        W.dim "  q: Back";
      ]
    in

    (* Combine QR code and info side by side *)
    let max_lines = max (List.length qr_lines) (List.length info_lines) in
    let combined_lines = ref [] in
    for i = 0 to max_lines - 1 do
      let qr_part =
        if i < List.length qr_lines then List.nth qr_lines i else ""
      in
      let info_part =
        if i < List.length info_lines then "  " ^ List.nth info_lines i else ""
      in
      combined_lines := (qr_part ^ info_part) :: !combined_lines
    done ;

    String.concat "\n" (header :: List.rev !combined_lines)

  let handle_key s key_str ~size:_ =
    match key_str with
    | "1" -> {s with current = 0}
    | "2" -> {s with current = 1}
    | "3" -> {s with current = 2}
    | "4" -> {s with current = 3}
    | "?" ->
        let () =
          show_tutorial_modal
            ~title:"QR Code Tutorial"
            ~markdown:tutorial_markdown
        in
        s
    | "q" -> {s with next_page = Some launcher_page_name}
    | _ -> s

  let move s _ = s

  let refresh s = s

  let enter s = s

  let service_select s _ = s

  let service_cycle s _ = s

  let handle_modal_key s _ ~size:_ = s

  let next_page s = s.next_page

  let keymap _ = []

  let handled_keys () = []

  let back s = {s with next_page = Some launcher_page_name}

  let has_modal _ = false
end

module Image_demo_page : Miaou.Core.Tui_page.PAGE_SIG = struct
  module Img = Miaou_widgets_display.Image_widget

  let tutorial_markdown =
    {|
# Image Widgets

Display images in the terminal using Unicode half-blocks (▀ ▄) with ANSI colors.

## Usage Pattern

```ocaml
match Image_widget.load_from_file "logo.png" ~max_width:80 ~max_height:24 () with
| Ok img ->
    let output = Image_widget.render img ~focus:true in
    print_endline output
| Error err ->
    Printf.eprintf "Failed to load: %s\n" err
```

## Key Features

- **Format support**: PNG, BMP, PPM, PGM, PBM (via imagelib)
- **Aspect ratio preservation**: Automatically scales while maintaining proportions
- **Half-block rendering**: 2 pixels per character cell for better resolution
- **ANSI 256-color**: Maps RGB to closest terminal colors
- **Memory efficiency**: Nearest-neighbor scaling, minimal allocations

## Rendering Details

Terminal rendering uses Unicode half-blocks:
- **▀** (upper half) - shows top pixel, bottom pixel in foreground and background colors
- **█** (full block) - when both pixels same color
- Achieves 2x vertical resolution vs simple character art

## Integration Tips

- Call `load_from_file` once, cache the result
- Use `max_width`/`max_height` to fit terminal size
- For dynamic resizing, reload on terminal size change
- Consider showing loading state for large images

## Use Cases

- Display logos or branding in TUI apps
- Show charts/graphs exported as images
- Preview image files in file browsers
- Display user avatars or thumbnails

This demo shows both file loading (PNG) and procedural image generation.
|}

  type display_mode = Logo | Gradient

  type state = {
    mode : display_mode;
    next_page : string option;
    logo_image : (Img.t, string) result option; (* Cached logo *)
    mutable logo_widget : Miaou_widgets_display.Image_widget.t option;
        (* Cached widget with frame tracking *)
    mutable gradient_widget : Miaou_widgets_display.Image_widget.t option;
  }

  type msg = KeyPressed of string

  let init () =
    (* Pre-load logo at init time to enable caching *)
    let logo_result =
      let module W = Miaou_widgets_display.Widgets in
      let img_width, img_height, logo_path =
        match W.get_backend () with
        | `Terminal -> (50, 25, "example/miaou_logo_small.png")
        | `Sdl -> (600, 450, "example/miaou_logo_small.png")
      in
      Img.load_from_file
        logo_path
        ~max_width:img_width
        ~max_height:img_height
        ()
    in
    {
      mode = Logo;
      next_page = None;
      logo_image = Some logo_result;
      logo_widget = None;
      gradient_widget = None;
    }

  let update s = function
    | KeyPressed ("escape" | "Esc") ->
        {s with next_page = Some launcher_page_name}
    | KeyPressed _ -> s

  (* Create a simple gradient image *)
  let create_gradient_image width height =
    let rgb_data = Bytes.create (width * height * 3) in
    for y = 0 to height - 1 do
      for x = 0 to width - 1 do
        let offset = ((y * width) + x) * 3 in
        (* Rainbow gradient *)
        let r = x * 255 / width in
        let g = y * 255 / height in
        let b = (x + y) * 255 / (width + height) in
        Bytes.set rgb_data offset (Char.chr r) ;
        Bytes.set rgb_data (offset + 1) (Char.chr g) ;
        Bytes.set rgb_data (offset + 2) (Char.chr b)
      done
    done ;
    Img.create_from_rgb ~width ~height ~rgb_data ()

  let view s ~focus:_ ~size:_ =
    let module W = Miaou_widgets_display.Widgets in
    let header = W.titleize "Image Widget Demo" in

    (* Image dimensions: constrain for TUI, reasonable for SDL *)
    let img_width, img_height =
      match W.get_backend () with
      | `Terminal -> (50, 25) (* Constrained for TUI layout *)
      | `Sdl -> (600, 450)
      (* Smaller for responsive SDL *)
    in

    let img_display, img_info =
      match s.mode with
      | Logo ->
          (* Check if SDL context is disabled (during transition capture) *)
          let sdl_context =
            Miaou_widgets_display.Sdl_chart_context.get_context ()
          in
          let in_transition = W.get_backend () = `Sdl && sdl_context = None in

          if in_transition then
            (* During transition - use lightweight placeholder *)
            ("", "Loading...")
          else
            (* Use or create cached widget *)
            let widget =
              match s.logo_widget with
              | Some w -> w
              | None -> (
                  let img_result =
                    match s.logo_image with
                    | Some result -> result
                    | None -> Error "Image not loaded at init"
                  in
                  match img_result with
                  | Ok img ->
                      s.logo_widget <- Some img ;
                      img
                  | Error _ ->
                      let img = create_gradient_image img_width img_height in
                      s.logo_widget <- Some img ;
                      img)
            in
            let w, h = Img.get_dimensions widget in
            let backend_info =
              match W.get_backend () with
              | `Terminal ->
                  "TUI (cropped)\nUnicode half-blocks (▀▄)\nANSI 256-color"
              | `Sdl -> "SDL (full image)\nDirect pixel rendering"
            in
            ( Img.render widget ~focus:true,
              Printf.sprintf
                "MIAOU Logo\nDisplayed: %d×%d\n\n%s"
                w
                h
                backend_info )
      | Gradient ->
          let widget =
            match s.gradient_widget with
            | Some w -> w
            | None ->
                let img = create_gradient_image img_width img_height in
                s.gradient_widget <- Some img ;
                img
          in
          ( Img.render widget ~focus:true,
            Printf.sprintf
              "Procedural Gradient\nGenerated: %d×%d pixels\nRGB interpolation"
              img_width
              img_height )
    in

    let mode_label =
      match s.mode with
      | Logo -> W.bold "1: Logo (current)"
      | Gradient -> "1: Logo"
    in
    let gradient_label =
      match s.mode with
      | Logo -> "2: Gradient"
      | Gradient -> W.bold "2: Gradient (current)"
    in

    (* Side-by-side layout: image on left, details on right *)
    let img_lines = String.split_on_char '\n' img_display in
    let info_lines = String.split_on_char '\n' img_info in
    let max_img_lines = List.length img_lines in

    let combined_lines = ref [] in
    for i = 0 to max_img_lines - 1 do
      let img_line =
        if i < List.length img_lines then List.nth img_lines i else ""
      in
      let info_line =
        if i < List.length info_lines then "  │ " ^ List.nth info_lines i
        else ""
      in
      combined_lines := (img_line ^ info_line) :: !combined_lines
    done ;

    let combined = String.concat "\n" (List.rev !combined_lines) in

    let instructions =
      W.dim (mode_label ^ " | " ^ gradient_label ^ " | ?: help | q: back")
    in

    String.concat "\n\n" [header; combined; instructions]

  let handle_key s key_str ~size:_ =
    let s = update s (KeyPressed key_str) in
    match key_str with
    | "1" -> {s with mode = Logo}
    | "2" -> {s with mode = Gradient}
    | "?" ->
        let () =
          show_tutorial_modal
            ~title:"Image Widget Tutorial"
            ~markdown:tutorial_markdown
        in
        s
    | "q" -> {s with next_page = Some launcher_page_name}
    | _ -> s

  let move s _ = s

  let refresh s = s

  let enter s = s

  let service_select s _ = s

  let service_cycle s _ = s

  let handle_modal_key s _ ~size:_ = s

  let next_page s = s.next_page

  let keymap _ = []

  let handled_keys () = []

  let back s = {s with next_page = Some launcher_page_name}

  let has_modal _ = false
end

module rec Page : Miaou.Core.Tui_page.PAGE_SIG = struct
  type step = {title : string; open_demo : state -> state}

  and state = {cursor : int; next_page : string option}

  type msg = Move of int

  let goto name page =
    let f s =
      if not (Miaou.Core.Registry.exists name) then
        Miaou.Core.Registry.register name page ;
      {s with next_page = Some name}
    in
    f

  let demos =
    [
      {
        title = "Textbox Widget";
        open_demo =
          (fun s ->
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
            s);
      };
      {
        title = "Select Widget";
        open_demo =
          (fun s ->
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
            s);
      };
      {
        title = "File Browser";
        open_demo =
          (fun s ->
            let module FB = Miaou_widgets_layout.File_browser_widget in
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
              ~commit_on:["s"]
              ~cancel_on:["Esc"]
              ~on_close:(fun (st : File_browser_modal.state) -> function
                | `Commit ->
                    let sel =
                      match FB.get_selection st with
                      | Some path -> path
                      | None -> "<none>"
                    in
                    Logs.info (fun m -> m "File browser committed: %s" sel) ;
                    show_tutorial_modal
                      ~title:"Selected path"
                      ~markdown:(Printf.sprintf "You selected:\\n\\n`%s`" sel)
                | `Cancel ->
                    Logs.info (fun m ->
                        m
                          "File browser cancelled (was on %s)"
                          (match FB.get_selection st with
                          | Some path -> path
                          | None -> "<none>"))) ;
            s);
      };
      {
        title = "Table Widget";
        open_demo =
          goto
            "demo_table"
            (module Table_demo_page : Miaou.Core.Tui_page.PAGE_SIG);
      };
      {
        title = "Palette Sampler";
        open_demo =
          goto
            "demo_palette"
            (module Palette_demo_page : Miaou.Core.Tui_page.PAGE_SIG);
      };
      {
        title = "Logger Demo";
        open_demo =
          goto
            "demo_logger"
            (module Logger_demo_page : Miaou.Core.Tui_page.PAGE_SIG);
      };
      {
        title = "Key Handling";
        open_demo =
          goto
            "demo_keys"
            (module Key_handling_demo_page : Miaou.Core.Tui_page.PAGE_SIG);
      };
      {
        title = "Select Widget (records)";
        open_demo =
          (fun s ->
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
                | Some sel ->
                    Logs.info (fun m -> m "Poly select committed: %s" sel)
                | None -> Logs.info (fun m -> m "Poly select cancelled"))
              () ;
            s);
      };
      {
        title = "Description List";
        open_demo =
          goto
            "demo_description_list"
            (module Description_list_demo : Miaou.Core.Tui_page.PAGE_SIG);
      };
      {
        title = "Pager Widget";
        open_demo =
          goto
            "demo_pager"
            (module Pager_demo_page : Miaou.Core.Tui_page.PAGE_SIG);
      };
      {
        title = "Tree Viewer";
        open_demo =
          goto
            "demo_tree"
            (module Tree_demo_page : Miaou.Core.Tui_page.PAGE_SIG);
      };
      {
        title = "Layout Helpers";
        open_demo =
          goto
            "demo_layout"
            (module Layout_demo_page : Miaou.Core.Tui_page.PAGE_SIG);
      };
      {
        title = "Flex Layout";
        open_demo =
          goto
            "demo_flex"
            (module Flex_demo_page : Miaou.Core.Tui_page.PAGE_SIG);
      };
      {title = "Link"; open_demo = goto "demo_link" (module Link_demo_page)};
      {
        title = "Checkboxes";
        open_demo =
          goto
            "demo_checkboxes"
            (module Checkbox_demo_page : Miaou.Core.Tui_page.PAGE_SIG);
      };
      {
        title = "Radio Buttons";
        open_demo =
          goto
            "demo_radio"
            (module Radio_demo_page : Miaou.Core.Tui_page.PAGE_SIG);
      };
      {
        title = "Switch";
        open_demo =
          goto
            "demo_switch"
            (module Switch_demo_page : Miaou.Core.Tui_page.PAGE_SIG);
      };
      {
        title = "Button";
        open_demo =
          goto
            "demo_button"
            (module Button_demo_page : Miaou.Core.Tui_page.PAGE_SIG);
      };
      {
        title = "Validated Textbox";
        open_demo =
          goto
            "demo_validated_textbox"
            (module Validated_textbox_demo_page : Miaou.Core.Tui_page.PAGE_SIG);
      };
      {
        title = "Breadcrumbs";
        open_demo =
          goto
            "demo_breadcrumbs"
            (module Breadcrumbs_demo_page : Miaou.Core.Tui_page.PAGE_SIG);
      };
      {
        title = "Tabs Navigation";
        open_demo =
          goto
            "demo_tabs"
            (module Tabs_demo_page : Miaou.Core.Tui_page.PAGE_SIG);
      };
      {
        title = "Toast Notifications";
        open_demo =
          goto
            "demo_toast"
            (module Toast_demo_page : Miaou.Core.Tui_page.PAGE_SIG);
      };
      {
        title = "Card & Sidebar";
        open_demo =
          goto
            "demo_card_sidebar"
            (module Card_sidebar_demo_page : Miaou.Core.Tui_page.PAGE_SIG);
      };
      {
        title = "Spinner & Progress";
        open_demo =
          goto
            "demo_spinner"
            (module Spinner_progress_demo_page : Miaou.Core.Tui_page.PAGE_SIG);
      };
      {
        title = "Sparkline Charts";
        open_demo =
          goto
            "demo_sparkline"
            (module Sparkline_demo_page : Miaou.Core.Tui_page.PAGE_SIG);
      };
      {
        title = "Line Chart";
        open_demo =
          goto
            "demo_line_chart"
            (module Line_chart_demo_page : Miaou.Core.Tui_page.PAGE_SIG);
      };
      {
        title = "Bar Chart";
        open_demo =
          goto
            "demo_bar_chart"
            (module Bar_chart_demo_page : Miaou.Core.Tui_page.PAGE_SIG);
      };
      {
        title = "System Monitor (Showcase)";
        open_demo =
          goto
            "demo_system_monitor"
            (module System_monitor_demo_page : Miaou.Core.Tui_page.PAGE_SIG);
      };
      {
        title = "QR Code";
        open_demo =
          goto
            "demo_qr_code"
            (module Qr_code_demo_page : Miaou.Core.Tui_page.PAGE_SIG);
      };
      {
        title = "Image";
        open_demo =
          goto
            "demo_image"
            (module Image_demo_page : Miaou.Core.Tui_page.PAGE_SIG);
      };
    ]

  let init () = {cursor = 0; next_page = None}

  let update s = function
    | Move d ->
        let hi = max 0 (List.length demos - 1) in
        {s with cursor = max 0 (min hi (s.cursor + d))}

  let open_demo s idx =
    match List.nth_opt demos idx with Some d -> d.open_demo s | None -> s

  let view s ~focus:_ ~size =
    let module W = Miaou_widgets_display.Widgets in
    (* The terminal renderer treats the first line as the page title and wraps
       the rest in a frame with its own title/separator/footer. Keep this first
       line plain (no embedded newlines), and size our body so the frame does
       not exceed [size.rows] (otherwise the renderer trims lines in the middle,
       desynchronizing cursor and viewport). *)
    let title = "MIAOU demo launcher" in
    let instructions =
      W.dim "Use ↑/↓ (or j/k) to move, Enter to launch a demo, q or Esc to exit"
    in
    let header_overhead = if size.LTerm_geom.cols < 80 then 1 else 0 in
    let frame_overhead =
      (* title + separator + footer hints (driver caps to 3 lines) *)
      2 + 3 + header_overhead
    in
    let body_rows_available = max 0 (size.LTerm_geom.rows - frame_overhead) in
    let items_capacity =
      (* instructions + blank line *)
      max 1 (body_rows_available - 2)
    in
    let max_lines = min 12 items_capacity in
    let start =
      let total = List.length demos in
      let max_start = max 0 (total - max_lines) in
      let desired = s.cursor - max_lines + 1 in
      max 0 (min desired max_start)
    in
    let slice =
      List.filteri (fun i _ -> i >= start && i < start + max_lines) demos
    in
    let items =
      List.mapi
        (fun idx d ->
          let i = start + idx in
          if i = s.cursor then W.green ("❯ " ^ d.title) else "  " ^ d.title)
        slice
    in
    String.concat "\n" (title :: instructions :: "" :: items)

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

  let handled_keys () = []

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

  let handled_keys () = []

  let back s = {s with next_page = Some launcher_page_name}

  let has_modal _ = Miaou.Core.Modal_manager.has_active ()
end

let page : Miaou.Core.Registry.page =
  (module Page : Miaou.Core.Tui_page.PAGE_SIG)

let register_page () =
  if not (Miaou.Core.Registry.exists launcher_page_name) then
    Miaou.Core.Registry.register launcher_page_name page

type 'size bench_case = {name : string; run : size:'size -> int}

type bench = LTerm_geom.size bench_case

let bench_size : LTerm_geom.size = {LTerm_geom.rows = 40; cols = 120}

let make_page_case name (module P : Miaou.Core.Tui_page.PAGE_SIG) =
  let run ~size =
    let state = P.init () in
    String.length (P.view state ~focus:false ~size)
  in
  {name; run}

let line_chart_braille_case =
  let module LC = Miaou_widgets_display.Line_chart_widget in
  let run ~size =
    let series =
      let make_wave f color =
        {
          LC.label = "wave";
          points =
            List.init 60 (fun i ->
                let x = float_of_int i in
                let y = f x in
                {LC.x; y; color = None});
          color;
        }
      in
      [
        make_wave (fun x -> (sin (x /. 4.) *. 30.) +. 50.) (Some "32");
        make_wave (fun x -> (cos (x /. 5.) *. 30.) +. 40.) (Some "34");
      ]
    in
    let chart =
      LC.create
        ~width:(min 120 size.LTerm_geom.cols)
        ~height:(min 20 size.LTerm_geom.rows)
        ~series
        ()
    in
    LC.render
      chart
      ~show_axes:true
      ~show_grid:true
      ~thresholds:[{LC.value = 75.; color = "33"}; {value = 90.; color = "31"}]
      ~mode:LC.Braille
      ()
    |> String.length
  in
  {name = "line_chart_braille"; run}

let sparkline_braille_case =
  let module SP = Miaou_widgets_display.Sparkline_widget in
  let run ~size =
    let width = min 100 size.LTerm_geom.cols in
    let sp =
      SP.create ~width ~max_points:(width * 2) ~min_value:0. ~max_value:100. ()
    in
    for i = 0 to (width * 2) - 1 do
      let v = 50. +. (40. *. sin (float_of_int i /. 6.)) in
      SP.push sp v
    done ;
    SP.render
      sp
      ~focus:false
      ~show_value:false
      ~color:"36"
      ~thresholds:[{SP.value = 80.; color = "31"}; {value = 60.; color = "33"}]
      ~mode:SP.Braille
      ()
    |> String.length
  in
  {name = "sparkline_braille"; run}

let bar_chart_braille_case =
  let module BC = Miaou_widgets_display.Bar_chart_widget in
  let run ~size =
    let labels = ["Mon"; "Tue"; "Wed"; "Thu"; "Fri"; "Sat"; "Sun"] in
    let data =
      List.mapi
        (fun i lbl ->
          let base = 40. +. float_of_int (i * 7 mod 30) in
          (lbl, base, None))
        labels
    in
    let chart =
      BC.create
        ~width:(min 120 size.LTerm_geom.cols)
        ~height:(min 15 size.LTerm_geom.rows)
        ~data
        ~title:"Weekly"
        ()
    in
    BC.render
      chart
      ~show_values:false
      ~thresholds:[{BC.value = 60.; color = "33"}; {value = 80.; color = "31"}]
      ~mode:BC.Braille
      ()
    |> String.length
  in
  {name = "bar_chart_braille"; run}

let bench_cases : bench list =
  [
    make_page_case "table" (module Table_demo_page);
    make_page_case "poly_table" (module Poly_table_demo_page);
    make_page_case "pager" (module Pager_demo_page);
    make_page_case "layout" (module Layout_demo_page);
    make_page_case "flex" (module Flex_demo_page);
    make_page_case "toast" (module Toast_demo_page);
    make_page_case "spinner" (module Spinner_progress_demo_page);
    make_page_case "sparkline" (module Sparkline_demo_page);
    sparkline_braille_case;
    make_page_case "line_chart" (module Line_chart_demo_page);
    line_chart_braille_case;
    make_page_case "bar_chart" (module Bar_chart_demo_page);
    bar_chart_braille_case;
    make_page_case "tree" (module Tree_demo_page);
    make_page_case "breadcrumbs" (module Breadcrumbs_demo_page);
    make_page_case "tabs" (module Tabs_demo_page);
    make_page_case "link" (module Link_demo_page);
    make_page_case "checkbox" (module Checkbox_demo_page);
    make_page_case "radio" (module Radio_demo_page);
    make_page_case "switch" (module Switch_demo_page);
    make_page_case "button" (module Button_demo_page);
    make_page_case "validated_textbox" (module Validated_textbox_demo_page);
    make_page_case "description_list" (module Description_list_demo);
    make_page_case "card_sidebar" (module Card_sidebar_demo_page);
    make_page_case "qr_code" (module Qr_code_demo_page);
    (* Image widget excluded - too slow for benchmarking *)
  ]

let bench_names () = List.map (fun c -> c.name) bench_cases

let run_bench_case ~count case =
  let rec loop i acc =
    if i = count then acc
    else
      let bytes = case.run ~size:bench_size in
      loop (i + 1) (acc + bytes)
  in
  let start = Unix.gettimeofday () in
  let bytes = loop 0 0 in
  let elapsed = Unix.gettimeofday () -. start in
  Printf.printf
    "%s iterations=%d bytes=%d time=%.3fs\n"
    case.name
    count
    bytes
    elapsed ;
  flush stdout

let run_bench ~target ~count =
  let selected =
    if String.equal target "all" then bench_cases
    else
      match List.find_opt (fun c -> String.equal c.name target) bench_cases with
      | Some c -> [c]
      | None ->
          let available = String.concat ", " (bench_names ()) in
          invalid_arg
            (Printf.sprintf
               "Unknown bench '%s'. Available: %s or 'all'"
               target
               available)
  in
  List.iter (run_bench_case ~count) selected
