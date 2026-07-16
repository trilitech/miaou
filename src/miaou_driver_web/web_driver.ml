(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(** Web backend for the Matrix driver.

    Serves a xterm.js-based web terminal over HTTP/WebSocket and delegates
    the main loop to {!Matrix_main_loop}. *)

open Miaou_core
open Miaou_driver_matrix
module Fibers = Miaou_helpers.Fiber_runtime

let available = true

(* Thread-safe output buffer.
   The render domain writes ANSI strings here; an Eio fiber flushes
   them over the WebSocket connection. *)
module Output_buffer = struct
  type t = {mutex : Mutex.t; buf : Buffer.t; has_data : bool Atomic.t}

  let create () =
    {
      mutex = Mutex.create ();
      buf = Buffer.create 4096;
      has_data = Atomic.make false;
    }

  let write t s =
    Mutex.lock t.mutex ;
    Buffer.add_string t.buf s ;
    Atomic.set t.has_data true ;
    Mutex.unlock t.mutex

  let take t =
    if not (Atomic.get t.has_data) then None
    else begin
      Mutex.lock t.mutex ;
      let data = Buffer.contents t.buf in
      Buffer.clear t.buf ;
      Atomic.set t.has_data false ;
      Mutex.unlock t.mutex ;
      if String.length data = 0 then None else Some data
    end
end

(* Session tracks the controller and read-only viewers.

   S6 (reconnect, FR-050) adds the parking/reattach bookkeeping: a
   controller WebSocket closing (client tab closed, network drop, any
   non-clean disconnect) no longer tears the session down — it only
   parks it ([controller_parked <- true]) — so a later connection to the
   same session's [/ws] can hand its (ws, br) pair to [reattach] instead
   of being refused with a "slot taken" 409 or spawning a brand new page
   instance. [reattach] is installed once, by {!run_tui}, right before it
   starts running the shared main loop; it captures {!run_tui}'s own
   private mutable state (the current transport cell, the switch reader
   fibers are forked under, the event stream) so this module itself never
   needs to know any of {!run_tui}'s internals. *)
module Session = struct
  type t = {
    mutex : Mutex.t;
    mutable viewers : Web_websocket.t list;
    mutable viewer_input_rejections : int;
        (** FR-041 audit counter: every inbound frame on a viewer
            connection that would map to an input event (key/resize/
            mouse) increments this instead of being silently discarded,
            so the rejection is observable/testable rather than
            enforcement-by-omission. *)
    mutable controller_parked : bool;
        (** [true] once a controller has attached at least once and its
            connection has since closed (any close — clean or abrupt)
            without the app itself reaching a terminal outcome. [false]
            before any controller has ever attached, and while one is
            currently live. Consulted by the accept loop to route a new
            [/ws] connection to {!reattach} (reconnect) instead of the
            "controller slot taken" 409. *)
    mutable reattach :
      (Web_websocket.t -> Eio.Buf_read.t -> close:(unit -> unit) -> unit) option;
        (** Set by {!run_tui} once it starts; [None] before the first
            attach and after the app reaches a terminal outcome (Quit /
            Back-to-empty-stack / SwitchTo-not-found) — at that point the
            worker process itself is about to exit (S6), so there is
            nothing left to reattach to. Calling the function adopts a
            new (ws, br) pair as the session's current controller
            transport: it must only ever be invoked while
            [controller_parked] is [true]. *)
  }

  let create () =
    {
      mutex = Mutex.create ();
      viewers = [];
      viewer_input_rejections = 0;
      controller_parked = false;
      reattach = None;
    }

  (* [true] iff a new [/ws] connection should be routed to {!reattach}
     rather than refused as "slot taken" — both the parked flag and a
     live [reattach] callback must hold (the callback is briefly [None]
     during the very first attach's own startup window, before
     {!run_tui} has installed it; a connection racing in during that
     window is correctly refused, same as pre-S6 behavior, rather than
     crashing on [Option.get]). *)
  let can_reattach t = t.controller_parked && Option.is_some t.reattach

  (* Records one rejected viewer input frame and returns the new running
     count (used only to make the emitted audit line self-numbering). *)
  let record_viewer_input_rejection t =
    Mutex.lock t.mutex ;
    t.viewer_input_rejections <- t.viewer_input_rejections + 1 ;
    let n = t.viewer_input_rejections in
    Mutex.unlock t.mutex ;
    n

  let add_viewer t ws =
    Mutex.lock t.mutex ;
    t.viewers <- ws :: t.viewers ;
    Mutex.unlock t.mutex

  let remove_viewer t ws =
    Mutex.lock t.mutex ;
    t.viewers <- List.filter (fun v -> v != ws) t.viewers ;
    Mutex.unlock t.mutex

  let broadcast t data =
    Mutex.lock t.mutex ;
    t.viewers <-
      List.filter
        (fun ws ->
          if Web_websocket.is_closed ws then false
          else begin
            (try Web_websocket.send_text ws data with _ -> ()) ;
            not (Web_websocket.is_closed ws)
          end)
        t.viewers ;
    Mutex.unlock t.mutex

  let close_all_viewers t =
    Mutex.lock t.mutex ;
    List.iter (fun ws -> try Web_websocket.close ws with _ -> ()) t.viewers ;
    t.viewers <- [] ;
    Mutex.unlock t.mutex
end

type auth = {
  controller_password : string option;
  viewer_password : string option;
}

type extra_asset = {path : string; content_type : string; body : string}

let send_role_message ws role =
  let msg = Printf.sprintf {|{"type":"role","role":"%s"}|} role in
  Web_websocket.send_text ws msg

(* Extract path (without query string) from an HTTP request line like
   "GET /path?key=val HTTP/1.1" *)
let extract_path request_line =
  let raw =
    match String.split_on_char ' ' request_line with
    | _ :: path :: _ -> path
    | _ -> "/"
  in
  match String.split_on_char '?' raw with first :: _ -> first | [] -> "/"

(* Extract a query parameter value from the raw URI in an HTTP request line.
   Returns [Some value] for "?password=value" or [None] if missing. *)
let extract_query_param request_line param =
  let raw =
    match String.split_on_char ' ' request_line with
    | _ :: path :: _ -> path
    | _ -> "/"
  in
  match String.split_on_char '?' raw with
  | _ :: qs_parts -> (
      let qs = String.concat "?" qs_parts in
      let pairs = String.split_on_char '&' qs in
      let prefix = param ^ "=" in
      let plen = String.length prefix in
      match
        List.find_opt
          (fun p -> String.length p >= plen && String.sub p 0 plen = prefix)
          pairs
      with
      | Some pair -> Some (String.sub pair plen (String.length pair - plen))
      | None -> None)
  | _ -> None

(* Send an HTTP response directly to a flow *)
let serve_response conn ~status ~content_type body =
  let len = String.length body in
  let headers =
    Printf.sprintf
      "%s\r\n\
       Content-Type: %s\r\n\
       Content-Length: %d\r\n\
       Connection: close\r\n\
       \r\n"
      status
      content_type
      len
  in
  Eio.Flow.write
    (conn :> Eio.Flow.sink_ty Eio.Resource.t)
    [Cstruct.of_string (headers ^ body)]

let serve_200 conn ~content_type body =
  serve_response conn ~status:"HTTP/1.1 200 OK" ~content_type body

let serve_404 conn =
  serve_response
    conn
    ~status:"HTTP/1.1 404 Not Found"
    ~content_type:"text/plain"
    "Not Found"

let serve_403 conn =
  serve_response
    conn
    ~status:"HTTP/1.1 403 Forbidden"
    ~content_type:"text/plain"
    "Forbidden"

let serve_409 conn msg =
  serve_response
    conn
    ~status:"HTTP/1.1 409 Conflict"
    ~content_type:"text/plain"
    msg

(* Check a supplied password against an expected password.
   Returns [true] if no password is required or if it matches. *)
let check_password ~expected ~supplied =
  match expected with None -> true | Some exp -> supplied = Some exp

(* Parse a JSON client message and push the corresponding event *)
let parse_client_message events ~current_rows ~current_cols msg =
  match Yojson.Safe.from_string msg with
  | json -> (
      let open Yojson.Safe.Util in
      match member "type" json |> to_string with
      | "key" ->
          let key = member "key" json |> to_string in
          Eio.Stream.add events (Matrix_io.Key key)
      | "resize" ->
          let rows = member "rows" json |> to_int in
          let cols = member "cols" json |> to_int in
          current_rows := rows ;
          current_cols := cols ;
          Eio.Stream.add events Matrix_io.Resize
      | "mouse" ->
          let row = member "row" json |> to_int in
          let col = member "col" json |> to_int in
          (* Web driver doesn't report button, default to left (0) *)
          Eio.Stream.add events (Matrix_io.Mouse (row, col, 0))
      | _ -> ()
      | exception _ -> ())
  | exception _ -> ()

(* FR-040/FR-041: a viewer connection's role is fixed at connect time (by
   which path it upgraded on — never re-derived per frame, and never
   client-asserted); this classifies an inbound frame on that connection
   *without* ever handing it to {!parse_client_message} (which is what
   would route it to {!Matrix_io}). Any frame whose declared ["type"] is
   one that {!parse_client_message} would turn into an input event
   (["key"], ["resize"], ["mouse"]) is an explicit, audited rejection
   instead of the previous silent discard-everything behavior — closing
   the "easy to regress silently" gap (a future refactor that reused
   [parse_client_message] here would have quietly reintroduced viewer
   input, with nothing catching it). Anything else (unknown message
   types, malformed JSON, keepalive-style pings already handled inside
   {!Web_websocket.recv_text}) is not an input event and is ignored, same
   as before. *)
let classify_and_audit_viewer_input session msg =
  match Yojson.Safe.from_string msg with
  | json -> (
      let open Yojson.Safe.Util in
      match member "type" json |> to_string with
      | ("key" | "resize" | "mouse") as input_type ->
          let n = Session.record_viewer_input_rejection session in
          Printf.eprintf
            "[web] AUDIT viewer-input-rejected type=%s count=%d\n%!"
            input_type
            n
      | _ -> ()
      | exception _ -> ())
  | exception _ -> ()

exception Tui_done of ([`Quit | `Back | `SwitchTo of string] * (int * int))

(* Run the TUI over an established WebSocket connection.
   [~initial_size] can be passed to skip waiting for resize on page switch.

   S6 (reconnect, FR-050): a client-close (clean WebSocket close frame, or
   an abrupt disconnect — the reader fiber cannot tell the difference, and
   per FR-051 doesn't need to) no longer injects {!Matrix_io.Quit}. It
   only "parks" the session: {!Matrix_main_loop.run}'s call below keeps
   blocking (the render domain and all page/navigation state stay exactly
   as they were — that state lives in the [Packed] value {!Matrix_main_loop.run}
   closes over internally, never touched by this module), while the
   *transport* (the current controller [Web_websocket.t] / [Buf_read.t]
   pair) is cleared. A later connection to the same session's [/ws] calls
   the [reattach] closure installed on [session] below, which swaps in
   the new transport, forks a fresh reader fiber for it, and injects a
   synthetic {!Matrix_io.Resize} event — {!Matrix_main_loop}'s *existing*,
   unmodified Resize handling already does the FR-050 full-redraw
   (["\027[2J\027[H"] plus [Matrix_buffer.mark_all_dirty]), so reconnect
   reuses that exact path rather than duplicating it here. Only the app
   itself reaching a genuine terminal outcome (`Quit`/`Back`/`SwitchTo`)
   ends {!Matrix_main_loop.run}'s call — client transport churn never
   does. *)
let run_tui (env : Eio_unix.Stdenv.base) config session ~conn ws br
    ?(initial_size : (int * int) option) initial_page =
  Printf.eprintf "[web] WebSocket TUI session starting\n%!" ;
  let events = Eio.Stream.create 256 in
  let current_rows, current_cols =
    match initial_size with
    | Some (r, c) ->
        Printf.eprintf "[web] Using passed size: %dx%d\n%!" r c ;
        (ref r, ref c)
    | None -> (ref 24, ref 80)
  in
  let last_refresh = ref (Unix.gettimeofday ()) in
  let output = Output_buffer.create () in
  let config =
    match config with Some c -> c | None -> Matrix_config.load ()
  in
  let buffer = Matrix_buffer.create ~rows:!current_rows ~cols:!current_cols in
  let parser = Matrix_ansi_parser.create () in
  let writer = Matrix_ansi_writer.create () in
  let render_loop =
    Matrix_render_loop.create
      ~config
      ~buffer
      ~writer
      ~write:(Output_buffer.write output)
  in
  (* The current controller transport: [None] while parked (no controller
     currently attached), [Some ws] while one is live. Read by the single,
     long-lived flusher fiber below; written by the reader fiber that
     detects a close (clears it) and by [reattach] (sets it). [close_current]
     is the thunk that closes whichever raw connection (`conn`) backs the
     transport currently in [current_ws] — parking (or the final terminal
     cleanup) calls it so the OS-level socket for a since-abandoned
     connection is not leaked. *)
  let current_ws = ref (Some ws) in
  let close_current =
    ref (Some (fun () -> try Eio.Flow.close conn with _ -> ()))
  in
  let flush_count = ref 0 in
  let flush_output () =
    match Output_buffer.take output with
    | Some data ->
        incr flush_count ;
        if !flush_count <= 3 then
          Printf.eprintf
            "[web] Flushing %d bytes (frame #%d)\n%!"
            (String.length data)
            !flush_count ;
        (match !current_ws with
        | Some ws -> ( try Web_websocket.send_text ws data with _ -> ())
        | None ->
            (* Parked: nobody to send to. Dropped, not buffered — a
               reattach forces a full redraw (via the synthetic Resize
               event below) rather than replaying whatever accumulated
               while nobody was listening. *)
            ()) ;
        Session.broadcast session data
    | None -> ()
  in
  let refresh_interval = config.frame_time_ms /. 1000.0 in
  let io : Matrix_io.t =
    {
      write = Output_buffer.write output;
      drain =
        (fun () ->
          let acc = ref [] in
          let rec take () =
            match Eio.Stream.take_nonblocking events with
            | Some ev ->
                acc := ev :: !acc ;
                take ()
            | None -> ()
          in
          take () ;
          (* Inject periodic Refresh so service_cycle runs when idle *)
          let now = Unix.gettimeofday () in
          if now -. !last_refresh >= refresh_interval then begin
            last_refresh := now ;
            acc := Matrix_io.Refresh :: !acc
          end ;
          List.rev !acc);
      size = (fun () -> (!current_rows, !current_cols));
      invalidate_size_cache = (fun () -> ());
    }
  in
  let ctx : Matrix_main_loop.context =
    {config; buffer; parser; render_loop; io}
  in
  (* Parks the session if [this_ws] is still the attached transport (a
     physical-equality guard, same pattern as {!Serve_session.reap_and_log}'s
     [w == worker] guard — protects against a stale, already-superseded
     reader fiber's own close detection clobbering a newer reattach that
     raced in ahead of it). Never raises: closing an already-abruptly-dead
     connection is expected to error, and is not itself news. *)
  let park_if_current ~ws:this_ws =
    match !current_ws with
    | Some cur when cur == this_ws ->
        current_ws := None ;
        (match !close_current with
        | Some f -> ( try f () with _ -> ())
        | None -> ()) ;
        close_current := None ;
        session.Session.controller_parked <- true
    | Some _ | None -> ()
  in
  let spawn_reader ~sw this_ws this_br =
    Eio.Fiber.fork ~sw (fun () ->
        try
          let rec loop () =
            match Web_websocket.recv_text this_ws this_br with
            | None ->
                Printf.eprintf
                  "[web] WebSocket closed by client, parking session\n%!" ;
                park_if_current ~ws:this_ws
            | Some msg ->
                Printf.eprintf "[web] Client msg: %s\n%!" msg ;
                parse_client_message events ~current_rows ~current_cols msg ;
                loop ()
          in
          loop ()
        with exn ->
          Printf.eprintf
            "[web] Reader fiber error: %s, parking session\n%!"
            (Printexc.to_string exn) ;
          park_if_current ~ws:this_ws)
  in
  try
    Eio.Switch.run (fun sw ->
        (* Installed once, before the main loop starts, so a reconnect
           racing in extremely early (immediately after role assignment)
           still finds a live [reattach] rather than a "not started yet"
           gap. Cleared at the very end, once the app reaches a genuine
           terminal outcome — nothing is left to reattach to at that
           point (S6: the worker process itself is about to exit). *)
        session.Session.reattach <-
          Some
            (fun new_ws new_br ~close ->
              (* Discard whatever accumulated in [output] while parked
                 (or the last live frame not yet flushed) — the synthetic
                 Resize event below forces a fresh full redraw, so stale
                 pre-reattach content must never precede it. *)
              ignore (Output_buffer.take output : string option) ;
              current_ws := Some new_ws ;
              close_current := Some close ;
              session.Session.controller_parked <- false ;
              spawn_reader ~sw new_ws new_br ;
              Eio.Stream.add events Matrix_io.Resize) ;
        (* WebSocket reader fiber, for the initial (first-attach) transport *)
        spawn_reader ~sw ws br ;
        (* Output flusher fiber: drains the thread-safe buffer over
           whichever transport is currently attached (or drops it, while
           parked) — see [flush_output] above. *)
        Eio.Fiber.fork ~sw (fun () ->
            try
              let rec loop () =
                flush_output () ;
                Eio.Time.sleep env#clock 0.016 ;
                loop ()
              in
              loop ()
            with exn ->
              Printf.eprintf
                "[web] Flusher fiber error: %s\n%!"
                (Printexc.to_string exn)) ;
        (* Wait briefly for the client to send initial dimensions.
           On first connection the client sends resize after role assignment.
           On page switch within the same connection, no resize is sent,
           so we use a short timeout and fall back to default size. *)
        Printf.eprintf "[web] Waiting for initial resize from client...\n%!" ;
        let rec drain_until_resize_or_timeout deadline =
          let now = Unix.gettimeofday () in
          if now >= deadline then
            Printf.eprintf
              "[web] Resize timeout, using %dx%d\n%!"
              !current_rows
              !current_cols
          else
            match Eio.Stream.take_nonblocking events with
            | Some Matrix_io.Resize ->
                Printf.eprintf
                  "[web] Got initial resize: %dx%d\n%!"
                  !current_rows
                  !current_cols ;
                Matrix_buffer.resize
                  buffer
                  ~rows:!current_rows
                  ~cols:!current_cols
            | Some Matrix_io.Quit ->
                raise (Tui_done (`Quit, (!current_rows, !current_cols)))
            | Some _ -> drain_until_resize_or_timeout deadline
            | None ->
                Eio.Time.sleep env#clock 0.01 ;
                drain_until_resize_or_timeout deadline
        in
        drain_until_resize_or_timeout (Unix.gettimeofday () +. 0.5) ;
        (* Hide cursor and clear the screen so old content from a previous
           page doesn't bleed through in xterm.js *)
        let init = Matrix_ansi_writer.cursor_hide ^ "\027[2J\027[H" in
        (match !current_ws with
        | Some ws -> ( try Web_websocket.send_text ws init with _ -> ())
        | None -> ()) ;
        Session.broadcast session init ;
        (* Start the render domain and run the shared main loop *)
        Printf.eprintf "[web] Starting render loop and main loop\n%!" ;
        Matrix_render_loop.start render_loop ;
        let result = Matrix_main_loop.run ctx ~env initial_page in
        Printf.eprintf "[web] Main loop exited\n%!" ;
        Matrix_render_loop.shutdown render_loop ;
        flush_output () ;
        let cleanup = Matrix_ansi_writer.cursor_show ^ "\027[0m" in
        (match !current_ws with
        | Some ws -> ( try Web_websocket.send_text ws cleanup with _ -> ())
        | None -> ()) ;
        Session.broadcast session cleanup ;
        (* Terminal outcome: whichever connection is currently attached
           (possibly none, if the app quit while parked) is closed here;
           no future reattach is possible once [reattach] is cleared. *)
        (match !close_current with
        | Some f -> ( try f () with _ -> ())
        | None -> ()) ;
        close_current := None ;
        current_ws := None ;
        session.Session.reattach <- None ;
        let final_size = (!current_rows, !current_cols) in
        raise (Tui_done (result, final_size)))
  with Tui_done (result, size) ->
    Printf.eprintf "[web] TUI session ended\n%!" ;
    (result, size)

type listen = [`Tcp of string * int | `Unix of string]

(* Resolve a [`Tcp (host, port)] listen target's host string into an Eio
   Ipaddr. This is the fix for the pre-Slice-2 discrepancy: previously
   [run] always bound [Eio.Net.Ipaddr.V4.any] (all interfaces) no matter
   what its log line implied — [run_on]'s [`Tcp] variant honors [host]
   literally, so e.g. ["127.0.0.1"] genuinely restricts to loopback.

   ["localhost"] is resolved to the loopback literal before parsing:
   [Unix.inet_addr_of_string] only accepts numeric IP literals, but
   ["localhost"] is one of the hostnames a caller may reasonably pass
   here — and, notably, one of the hostnames
   {!Miaou_serve.Serve_policy.is_loopback} already treats as
   already-trusted. Leaving the two inconsistent would let
   [--bind localhost] pass the fail-closed check and then crash with an
   uncaught [Failure] the first time a socket is actually opened. Any
   other non-numeric host is a genuine usage error and still raises, but
   with a clear message instead of {!Unix.inet_addr_of_string}'s bare
   ["inet_addr_of_string"] failure. *)
let ipaddr_of_host host =
  let literal = if host = "localhost" then "127.0.0.1" else host in
  match Unix.inet_addr_of_string literal with
  | addr -> Eio_unix.Net.Ipaddr.of_unix addr
  | exception Failure _ ->
      invalid_arg
        (Printf.sprintf
           "Web_driver.run_on: %S is not a valid IP literal (DNS name \
            resolution is not supported here; use an IP address or \
            \"localhost\")"
           host)

let sockaddr_of_listen (listen : listen) : Eio.Net.Sockaddr.stream =
  match listen with
  | `Tcp (host, port) -> `Tcp (ipaddr_of_host host, port)
  | `Unix path -> `Unix path

let describe_listen (listen : listen) =
  match listen with
  | `Tcp (host, port) -> Printf.sprintf "http://%s:%d" host port
  | `Unix path -> Printf.sprintf "unix:%s" path

let run_on ?(config = None) ~(listen : listen) ?auth
    ?(controller_html = Web_assets.index_html)
    ?(viewer_html = Web_assets.viewer_html) ?(extra_assets = [])
    ?(on_session_end = fun () -> ()) (initial_page : (module Tui_page.PAGE_SIG))
    : [`Quit | `Back | `SwitchTo of string] =
  Fibers.with_page_switch (fun env page_sw ->
      Printf.eprintf "Miaou web driver: %s\n%!" (describe_listen listen) ;
      let socket =
        Eio.Net.listen
          env#net
          ~sw:page_sw
          ~reuse_addr:true
          ~backlog:5
          (sockaddr_of_listen listen)
      in
      let session : Session.t option ref = ref None in
      (* Accept loop: serve HTTP requests and manage controller/viewer
         WebSocket connections. *)
      let rec accept_loop () =
        let conn, _addr = Eio.Net.accept ~sw:page_sw socket in
        (* Disable Nagle's algorithm so small frames (e.g. the 101 upgrade
           response) are sent immediately rather than buffered. *)
        (match Eio_unix.Resource.fd_opt (conn :> _ Eio.Resource.t) with
        | Some fd -> (
            (* TCP_NODELAY is not a valid socket option on a Unix domain
               socket (the [`Unix path] listen target, used by a worker
               process) — setsockopt would raise ENOPROTOOPT there, so
               this is best-effort and silently ignored, not asserted. *)
            try
              Eio_unix.Fd.use_exn "nodelay" fd (fun unix_fd ->
                  Unix.setsockopt unix_fd Unix.TCP_NODELAY true)
            with Unix.Unix_error _ -> ())
        | None -> ()) ;
        (try
           let br = Eio.Buf_read.of_flow ~max_size:(1024 * 1024) conn in
           let request_line = Eio.Buf_read.line br in
           let headers = Web_websocket.parse_headers br in
           let path = extract_path request_line in
           Printf.eprintf "[web] %s\n%!" request_line ;
           match path with
           | "/" -> (
               serve_200 conn ~content_type:"text/html" controller_html ;
               try Eio.Flow.close conn with _ -> ())
           | "/viewer" -> (
               serve_200 conn ~content_type:"text/html" viewer_html ;
               try Eio.Flow.close conn with _ -> ())
           | "/client.js" -> (
               serve_200
                 conn
                 ~content_type:"application/javascript"
                 Web_assets.client_js ;
               try Eio.Flow.close conn with _ -> ())
           | "/ws" -> (
               (* Controller WebSocket endpoint *)
               let password = extract_query_param request_line "password" in
               let required_password =
                 match auth with
                 | None -> None
                 | Some a -> a.controller_password
               in
               if
                 not
                   (check_password
                      ~expected:required_password
                      ~supplied:password)
               then begin
                 Printf.eprintf "[web] Auth failed for /ws\n%!" ;
                 serve_403 conn ;
                 try Eio.Flow.close conn with _ -> ()
               end
               else if
                 match !session with
                 | Some sess -> not (Session.can_reattach sess)
                 | None -> false
               then begin
                 Printf.eprintf "[web] Controller slot taken, returning 409\n%!" ;
                 serve_409 conn "Controller slot already taken" ;
                 try Eio.Flow.close conn with _ -> ()
               end
               else
                 let sink = (conn :> Eio.Flow.sink_ty Eio.Resource.t) in
                 let write s = Eio.Flow.write sink [Cstruct.of_string s] in
                 match Web_websocket.upgrade headers ~write with
                 | None -> (
                     Printf.eprintf "[web] WebSocket upgrade failed\n%!" ;
                     serve_404 conn ;
                     try Eio.Flow.close conn with _ -> ())
                 | Some ws -> (
                     match !session with
                     | Some sess when Session.can_reattach sess -> (
                         (* S6 (FR-050) reconnect: this session already has
                            a worker instance parked (a controller attached
                            once and has since detached, cleanly or
                            abruptly) — hand this new (ws, br) pair to the
                            already-running {!run_tui} instead of spawning
                            a fresh page. *)
                         Printf.eprintf
                           "[web] WebSocket upgraded (controller reconnect)\n%!" ;
                         send_role_message ws "controller" ;
                         match sess.Session.reattach with
                         | Some reattach ->
                             reattach ws br ~close:(fun () ->
                                 try Eio.Flow.close conn with _ -> ())
                         | None -> (
                             (* Lost the race: [reattach] was cleared
                                (session reached a terminal outcome)
                                between the [can_reattach] check above and
                                here. Refuse cleanly rather than silently
                                dropping the connection. *)
                             Printf.eprintf
                               "[web] Reattach race lost, session already \
                                terminal\n\
                                %!" ;
                             Web_websocket.close ws ;
                             try Eio.Flow.close conn with _ -> ()))
                     | Some _ | None ->
                         Printf.eprintf
                           "[web] WebSocket upgraded (controller)\n%!" ;
                         let sess = Session.create () in
                         session := Some sess ;
                         send_role_message ws "controller" ;
                         Eio.Fiber.fork ~sw:page_sw (fun () ->
                             let page_stack = ref [] in
                             (* [terminal] tracks whether the loop below ended
                            because the app reached a genuine terminal
                            outcome (Quit / Back-to-empty-stack /
                            SwitchTo-not-found) — as opposed to an
                            uncaught exception. [run_tui] itself already
                            closes whichever transport/connection is
                            *currently* attached before returning (S6:
                            it, not this stale [ws]/[conn], is what a
                            reattach may have swapped in) — nothing here
                            needs to call {!Web_websocket.close} or
                            {!Eio.Flow.close conn} again for the terminal
                            case; [conn] is only closed here as a
                            best-effort backstop for the exception path,
                            where [run_tui] may not have run its own
                            cleanup. *)
                             let terminal = ref false in
                             let rec page_loop ?initial_size current_page =
                               let result, final_size =
                                 run_tui
                                   env
                                   config
                                   sess
                                   ~conn
                                   ws
                                   br
                                   ?initial_size
                                   current_page
                               in
                               match result with
                               | `Quit -> terminal := true
                               | `Back -> (
                                   match !page_stack with
                                   | [] -> terminal := true
                                   | prev :: rest ->
                                       page_stack := rest ;
                                       page_loop ~initial_size:final_size prev)
                               | `SwitchTo next -> (
                                   match Registry.find next with
                                   | Some p ->
                                       page_stack := current_page :: !page_stack ;
                                       page_loop ~initial_size:final_size p
                                   | None ->
                                       Printf.eprintf
                                         "[web] Page %S not found, closing\n%!"
                                         next ;
                                       terminal := true)
                             in
                             (try page_loop initial_page
                              with exn -> (
                                Printf.eprintf
                                  "[web] Controller error: %s\n%!"
                                  (Printexc.to_string exn) ;
                                try Eio.Flow.close conn with _ -> ())) ;
                             Printf.eprintf
                               "[web] Controller disconnected, closing viewers\n\
                                %!" ;
                             Session.close_all_viewers sess ;
                             session := None ;
                             (* S6/FR-050: a genuine terminal outcome (as
                            opposed to a client merely detaching, which
                            [run_tui] now parks rather than reports here
                            at all) is the *only* time this hook fires —
                            [Serve_worker.run] wires it to end the whole
                            worker process, so a reconnect attempt after
                            an app-initiated Quit finds no worker at all
                            (dead end, not a fresh page instance), while
                            a generic (non-serve) {!run_on} caller — whose
                            default hook is a no-op — keeps its
                            pre-S6 behavior of simply returning here
                            unchanged. *)
                             if !terminal then on_session_end ())))
           | "/ws/viewer" -> (
               (* Viewer WebSocket endpoint *)
               let password = extract_query_param request_line "password" in
               let required_password =
                 match auth with None -> None | Some a -> a.viewer_password
               in
               if
                 not
                   (check_password
                      ~expected:required_password
                      ~supplied:password)
               then begin
                 Printf.eprintf "[web] Auth failed for /ws/viewer\n%!" ;
                 serve_403 conn ;
                 try Eio.Flow.close conn with _ -> ()
               end
               else
                 match !session with
                 | None -> (
                     Printf.eprintf "[web] No controller yet, returning 409\n%!" ;
                     serve_409 conn "No controller connected yet" ;
                     try Eio.Flow.close conn with _ -> ())
                 | Some sess -> (
                     let sink = (conn :> Eio.Flow.sink_ty Eio.Resource.t) in
                     let write s = Eio.Flow.write sink [Cstruct.of_string s] in
                     match Web_websocket.upgrade headers ~write with
                     | None -> (
                         Printf.eprintf "[web] WebSocket upgrade failed\n%!" ;
                         serve_404 conn ;
                         try Eio.Flow.close conn with _ -> ())
                     | Some ws ->
                         Printf.eprintf "[web] WebSocket upgraded (viewer)\n%!" ;
                         Session.add_viewer sess ws ;
                         send_role_message ws "viewer" ;
                         Eio.Fiber.fork ~sw:page_sw (fun () ->
                             (try
                                let rec loop () =
                                  match Web_websocket.recv_text ws br with
                                  | None -> ()
                                  | Some msg ->
                                      classify_and_audit_viewer_input sess msg ;
                                      loop ()
                                in
                                loop ()
                              with _ -> ()) ;
                             Printf.eprintf "[web] Viewer disconnected\n%!" ;
                             Session.remove_viewer sess ws ;
                             try Eio.Flow.close conn with _ -> ())))
           | _ -> (
               (* Check extra_assets, then 404 *)
               match List.find_opt (fun a -> a.path = path) extra_assets with
               | Some asset -> (
                   serve_200 conn ~content_type:asset.content_type asset.body ;
                   try Eio.Flow.close conn with _ -> ())
               | None -> (
                   serve_404 conn ;
                   try Eio.Flow.close conn with _ -> ()))
         with
        | Eio.Io _ as exn ->
            Printf.eprintf "[web] I/O error: %s\n%!" (Printexc.to_string exn)
        | End_of_file -> Printf.eprintf "[web] Connection closed (EOF)\n%!"
        | exn ->
            Printf.eprintf
              "[web] Unexpected error: %s\n%!"
              (Printexc.to_string exn)) ;
        accept_loop ()
      in
      accept_loop ())

let run ?(config = None) ?(port = 8080) ?auth
    ?(controller_html = Web_assets.index_html)
    ?(viewer_html = Web_assets.viewer_html) ?(extra_assets = [])
    (initial_page : (module Tui_page.PAGE_SIG)) :
    [`Quit | `Back | `SwitchTo of string] =
  run_on
    ~config
    ~listen:(`Tcp ("0.0.0.0", port))
    ?auth
    ~controller_html
    ~viewer_html
    ~extra_assets
    initial_page
