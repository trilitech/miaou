(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)
[@@@warning "-32-34-37-69"]
[@@@coverage off]

module Logger_capability = Miaou_interfaces.Logger_capability
open Miaou_core.Tui_page
module Capture = Miaou_core.Tui_capture
module Khs = Miaou_internals.Key_handler_stack
module Modal_manager = Miaou_core.Modal_manager
module Narrow_modal = Miaou_core.Narrow_modal
module Quit_flag = Miaou_core.Quit_flag
module Help_hint = Miaou_core.Help_hint

(* Persistent session flags *)
let narrow_warned = ref false

module LT = LTerm

type t = private T

let available = true

let size () = (Obj.magic 0 : t)

let clear () =
  print_string "\027[2J\027[H" ;
  Stdlib.flush stdout

(* top-level reader removed; a local reader is used inside run_with_page to allow
  buffered read of escape sequences specific to the interactive driver. *)
(* Other imports and module definitions *)

let run (initial_page : (module PAGE_SIG)) : [`Quit | `SwitchTo of string] =
  let run_with_page (module Page : PAGE_SIG) =
    (* Ensure widgets render with terminal-friendly glyphs when using the lambda-term backend. *)
    Miaou_widgets_display.Widgets.set_backend `Terminal ;
    let fd = Unix.descr_of_in_channel stdin in

    if not (try Unix.isatty fd with _ -> false) then
      failwith "interactive TUI requires a terminal" ;
    let orig = try Some (Unix.tcgetattr fd) with _ -> None in
    let enter_raw () =
      match orig with
      | None -> ()
      | Some o ->
          let raw =
            {
              o with
              Unix.c_icanon = false;
              Unix.c_echo = false;
              Unix.c_vmin = 1;
              Unix.c_vtime = 0;
            }
          in
          Unix.tcsetattr fd Unix.TCSANOW raw
    in
    let restore () =
      match orig with None -> () | Some o -> Unix.tcsetattr fd Unix.TCSANOW o
    in
    (* Ensure terminal is restored and mouse tracking disabled on any exit path. *)
    let cleanup_done = ref false in
    let cleanup () =
      if not !cleanup_done then (
        (* Disable xterm mouse tracking modes. We only enable 1000/1006 here,
           but also disable 1002/1003/1005/1015 defensively in case they were
           toggled by an earlier run or a different program. *)
        (try
           print_string
             "\027[?1000l\027[?1002l\027[?1003l\027[?1005l\027[?1006l\027[?1015l" ;
           Stdlib.flush stdout
         with _ -> ()) ;
        (* Restore original termios if available. *)
        (try restore () with _ -> ()) ;
        cleanup_done := true)
    in
    (* Register process-exit cleanup and trap a few common termination signals. *)
    let () = at_exit cleanup in
    let install_signal_handlers () =
      let set sigv =
        try
          Sys.set_signal
            sigv
            (Sys.Signal_handle
               (fun _sig ->
                 (* Best-effort cleanup then terminate. *)
                 (try cleanup () with _ -> ()) ;
                 (* Exit with a conventional non-zero status. *)
                 exit 130))
        with _ -> ()
      in
      (* Linux: INT (C-c), TERM, HUP, QUIT; ignore failures on platforms without some signals. *)
      set Sys.sigint ;
      set Sys.sigterm ;
      (try set Sys.sighup with _ -> ()) ;
      try set Sys.sigquit with _ -> ()
    in
    install_signal_handlers () ;
    (* Track terminal resizes via SIGWINCH to force immediate refresh. *)
    let resize_pending = Atomic.make false in
    (try
       (* Linux SIGWINCH is 28; Sys doesn't expose a constant on all versions. *)
       let sigwinch = 28 in
       Sys.set_signal
         sigwinch
         (Sys.Signal_handle (fun _ -> Atomic.set resize_pending true))
     with _ -> ()) ;

    (* Cache the last rendered frame to avoid unnecessary redraws (reduces flicker). *)
    let last_out_ref = ref "" in
    (* Track last known terminal size and detect changes by polling on each
    render tick. This avoids depending on SIGWINCH being available at
    compile-time across different platforms. *)
    let last_size = ref {LTerm_geom.rows = 24; cols = 80} in
    (* Portable size detection used by render and key handlers.
       First, try lambda-term directly (in-process, no subprocess TTY issues).
       Then fall back to external tools. Avoid touching stdin to not interfere
       with input handling. *)
    let detect_size () =
      (* Highest-priority: ask lambda-term for the current terminal size. This
         works even when subprocess stdio are pipes (e.g., when capturing output),
         where `stty` would fail. *)
      let try_lterm () =
        try
          (* Obtain the terminal handle and ask lambda-term for its size. *)
          let term = Lwt_main.run (Lazy.force LTerm.stdout) in
          let sz = LTerm.size term in
          Some {LTerm_geom.rows = sz.LTerm_geom.rows; cols = sz.LTerm_geom.cols}
        with _ -> None
      in
      (* Highest-priority: allow explicit overrides for debugging or constrained environments. *)
      let try_env_override () =
        match
          (Sys.getenv_opt "MIAOU_TUI_ROWS", Sys.getenv_opt "MIAOU_TUI_COLS")
        with
        | Some r, Some c -> (
            try
              let rows = int_of_string (String.trim r) in
              let cols = int_of_string (String.trim c) in
              Some {LTerm_geom.rows; cols}
            with _ -> None)
        | _ -> None
      in
      let try_stty () =
        try
          let sys = Miaou_interfaces.System.require () in
          (* Prefer querying the actual stdout fd which is our drawing surface. *)
          let try_stdout_fd () =
            match
              sys.run_command
                ~argv:["stty"; "size"; "-F"; "/proc/self/fd/1"]
                ~cwd:None
            with
            | Ok {stdout; _} -> (
                let trimmed = String.trim stdout in
                match String.split_on_char ' ' trimmed with
                | [r; c] ->
                    let rows = int_of_string r in
                    let cols = int_of_string c in
                    Some {LTerm_geom.rows; cols}
                | _ -> None)
            | Error _ -> None
          in
          match try_stdout_fd () with
          | Some s -> Some s
          | None -> (
              (* Prefer stty size on /dev/tty when available. *)
              match
                sys.run_command
                  ~argv:["stty"; "size"; "-F"; "/dev/tty"]
                  ~cwd:None
              with
              | Ok {stdout; _} -> (
                  let trimmed = String.trim stdout in
                  match String.split_on_char ' ' trimmed with
                  | [r; c] ->
                      let rows = int_of_string r in
                      let cols = int_of_string c in
                      Some {LTerm_geom.rows; cols}
                  | _ -> None)
              | Error _ -> (
                  match sys.run_command ~argv:["stty"; "size"] ~cwd:None with
                  | Ok {stdout; _} -> (
                      let trimmed = String.trim stdout in
                      match String.split_on_char ' ' trimmed with
                      | [r; c] ->
                          let rows = int_of_string r in
                          let cols = int_of_string c in
                          Some {LTerm_geom.rows; cols}
                      | _ -> None)
                  | Error _ -> None))
        with _ -> None
      in
      let try_tput () =
        try
          let sys = Miaou_interfaces.System.require () in
          match sys.run_command ~argv:["tput"; "lines"] ~cwd:None with
          | Ok {stdout = l; _} -> (
              match sys.run_command ~argv:["tput"; "cols"] ~cwd:None with
              | Ok {stdout = c; _} ->
                  let rows = int_of_string (String.trim l) in
                  let cols = int_of_string (String.trim c) in
                  Some {LTerm_geom.rows; cols}
              | Error _ -> None)
          | Error _ -> None
        with _ -> None
      in
      let try_stty_a () =
        let parse_rows_cols s =
          let open Str in
          let rgx1 = regexp ".*rows \\([0-9]+\\); columns \\([0-9]+\\).*" in
          let rgx2 = regexp ".*columns \\([0-9]+\\); rows \\([0-9]+\\).*" in
          if string_match rgx1 s 0 then
            let rows = int_of_string (matched_group 1 s) in
            let cols = int_of_string (matched_group 2 s) in
            Some {LTerm_geom.rows; cols}
          else if string_match rgx2 s 0 then
            let cols = int_of_string (matched_group 1 s) in
            let rows = int_of_string (matched_group 2 s) in
            Some {LTerm_geom.rows; cols}
          else None
        in
        try
          let sys = Miaou_interfaces.System.require () in
          match
            sys.run_command ~argv:["stty"; "-a"; "-F"; "/dev/tty"] ~cwd:None
          with
          | Ok {stdout; _} -> (
              match parse_rows_cols stdout with
              | Some s -> Some s
              | None -> (
                  match sys.run_command ~argv:["stty"; "-a"] ~cwd:None with
                  | Ok {stdout; _} -> parse_rows_cols stdout
                  | Error _ -> None))
          | Error _ -> None
        with _ -> None
      in
      let try_env () =
        match (Sys.getenv_opt "LINES", Sys.getenv_opt "COLUMNS") with
        | Some r, Some c -> (
            try
              let rows = int_of_string (String.trim r) in
              let cols = int_of_string (String.trim c) in
              Some {LTerm_geom.rows; cols}
            with _ -> None)
        | _ -> None
      in
      match try_lterm () with
      | Some s -> s
      | None -> (
          match try_env_override () with
          | Some s -> s
          | None -> (
              match try_stty () with
              | Some s -> s
              | None -> (
                  match try_tput () with
                  | Some s -> s
                  | None -> (
                      match try_stty_a () with
                      | Some s -> s
                      | None -> (
                          match try_env () with
                          | Some s -> s
                          | None -> !last_size)))))
    in
    let footer_ref : string option ref = ref None in
    let clear_and_render st key_stack =
      (* Log driver render tick using the Miaou TUI logger if available. *)
      (match Logger_capability.get () with
      | Some logger -> logger.logf Debug "DRIVER: clear_and_render tick"
      | None -> ()) ;
      (* Build footer from key handler stack top frame bindings if available. *)
      let size = detect_size () in
      (* Persistent narrow banner: show a small header warning on every render while cols < 80. *)
      let header_lines =
        if size.cols < 80 then
          [
            Miaou_widgets_display.Widgets.warning_banner
              ~cols:size.cols
              (Printf.sprintf
                 "Narrow terminal: %d cols (< 80). Some UI may be truncated."
                 size.cols);
          ]
        else []
      in
      (* One-time narrow terminal warning (only once per session). *)
      (* Trigger warning when starting narrow or when crossing from >=80 to <80. *)
      let prev_cols = !last_size.LTerm_geom.cols in
      if
        (size.cols < 80 && not !narrow_warned)
        || (size.cols < 80 && prev_cols >= 80 && not !narrow_warned)
      then (
        (* Structured log for width crossing / initial narrow state *)
        (match Logger_capability.get () with
        | Some logger ->
            logger.logf
              Warning
              (Printf.sprintf
                 "WIDTH_CROSSING: prev=%d new=%d (showing narrow modal)"
                 prev_cols
                 size.cols)
        | None -> ()) ;
        narrow_warned := true ;
        Modal_manager.push
          (module Narrow_modal.Page)
          ~init:(Narrow_modal.Page.init ())
          ~ui:
            {
              title = "Narrow terminal";
              left = Some 2;
              max_width = None;
              dim_background = true;
            }
          ~commit_on:[]
          ~cancel_on:[]
          ~on_close:(fun (_ : Narrow_modal.Page.state) _ -> ()) ;
        (* Mark the next key as consumed so Enter/Esc won't propagate. *)
        Modal_manager.set_consume_next_key () ;
        (* Auto-dismiss after 5s. We only close the modal if it's still the
           same top modal title to avoid racing with other modals. *)
        let my_title = "Narrow terminal" in
        ignore
          (Thread.create
             (fun () ->
               Thread.delay 5.0 ;
               match Modal_manager.top_title_opt () with
               | Some t when t = my_title -> Modal_manager.close_top `Cancel
               | _ -> ())
             ())) ;
      (* If terminal geometry changed since last render, force a redraw and
      update the modal snapshot size so overlays render correctly. *)
      (* Log size changes for diagnostics and force a redraw when geometry changes. *)
      if
        size.LTerm_geom.rows <> !last_size.LTerm_geom.rows
        || size.LTerm_geom.cols <> !last_size.LTerm_geom.cols
      then last_out_ref := "" ;
      (* Publish current size to modal machinery for overlays. *)
      Modal_manager.set_current_size size.LTerm_geom.rows size.LTerm_geom.cols ;
      let body = Page.view st ~focus:true ~size in
      let title_opt =
        match String.index_opt body '\n' with
        | None -> None
        | Some idx -> Some (String.sub body 0 idx)
      in
      let main_out =
        match title_opt with
        | Some t when String.length t > 0 ->
            let wrapped_footer =
              Miaou_widgets_display.Widgets.footer_hints_wrapped_capped
                ~cols:size.cols
                ~max_lines:3
                (Khs.top_bindings key_stack)
            in
            Miaou_widgets_display.Widgets.render_frame
              ~title:t
              ~header:header_lines
              ~cols:size.cols
              ~body:
                (String.sub
                   body
                   (min (String.length body) (String.length t + 1))
                   (max 0 (String.length body - (String.length t + 1))))
              ~footer:wrapped_footer
              ()
        | _ ->
            let wrapped_footer =
              Miaou_widgets_display.Widgets.footer_hints_wrapped_capped
                ~cols:size.cols
                ~max_lines:3
                (Khs.top_bindings key_stack)
            in
            let hdr =
              match header_lines with
              | [] -> ""
              | lst -> String.concat "\n" lst ^ "\n"
            in
            hdr ^ body ^ "\n" ^ wrapped_footer
      in
      let out =
        match
          Miaou_internals.Modal_renderer.render_overlay
            ~cols:(Some size.cols)
            ~base:main_out
            ~rows:size.rows
            ()
        with
        | Some s -> s
        | None -> main_out
      in
      (* Trim output to the current terminal rows so height resizing is respected.
       Keep the top of the output and the final footer line when possible. *)
      let max_rows = size.LTerm_geom.rows in
      let lines = String.split_on_char '\n' out in
      let out_trimmed =
        if List.length lines <= max_rows then out
        else
          let head_count = max 1 (max_rows - 1) in
          let rec take n lst =
            if n <= 0 then []
            else match lst with [] -> [] | x :: xs -> x :: take (n - 1) xs
          in
          let last_line = List.nth lines (List.length lines - 1) in
          let head = take head_count lines in
          String.concat "\n" (head @ [last_line])
      in
      (* Write only when output changed; keeps the terminal stable and avoids flicker. *)
      Capture.record_frame
        ~rows:size.LTerm_geom.rows
        ~cols:size.LTerm_geom.cols
        out_trimmed ;
      let full_out = out_trimmed ^ "\n" in
      if full_out <> !last_out_ref then (
        (* Use full clear (ESC[2J]) then home (ESC[H]) to keep previous behavior. *)
        print_string ("\027[2J\027[H" ^ full_out) ;
        Stdlib.flush stdout ;
        last_out_ref := full_out)
      else () ;
      (* Update last_size at end of render tick so next iteration compares
      against the previously displayed geometry. *)
      last_size := size
    in

    (* Pager notify mechanism: we avoid calling clear_and_render directly
     from background threads. Instead background appenders set an atomic
     flag which the main loop polls; when seen, the main loop performs the
     render from the main thread. This prevents unsafe cross-thread UI
     calls while keeping responsiveness. *)
    (* Pager notify mechanism: use an atomic timestamp and debounce so bursts of
    background notifications are coalesced. The notifier will set the
    timestamp to Unix.gettimeofday(); the main loop will only emit a
    Refresh when now - last_notify >= pager_notify_debounce_s. *)
    let pager_last_notify = Atomic.make 0.0 in
    let pager_notify_debounce_s = 0.08 in

    let notify_render_from_pager_flag () =
      Atomic.set pager_last_notify (Unix.gettimeofday ())
    in

    (* Buffered reader using Unix.read: keep a pending string of bytes read from
       the fd. Block until at least one byte is available, then for ESC-starting
       sequences poll briefly to gather additional bytes so common CSI arrow
       sequences (ESC '[' A/B/C/D) are returned as a single token. *)
    (* We need to expose refs to the current page state and key_stack so the
     pager notifier can call clear_and_render with a consistent snapshot. *)
    let current_state_ref : Page.state option ref = ref None in
    (* key stack is always present (use empty as initial value) so notifier
      can dereference it without option handling. *)
    let current_key_stack_ref : Khs.t ref = ref Khs.empty in
    (* Handle for the page frame we push into the key handler stack, so we can replace it each loop. *)
    let page_frame_handle : Khs.handle option ref = ref None in
    (* Expose pager_last_notify to the local scope so read_key_blocking can poll it. *)
    let pager_last_notify = pager_last_notify in
    let pending = ref "" in
    (* Helper: detect whether the transient narrow modal is currently active. *)
    let is_narrow_modal_active () =
      match Modal_manager.top_title_opt () with
      | Some t when t = "Narrow terminal" -> true
      | _ -> false
    in

    let refill timeout =
      try
        let r, _, _ = Unix.select [fd] [] [] timeout in
        if r = [] then 0
        else
          let b = Bytes.create 256 in
          try
            let n = Unix.read fd b 0 256 in
            if n <= 0 then 0
            else (
              pending := !pending ^ Bytes.sub_string b 0 n ;
              n)
          with Unix.Unix_error (Unix.EINTR, _, _) -> 0
      with Unix.Unix_error (Unix.EINTR, _, _) -> 0
    in

    (* Read next key or emit a periodic refresh tick when idle. *)
    let read_key_blocking () =
      try
        (* Prioritize a pending resize event to redraw immediately. *)
        if Atomic.get resize_pending then (
          Atomic.set resize_pending false ;
          `Refresh)
        else
          (* If a background append requested a render, service it as a refresh
           tick but only when the last notify timestamp is older than the
           debounce window. This coalesces bursts from background threads. *)
          let last = Atomic.get pager_last_notify in
          let now = Unix.gettimeofday () in
          if last > 0. && now -. last >= pager_notify_debounce_s then (
            Atomic.set pager_last_notify 0.0 ;
            `Refresh)
          else (
            (* Ensure at least one byte: wait a short time; if none, emit a refresh tick to drive pages. *)
            if String.length !pending = 0 then ignore (refill 0.15) ;
            if String.length !pending = 0 then
              (* Inject a synthetic refresh marker into the pending buffer to signal an idle tick. *)
              pending := "\000" ^ !pending ;
            if String.length !pending = 0 then raise End_of_file ;
            let first = String.get !pending 0 in
            (* If not ESC, consume single byte and return it. *)
            if Char.code first <> 27 then (
              pending :=
                if String.length !pending > 1 then
                  String.sub !pending 1 (String.length !pending - 1)
                else "" ;
              if first = '\000' then `Refresh
              else if first = '\n' || first = '\r' then `Enter
              else if Char.code first = 9 then `NextPage
              else if Char.code first = 127 then `Other "Backspace"
              else
                let code = Char.code first in
                if code >= 1 && code <= 26 then
                  let letter = Char.chr (code + 96) in
                  `Other ("C-" ^ String.make 1 letter)
                else `Other (String.make 1 first))
            else (
              (* first == ESC (27) *)
              (* Gather a short window for sequence completion. *)
              for _ = 1 to 5 do
                if String.length !pending >= 3 then () else ignore (refill 0.02)
              done ;
              let len = String.length !pending in
              if len = 1 then (
                pending := "" ;
                `Other "Esc")
              else if len >= 3 && String.get !pending 1 = '[' then (
                if
                  (* Handle SGR mouse: ESC [ < btn;col;row (M|m) *)
                  len >= 6 && String.get !pending 2 = '<'
                then (
                  (* Read until trailing 'M' or 'm' arrives. *)
                  let rec ensure_full_mouse timeout =
                    if timeout <= 0 then ()
                    else
                      let l = String.length !pending in
                      if l > 0 then (
                        let last = String.get !pending (l - 1) in
                        if last = 'M' || last = 'm' then ()
                        else ignore (refill 0.02) ;
                        ensure_full_mouse (timeout - 1))
                      else (
                        ignore (refill 0.02) ;
                        ensure_full_mouse (timeout - 1))
                  in
                  ensure_full_mouse 20 ;
                  let seq = !pending in
                  (* Find terminating M/m *)
                  let l = String.length seq in
                  let term_idx =
                    let rec find i =
                      if i >= l then l - 1
                      else
                        let c = String.get seq i in
                        if c = 'M' || c = 'm' then i else find (i + 1)
                    in
                    find 0
                  in
                  let chunk = String.sub seq 0 (min (term_idx + 1) l) in
                  (* Consume chunk from pending *)
                  pending :=
                    if String.length seq > String.length chunk then
                      String.sub
                        seq
                        (String.length chunk)
                        (String.length seq - String.length chunk)
                    else "" ;
                  (* Parse ESC [ < btn;col;row (M|m) *)
                  let parsed =
                    try
                      if String.length chunk < 6 then None
                      else if String.get chunk 0 <> '\027' then None
                      else if String.get chunk 1 <> '[' then None
                      else if String.get chunk 2 <> '<' then None
                      else
                        let body =
                          String.sub chunk 3 (String.length chunk - 4)
                        in
                        (* body like: "b;c;rM" or "b;c;rm" *)
                        let lastc =
                          String.get chunk (String.length chunk - 1)
                        in
                        let parts = String.split_on_char ';' body in
                        match parts with
                        | [b; c; r] -> (
                            let btn = int_of_string_opt b in
                            let col = int_of_string_opt c in
                            let row =
                              let r' = String.sub r 0 (String.length r - 0) in
                              int_of_string_opt (String.trim r')
                            in
                            match (btn, col, row) with
                            | Some _btn, Some col, Some row ->
                                Some (row, col, lastc)
                            | _ -> None)
                        | _ -> None
                    with _ -> None
                  in
                  match parsed with
                  | Some (row, col, lastc) ->
                      (match Logger_capability.get () with
                      | Some logger ->
                          logger.logf
                            Debug
                            (Printf.sprintf "MOUSE: row=%d col=%d" row col)
                      | None -> ()) ;
                      (* Emit click only on button release to avoid flooding on motion. *)
                      if lastc = 'm' then
                        `Other (Printf.sprintf "Mouse:%d:%d" row col)
                      else `Other "MouseMove"
                  | None -> `Other "Esc")
                else
                  let code = String.get !pending 2 in
                  (* consume ESC,[,code *)
                  pending :=
                    if len > 3 then String.sub !pending 3 (len - 3) else "" ;
                  match code with
                  | 'M' ->
                      (* X10 mouse tracking: ESC [ M b x y, with x,y,btn encoded +32 *)
                      let rec ensure_bytes n timeout =
                        if timeout <= 0 then false
                        else if String.length !pending >= n then true
                        else (
                          ignore (refill 0.02) ;
                          ensure_bytes n (timeout - 1))
                      in
                      if ensure_bytes 3 20 then (
                        let _b = String.get !pending 0 in
                        let x = String.get !pending 1 in
                        let y = String.get !pending 2 in
                        pending :=
                          if String.length !pending > 3 then
                            String.sub !pending 3 (String.length !pending - 3)
                          else "" ;
                        let col = max 1 (Char.code x - 32) in
                        let row = max 1 (Char.code y - 32) in
                        (match Logger_capability.get () with
                        | Some logger ->
                            logger.logf
                              Debug
                              (Printf.sprintf
                                 "MOUSE_X10: row=%d col=%d"
                                 row
                                 col)
                        | None -> ()) ;
                        `Other (Printf.sprintf "Mouse:%d:%d" row col))
                      else `Other "Esc"
                  | 'A' -> `Up
                  | 'B' -> `Down
                  | 'C' -> `Right
                  | 'D' -> `Left
                  | '3' ->
                      (* Common Delete sequence: ESC [ 3 ~ *)
                      if
                        String.length !pending > 0
                        && String.get !pending 0 = '~'
                      then (
                        pending :=
                          if String.length !pending > 1 then
                            String.sub !pending 1 (String.length !pending - 1)
                          else "" ;
                        `Other "Delete")
                      else `Other "3"
                  | c -> `Other (String.make 1 c))
              else if len >= 2 && String.get !pending 1 = 'O' then (
                let code = if len >= 3 then String.get !pending 2 else '\000' in
                pending :=
                  if len > 2 then String.sub !pending 2 (len - 2) else "" ;
                match code with
                | 'A' -> `Up
                | 'B' -> `Down
                | 'C' -> `Right
                | 'D' -> `Left
                | '\000' -> `Other "Esc"
                | c -> `Other (String.make 1 c))
              else if
                (* ESC followed by other single byte: consume ESC and next byte if present *)
                len >= 2
              then (
                let second = String.get !pending 1 in
                pending :=
                  if len > 2 then String.sub !pending 2 (len - 2) else "" ;
                `Other (String.make 1 second))
              else (
                pending := "" ;
                `Other "Esc")))
      with End_of_file -> `Quit
    in

    let handle_key_like st key key_stack =
      (* Compute current size for handlers so pages can react to geometry during key handling. *)
      let size = detect_size () in
      Modal_manager.set_current_size size.LTerm_geom.rows size.LTerm_geom.cols ;
      if Modal_manager.has_active () then (
        Modal_manager.handle_key key ;
        st)
      else if Page.has_modal st then (
        let st' = Page.handle_modal_key st key ~size in
        clear_and_render st' key_stack ;
        st')
      else Page.handle_key st key ~size
    in

    (* Key handler stack (pure) integration: thread alongside page state. *)
    (* Prepare key handler stack: push a frame for the page keymap once per page.
       We translate (key, state->state, desc) into a side-effect that records
       a pending state transformation applied after dispatch. *)
    let pending_update : (Page.state -> Page.state) option ref = ref None in
    let rec loop st key_stack =
      (* Refresh refs for pager notifier to see current state/key_stack snapshots. *)
      current_state_ref := Some st ;
      current_key_stack_ref := key_stack ;
      (* Rebuild page keymap frame each iteration so dynamic state (e.g. search mode) can adjust bindings. *)
      let key_stack =
        let merged = Page.keymap st in
        match !page_frame_handle with
        | Some h ->
            let ks = Khs.pop key_stack h in
            let bindings =
              List.map
                (fun (k, fn, desc) ->
                  (k, (fun () -> pending_update := Some fn), desc))
                merged
            in
            let ks', h' = Khs.push ks bindings in
            page_frame_handle := Some h' ;
            ks'
        | None -> key_stack
      in
      (* Update footer from top frame after rebuild. *)
      let () =
        let pairs = Khs.top_bindings key_stack in
        let pairs = if pairs = [] then [("q", "Quit")] else pairs in
        footer_ref := Some (Miaou_widgets_display.Widgets.footer_hints pairs)
      in
      match read_key_blocking () with
      | `Quit ->
          Printf.eprintf
            "lambda_term_driver: read_key_blocking -> Quit (ignoring)\n" ;
          Stdlib.flush stderr ;
          clear_and_render st key_stack ;
          loop st key_stack
      | `Refresh ->
          (* Periodic idle tick: let the page run its service cycle (for throttled refresh/background jobs). *)
          if Quit_flag.is_pending () then Quit_flag.clear_pending () ;
          let st' = Page.service_cycle st 0 in
          clear_and_render st' key_stack ;
          loop st' key_stack
      | `Enter -> (
          if Quit_flag.is_pending () then Quit_flag.clear_pending () ;
          if Modal_manager.has_active () then
            if
              (* If the narrow modal is active, close it on any key as advertised. *)
              is_narrow_modal_active ()
            then (
              Modal_manager.close_top `Cancel ;
              clear_and_render st key_stack ;
              loop st key_stack)
            else (
              (* Forward to modal; if it just closed and the page requested navigation, switch now. *)
              Modal_manager.handle_key "Enter" ;
              (* If the modal requested the key be consumed, stop here and do not
               propagate Enter to the underlying page. *)
              if Modal_manager.take_consume_next_key () then (
                clear_and_render st key_stack ;
                loop st key_stack)
              else if not (Modal_manager.has_active ()) then (
                match Page.next_page st with
                | Some page -> `SwitchTo page
                | None ->
                    clear_and_render st key_stack ;
                    loop st key_stack)
              else (
                clear_and_render st key_stack ;
                loop st key_stack))
          else if Page.has_modal st then (
            let size = detect_size () in
            Modal_manager.set_current_size
              size.LTerm_geom.rows
              size.LTerm_geom.cols ;
            let st' = Page.handle_modal_key st "Enter" ~size in
            match Page.next_page st' with
            | Some page -> `SwitchTo page
            | None ->
                clear_and_render st' key_stack ;
                loop st' key_stack)
          else
            (* Non-modal Enter: perform page.enter, then switch immediately if next_page set. *)
            match Page.next_page st with
            | Some page -> `SwitchTo page
            | None -> (
                let st' = Page.enter st in
                match Page.next_page st' with
                | Some page -> `SwitchTo page
                | None ->
                    clear_and_render st' key_stack ;
                    loop st' key_stack))
      | (`Up | `Down | `Left | `Right | `NextPage | `PrevPage) as k -> (
          let key =
            match k with
            | `Up -> "Up"
            | `Down -> "Down"
            | `Left -> "Left"
            | `Right -> "Right"
            | `NextPage -> "Tab"
            | `PrevPage -> "Shift-Tab"
            | _ -> ""
          in
          if key <> "" then (
            if Quit_flag.is_pending () then Quit_flag.clear_pending () ;
            let st' = handle_key_like st key key_stack in
            match Page.next_page st' with
            | Some page -> `SwitchTo page
            | None ->
                clear_and_render st' key_stack ;
                loop st' key_stack)
          else if Modal_manager.has_active () then
            if is_narrow_modal_active () then (
              Modal_manager.close_top `Cancel ;
              clear_and_render st key_stack ;
              loop st key_stack)
            else (
              Modal_manager.handle_key key ;
              clear_and_render st key_stack ;
              loop st key_stack)
          else if Page.has_modal st then (
            let size = detect_size () in
            Modal_manager.set_current_size
              size.LTerm_geom.rows
              size.LTerm_geom.cols ;
            let st' = Page.handle_modal_key st key ~size in
            clear_and_render st' key_stack ;
            loop st' key_stack)
          else
            (* First attempt stack-based dispatch. *)
            let consumed, key_stack' = Khs.dispatch key_stack key in
            if consumed then (
              let st' =
                match !pending_update with
                | Some f ->
                    let s' = f st in
                    pending_update := None ;
                    s'
                | None -> st
              in
              match Page.next_page st' with
              | Some page -> `SwitchTo page
              | None ->
                  clear_and_render st' key_stack ;
                  loop st' key_stack')
            else
              let st' = handle_key_like st key key_stack in
              match Page.next_page st' with
              | Some page -> `SwitchTo page
              | None ->
                  clear_and_render st' key_stack ;
                  loop st' key_stack')
      | `Other key ->
          if key = "?" then (
            (* Build help text with optional contextual hint (markdown),
          shown above the key bindings. Title is "hints" with a subtitle
          for the bindings. *)
            let size = detect_size () in
            let cols = size.LTerm_geom.cols in
            (* Use a conservative content width and align modal max width to it to
          prevent container re-wrapping (breaks words). *)
            let content_width =
              let cw = max 16 (cols - 20) in
              min cw 72
            in
            let all = Khs.all_bindings key_stack in
            let dedup = Hashtbl.create 97 in
            List.iter
              (fun (k, h) ->
                if not (Hashtbl.mem dedup k) then Hashtbl.add dedup k h)
              all ;
            let entries =
              Hashtbl.fold (fun k h acc -> (k, h) :: acc) dedup []
            in
            let entries =
              List.sort (fun (a, _) (b, _) -> String.compare a b) entries
            in
            let key_lines =
              List.map (fun (k, h) -> Printf.sprintf "%-12s %s" k h) entries
            in
            let contextual = Help_hint.get_active () in
            let hint_block =
              match contextual with
              | None -> None
              | Some {short; long} ->
                  let pick =
                    match (long, short) with
                    | Some l, Some s -> if cols >= 100 then l else s
                    | Some l, None -> l
                    | None, Some s -> s
                    | None, None -> ""
                  in
                  let pick = String.trim pick in
                  if pick = "" then None
                  else
                    let md =
                      Miaou_internals.Modal_utils.markdown_to_ansi pick
                    in
                    let wrapped =
                      Miaou_internals.Modal_utils.wrap_content_to_width_words
                        md
                        content_width
                    in
                    Some wrapped
            in
            let body =
              match hint_block with
              | None ->
                  let header =
                    Miaou_widgets_display.Widgets.bold
                      (Miaou_widgets_display.Widgets.fg 81 "Key Bindings")
                  in
                  let keys = String.concat "\n" key_lines in
                  String.concat "\n" [header; keys]
              | Some hb ->
                  let sep =
                    Miaou_widgets_display.Widgets.fg
                      238
                      (Miaou_widgets_display.Widgets.hr
                         ~width:(min content_width (cols - 6))
                         ())
                  in
                  let header =
                    Miaou_widgets_display.Widgets.bold
                      (Miaou_widgets_display.Widgets.fg 81 "Key Bindings")
                  in
                  let keys = String.concat "\n" key_lines in
                  String.concat "\n" [hb; sep; header; keys]
            in
            let module Help_modal = struct
              module Page : PAGE_SIG = struct
                type state = unit

                type msg = unit

                let handle_modal_key s _ ~size:_ = s

                let handle_key s _ ~size:_ = s

                let update s _ = s

                let move s _ = s

                let refresh s = s

                let enter s = s

                let service_select s _ = s

                let service_cycle s _ = s

                let back s = s

                let next_page _ = None

                let has_modal _ = false

                let init () = ()

                let view _ ~focus:_ ~size:_ = body

                let keymap (_ : state) = []
              end
            end in
            Modal_manager.push_default
              (module Help_modal.Page)
              ~init:(Help_modal.Page.init ())
              ~ui:
                {
                  title = "hints";
                  left = None;
                  max_width = Some (content_width + 4);
                  dim_background = true;
                }
              ~on_close:(fun (_ : Help_modal.Page.state) _ -> ()) ;
            clear_and_render st key_stack ;
            loop st key_stack)
          else if key = "Esc" || key = "Escape" then
            if Modal_manager.has_active () || Page.has_modal st then (
              (* Close modal if any; if page requested navigation, switch now. *)
              Modal_manager.handle_key "Esc" ;
              if Modal_manager.take_consume_next_key () then (
                clear_and_render st key_stack ;
                loop st key_stack)
              else if not (Modal_manager.has_active ()) then (
                match Page.next_page st with
                | Some page -> `SwitchTo page
                | None ->
                    clear_and_render st key_stack ;
                    loop st key_stack)
              else (
                clear_and_render st key_stack ;
                loop st key_stack))
            else
              (* Let the current page override Esc/Escape. If it sets next_page,
                 navigate there; else fall back to default back behavior. *)
              let size = detect_size () in
              let st' = Page.handle_key st key ~size in
              match Page.next_page st' with
              | Some page -> `SwitchTo page
              | None -> `SwitchTo "__BACK__"
          else if
            (* If a modal is active, route all keys to the modal first and do not
               propagate them to the underlying page or key handler stack. This
               prevents page shortcuts (e.g. 'd' for delete) from triggering while
               typing in modal inputs. *)
            Modal_manager.has_active ()
          then
            if is_narrow_modal_active () then (
              Modal_manager.close_top `Cancel ;
              clear_and_render st key_stack ;
              loop st key_stack)
            else (
              Modal_manager.handle_key key ;
              clear_and_render st key_stack ;
              loop st key_stack)
          else (
            if Quit_flag.is_pending () then Quit_flag.clear_pending () ;
            (* Stack dispatch first. *)
            let consumed, key_stack' = Khs.dispatch key_stack key in
            if consumed then (
              let st' =
                match !pending_update with
                | Some f ->
                    let s' = f st in
                    pending_update := None ;
                    s'
                | None -> st
              in
              match Page.next_page st' with
              | Some page -> `SwitchTo page
              | None ->
                  clear_and_render st' key_stack ;
                  loop st' key_stack')
            else
              let st' = handle_key_like st key key_stack in
              match Page.next_page st' with
              | Some page -> `SwitchTo page
              | None ->
                  clear_and_render st' key_stack ;
                  loop st' key_stack')
    in

    enter_raw () ;
    (* Enable xterm mouse tracking: 1000 button events, 1006 SGR extended. *)
    (try
       print_string "\027[?1000h\027[?1006h" ;
       Stdlib.flush stdout
     with _ -> ()) ;
    (* Log initial terminal size on startup *)
    let initial_size = detect_size () in
    (match Logger_capability.get () with
    | Some logger ->
        logger.logf
          Info
          (Printf.sprintf
             "STARTUP: terminal size %dx%d (cols=%d)"
             initial_size.LTerm_geom.cols
             initial_size.LTerm_geom.rows
             initial_size.LTerm_geom.cols)
    | None -> ()) ;
    last_size := initial_size ;
    let st0 = Page.init () in
    (* Initialize refs for pager notifier and register hook. *)
    current_state_ref := Some st0 ;
    (* Initialize stack after we have initial state. *)
    let init_stack =
      let bindings =
        List.map
          (fun (k, fn, desc) ->
            (k, (fun () -> pending_update := Some fn), desc))
          (Page.keymap st0)
      in
      let key_stack, handle = Khs.push Khs.empty bindings in
      page_frame_handle := Some handle ;
      key_stack
    in
    current_key_stack_ref := init_stack ;
    (* Register pager notify callback so appenders can request renders. *)
    (try
       Miaou_widgets_display.Pager_widget.set_notify_render
         (Some notify_render_from_pager_flag)
     with _ -> ()) ;
    (* Footer cache updated each loop; initialize ref *)
    footer_ref := None ;
    clear_and_render st0 init_stack ;
    let outcome = loop st0 init_stack in
    (* Pop page frame explicitly (semantic symmetry) *)
    (match !page_frame_handle with
    | Some h -> ignore (Khs.pop init_stack h)
    | None -> ()) ;
    (* Unified cleanup on exit. *)
    cleanup () ;
    outcome
  in

  match initial_page with
  | (module Page) -> run_with_page (module Page : PAGE_SIG)
