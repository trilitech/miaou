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

(* Extract path from an HTTP request line like "GET /path HTTP/1.1" *)
let extract_path request_line =
  match String.split_on_char ' ' request_line with
  | _ :: path :: _ -> path
  | _ -> "/"

(* Send an HTTP response and close the connection *)
let serve_response bw ~status ~content_type body =
  let len = String.length body in
  Eio.Buf_write.string
    bw
    (Printf.sprintf
       "%s\r\n\
        Content-Type: %s\r\n\
        Content-Length: %d\r\n\
        Connection: close\r\n\
        \r\n"
       status
       content_type
       len) ;
  Eio.Buf_write.string bw body

let serve_200 bw ~content_type body =
  serve_response bw ~status:"HTTP/1.1 200 OK" ~content_type body

let serve_404 bw =
  serve_response
    bw
    ~status:"HTTP/1.1 404 Not Found"
    ~content_type:"text/plain"
    "Not Found"

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
let run_tui (env : Eio_unix.Stdenv.base) config ws br bw initial_page =
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
  let flush_output () =
    match Output_buffer.take output with
    | Some data -> Web_websocket.send_text ws bw data
    | None -> ()
  in
  let io : Matrix_io.t =
    {
      write = Output_buffer.write output;
      poll =
        (fun ~timeout_ms ->
          let now = Unix.gettimeofday () in
          if now -. !last_refresh >= 1.0 then begin
            last_refresh := now ;
            Matrix_io.Refresh
          end
          else
            match Eio.Stream.take_nonblocking events with
            | Some ev -> ev
            | None -> (
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
            let rec loop () =
              match Web_websocket.recv_text ws br bw with
              | None -> Eio.Stream.add events Matrix_io.Quit
              | Some msg ->
                  parse_client_message events ~current_rows ~current_cols msg ;
                  loop ()
            in
            loop ()) ;
        (* Output flusher fiber: drains the thread-safe buffer over WebSocket *)
        Eio.Fiber.fork ~sw (fun () ->
            let rec loop () =
              flush_output () ;
              Eio.Time.sleep env#clock 0.016 ;
              loop ()
            in
            loop ()) ;
        (* Start the render domain and run the shared main loop *)
        Matrix_render_loop.start render_loop ;
        let result = Matrix_main_loop.run ctx ~env initial_page in
        Matrix_render_loop.shutdown render_loop ;
        flush_output () ;
        Web_websocket.close ws bw ;
        raise (Tui_done result))
  with Tui_done result -> result

let run ?(config = None) ?(port = 8080)
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
          (`Tcp (Eio.Net.Ipaddr.V4.loopback, port))
      in
      (* Accept loop: serve HTTP requests until a WebSocket connection
         is established, then run the TUI over that connection. *)
      let rec accept_loop () =
        let conn, _addr = Eio.Net.accept ~sw:page_sw socket in
        let is_ws = ref false in
        let ws_result = ref `Quit in
        begin try
          Eio.Buf_write.with_flow conn (fun bw ->
              let br = Eio.Buf_read.of_flow ~max_size:(1024 * 1024) conn in
              let request_line = Eio.Buf_read.line br in
              let headers = Web_websocket.parse_headers br in
              let path = extract_path request_line in
              match path with
              | "/" ->
                  serve_200 bw ~content_type:"text/html" Web_assets.index_html
              | "/client.js" ->
                  serve_200
                    bw
                    ~content_type:"application/javascript"
                    Web_assets.client_js
              | "/ws" -> (
                  match Web_websocket.upgrade headers bw with
                  | None -> serve_404 bw
                  | Some ws ->
                      is_ws := true ;
                      ws_result := run_tui env config ws br bw initial_page)
              | _ -> serve_404 bw)
        with
        | Eio.Io _ -> ()
        | End_of_file -> ()
        end ;
        if !is_ws then !ws_result else accept_loop ()
      in
      accept_loop ())
