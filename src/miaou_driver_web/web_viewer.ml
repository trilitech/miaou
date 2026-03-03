(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Mathias Bourgoin <mathias.bourgoin@atacama.tech>       *)
(*                                                                           *)
(*****************************************************************************)

(** Standalone viewer-only HTTP+WebSocket server.

    Serves the xterm.js viewer page over HTTP and broadcasts raw ANSI frames
    to all connected viewer WebSockets.  Designed to run alongside the headless
    driver so a human can observe an AI agent's TUI session in a browser. *)

[@@@warning "-32-34-37-69"]

type t = {mutex : Mutex.t; mutable viewers : Web_websocket.t list; port : int}

let create ~port = {mutex = Mutex.create (); viewers = []; port}

let add_viewer t ws =
  Mutex.lock t.mutex ;
  t.viewers <- ws :: t.viewers ;
  Mutex.unlock t.mutex

let remove_viewer t ws =
  Mutex.lock t.mutex ;
  t.viewers <- List.filter (fun v -> v != ws) t.viewers ;
  Mutex.unlock t.mutex

let broadcast t data =
  let frame = "\027[H" ^ data in
  Mutex.lock t.mutex ;
  t.viewers <-
    List.filter
      (fun ws ->
        if Web_websocket.is_closed ws then false
        else begin
          (try Web_websocket.send_text ws frame with _ -> ()) ;
          not (Web_websocket.is_closed ws)
        end)
      t.viewers ;
  Mutex.unlock t.mutex

let url t = Printf.sprintf "http://127.0.0.1:%d/viewer" t.port

(* HTTP response helpers (duplicated from Web_driver to avoid coupling) *)

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

let extract_path request_line =
  let raw =
    match String.split_on_char ' ' request_line with
    | _ :: path :: _ -> path
    | _ -> "/"
  in
  match String.split_on_char '?' raw with first :: _ -> first | [] -> "/"

let start ~sw ~net ~port () =
  let t = create ~port in
  let socket =
    Eio.Net.listen
      net
      ~sw
      ~reuse_addr:true
      ~backlog:5
      (`Tcp (Eio.Net.Ipaddr.V4.any, port))
  in
  Eio.Fiber.fork ~sw (fun () ->
      let rec accept_loop () =
        let conn, _addr = Eio.Net.accept ~sw socket in
        Eio.Fiber.fork ~sw (fun () ->
            try
              let br = Eio.Buf_read.of_flow ~max_size:(1024 * 1024) conn in
              let request_line = Eio.Buf_read.line br in
              let headers = Web_websocket.parse_headers br in
              let path = extract_path request_line in
              match path with
              | "/" | "/viewer" -> (
                  serve_200
                    conn
                    ~content_type:"text/html"
                    Web_assets.viewer_html ;
                  try Eio.Flow.close conn with _ -> ())
              | "/client.js" -> (
                  serve_200
                    conn
                    ~content_type:"application/javascript"
                    Web_assets.client_js ;
                  try Eio.Flow.close conn with _ -> ())
              | "/ws/viewer" -> (
                  let sink = (conn :> Eio.Flow.sink_ty Eio.Resource.t) in
                  let write s = Eio.Flow.write sink [Cstruct.of_string s] in
                  match Web_websocket.upgrade headers ~write with
                  | None -> (
                      serve_404 conn ;
                      try Eio.Flow.close conn with _ -> ())
                  | Some ws -> (
                      (* Send init: hide cursor, clear screen, home *)
                      let init = "\027[?25l\027[2J\027[H" in
                      Web_websocket.send_text ws init ;
                      (* Send role message so client.js knows it's a viewer *)
                      let role_msg = {|{"type":"role","role":"viewer"}|} in
                      Web_websocket.send_text ws role_msg ;
                      add_viewer t ws ;
                      (* Drain incoming messages until close *)
                      (try
                         let rec loop () =
                           match Web_websocket.recv_text ws br with
                           | None -> ()
                           | Some _ -> loop ()
                         in
                         loop ()
                       with _ -> ()) ;
                      remove_viewer t ws ;
                      try Eio.Flow.close conn with _ -> ()))
              | _ -> (
                  serve_404 conn ;
                  try Eio.Flow.close conn with _ -> ())
            with
            | Eio.Io _ -> ()
            | End_of_file -> ()
            | _ -> ()) ;
        accept_loop ()
      in
      accept_loop ()) ;
  t
