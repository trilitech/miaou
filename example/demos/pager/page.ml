(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

module Inner = struct
  let tutorial_title = "Pager Widget"

  let tutorial_markdown = [%blob "README.md"]

  module Pager = Miaou_widgets_display.Pager_widget
  module File_pager = Miaou_widgets_display.File_pager
  module Fibers = Miaou_helpers.Fiber_runtime

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
    let log_files =
      [
        "/var/log/pacman.log";
        "/var/log/alternatives.log";
        "/var/log/dpkg.log";
        "/var/log/bootstrap.log";
        "/var/log/haskell-register.log";
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
        "/ search • n/p next/prev • f follow mode • a append • s streaming • t \
         tutorial • Esc back";
        "";
      ]
    in
    String.concat "\n" header_lines ^ render_pager s ~focus ~size

  let append_line s msg =
    Pager.append_lines s.pager [msg] ;
    s

  let toggle_streaming s =
    match s.file with
    | Some _ -> s
    | None ->
        if s.streaming then (
          Pager.stop_streaming s.pager ;
          {s with streaming = false})
        else (
          Pager.start_streaming s.pager ;
          {s with streaming = true})

  let win_from size = max 3 (size.LTerm_geom.rows - 4)

  let go_back s =
    let s = close_file_if_any s in
    {s with next_page = Some Demo_shared.Demo_config.launcher_page_name}

  let handle_key s key_str ~size =
    let win = win_from size in
    let pager_input_mode =
      match s.pager.Pager.input_mode with `Search_edit -> true | _ -> false
    in
    match Miaou.Core.Keys.of_string key_str with
    | Some (Miaou.Core.Keys.Char "Esc") | Some (Miaou.Core.Keys.Char "Escape")
      ->
        if pager_input_mode then
          let pager, _ = Pager.handle_key ~win s.pager ~key:key_str in
          {s with pager}
        else go_back s
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
    let win = win_from size in
    let pager, _ = Pager.handle_key ~win s.pager ~key in
    {s with pager}

  let next_page s =
    match s.next_page with
    | Some _ ->
        let s = close_file_if_any s in
        s.next_page
    | None -> None

  let keymap (_ : state) = []

  let handled_keys () = []

  let back s = go_back s

  let has_modal s =
    match s.pager.Pager.input_mode with `Search_edit -> true | _ -> false
end

include Demo_shared.Demo_page.Make (Inner)
