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

[@@@warning "-32-34-37-69"]

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

(* Session tracks the controller and read-only viewers. *)
module Session = struct
  type t = {
    mutex : Mutex.t;
    mutable viewers : Web_websocket.t list;
    mutable active : bool;
  }

  let create () = {mutex = Mutex.create (); viewers = []; active = true}

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
    t.active <- false ;
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
          Eio.Stream.add events (Matrix_io.Mouse (row, col))
      | _ -> ()
      | exception _ -> ())
  | exception _ -> ()

exception Tui_done of [`Quit | `SwitchTo of string]

(* Run the TUI over an established WebSocket connection *)
let run_tui (env : Eio_unix.Stdenv.base) config session ws br initial_page =
  Printf.eprintf "[web] WebSocket TUI session starting\n%!" ;
  let events = Eio.Stream.create 256 in
  let current_rows = ref 24 in
  let current_cols = ref 80 in
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
        Web_websocket.send_text ws data ;
        Session.broadcast session data
    | None -> ()
  in
  let refresh_interval = config.frame_time_ms /. 1000.0 in
  let io : Matrix_io.t =
    {
      write = Output_buffer.write output;
      poll =
        (fun ~timeout_ms ->
          (* Always drain pending events first so input is never starved *)
          match Eio.Stream.take_nonblocking events with
          | Some ev -> ev
          | None -> (
              let now = Unix.gettimeofday () in
              if now -. !last_refresh >= refresh_interval then begin
                last_refresh := now ;
                Matrix_io.Refresh
              end
              else
                let timeout_s = float_of_int timeout_ms /. 1000.0 in
                match
                  Eio.Time.with_timeout env#clock timeout_s (fun () ->
                      Ok (Eio.Stream.take events))
                with
                | Ok ev -> ev
                | Error `Timeout -> Matrix_io.Idle));
      drain_nav_keys = (fun _ -> 0);
      drain_esc_keys = (fun () -> 0);
      size = (fun () -> (!current_rows, !current_cols));
      invalidate_size_cache = (fun () -> ());
    }
  in
  let ctx : Matrix_main_loop.context =
    {config; buffer; parser; render_loop; io}
  in
  try
    Eio.Switch.run (fun sw ->
        (* WebSocket reader fiber *)
        Eio.Fiber.fork ~sw (fun () ->
            try
              let rec loop () =
                match Web_websocket.recv_text ws br with
                | None ->
                    Printf.eprintf "[web] WebSocket closed by client\n%!" ;
                    Eio.Stream.add events Matrix_io.Quit
                | Some msg ->
                    Printf.eprintf "[web] Client msg: %s\n%!" msg ;
                    parse_client_message events ~current_rows ~current_cols msg ;
                    loop ()
              in
              loop ()
            with exn ->
              Printf.eprintf
                "[web] Reader fiber error: %s\n%!"
                (Printexc.to_string exn) ;
              Eio.Stream.add events Matrix_io.Quit) ;
        (* Output flusher fiber: drains the thread-safe buffer over WebSocket *)
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
        (* Clear the screen so old content from a previous page doesn't
           bleed through in xterm.js *)
        let clear = "\027[2J\027[H" in
        Web_websocket.send_text ws clear ;
        Session.broadcast session clear ;
        (* Start the render domain and run the shared main loop *)
        Printf.eprintf "[web] Starting render loop and main loop\n%!" ;
        Matrix_render_loop.start render_loop ;
        let result = Matrix_main_loop.run ctx ~env initial_page in
        Printf.eprintf "[web] Main loop exited\n%!" ;
        Matrix_render_loop.shutdown render_loop ;
        flush_output () ;
        raise (Tui_done result))
  with Tui_done result ->
    Printf.eprintf "[web] TUI session ended\n%!" ;
    result

let run ?(config = None) ?(port = 8080) ?auth
    ?(controller_html = Web_assets.index_html)
    ?(viewer_html = Web_assets.viewer_html) ?(extra_assets = [])
    (initial_page : (module Tui_page.PAGE_SIG)) : [`Quit | `SwitchTo of string]
    =
  Fibers.with_page_switch (fun env page_sw ->
      Printf.eprintf "Miaou web driver: http://127.0.0.1:%d\n%!" port ;
      let socket =
        Eio.Net.listen
          env#net
          ~sw:page_sw
          ~reuse_addr:true
          ~backlog:5
          (`Tcp (Eio.Net.Ipaddr.V4.any, port))
      in
      let session : Session.t option ref = ref None in
      (* Accept loop: serve HTTP requests and manage controller/viewer
         WebSocket connections. *)
      let rec accept_loop () =
        let conn, _addr = Eio.Net.accept ~sw:page_sw socket in
        (* Disable Nagle's algorithm so small frames (e.g. the 101 upgrade
           response) are sent immediately rather than buffered. *)
        (match Eio_unix.Resource.fd_opt (conn :> _ Eio.Resource.t) with
        | Some fd ->
            Eio_unix.Fd.use_exn "nodelay" fd (fun unix_fd ->
                Unix.setsockopt unix_fd Unix.TCP_NODELAY true)
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
               else if Option.is_some !session then begin
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
                 | Some ws ->
                     Printf.eprintf "[web] WebSocket upgraded (controller)\n%!" ;
                     let sess = Session.create () in
                     session := Some sess ;
                     send_role_message ws "controller" ;
                     Eio.Fiber.fork ~sw:page_sw (fun () ->
                         let page_stack = ref [] in
                         let rec page_loop current_page =
                           let result =
                             run_tui env config sess ws br current_page
                           in
                           match result with
                           | `Quit -> Web_websocket.close ws
                           | `SwitchTo "__BACK__" -> (
                               match !page_stack with
                               | [] -> Web_websocket.close ws
                               | prev :: rest ->
                                   page_stack := rest ;
                                   page_loop prev)
                           | `SwitchTo next -> (
                               match Registry.find next with
                               | Some p ->
                                   page_stack := current_page :: !page_stack ;
                                   page_loop p
                               | None ->
                                   Printf.eprintf
                                     "[web] Page %S not found, closing\n%!"
                                     next ;
                                   Web_websocket.close ws)
                         in
                         (try page_loop initial_page
                          with exn ->
                            Printf.eprintf
                              "[web] Controller error: %s\n%!"
                              (Printexc.to_string exn)) ;
                         Printf.eprintf
                           "[web] Controller disconnected, closing viewers\n%!" ;
                         Session.close_all_viewers sess ;
                         session := None ;
                         try Eio.Flow.close conn with _ -> ()))
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
                                  | Some _ -> loop ()
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
