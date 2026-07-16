(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

let session_prefix = "/s/"

let strip_session_prefix ~token path =
  let plen = String.length session_prefix in
  if String.length path < plen || String.sub path 0 plen <> session_prefix then
    None
  else
    let rest = String.sub path plen (String.length path - plen) in
    let candidate, tail =
      match String.index_opt rest '/' with
      | Some i ->
          (String.sub rest 0 i, String.sub rest i (String.length rest - i))
      | None -> (rest, "/")
    in
    if Serve_token.matches token ~candidate then Some tail else None

let respond conn ~status body =
  let headers =
    Printf.sprintf
      "HTTP/1.1 %s\r\n\
       Content-Type: text/plain\r\n\
       Content-Length: %d\r\n\
       Connection: close\r\n\
       \r\n"
      status
      (String.length body)
  in
  try Eio.Flow.copy_string (headers ^ body) conn with _ -> ()

let respond_400 conn = respond conn ~status:"400 Bad Request" "Bad Request"

let respond_403 conn = respond conn ~status:"403 Forbidden" "Forbidden"

let respond_502 conn = respond conn ~status:"502 Bad Gateway" "Bad Gateway"

(* Parse "METHOD /uri HTTP/x.y" (Eio.Buf_read.line keeps a trailing '\r'
   if present, so trim before splitting). *)
let parse_request_line line =
  match String.split_on_char ' ' (String.trim line) with
  | [meth; uri; version] -> Some (meth, uri, version)
  | _ -> None

let split_query uri =
  match String.index_opt uri '?' with
  | Some i ->
      ( String.sub uri 0 i,
        Some (String.sub uri (i + 1) (String.length uri - i - 1)) )
  | None -> (uri, None)

(* Read raw header lines (as they appeared on the wire, including any
   trailing '\r') up to and including the blank terminator line. Returned
   list excludes the terminator itself. *)
let read_header_lines br =
  let rec loop acc =
    let line = Eio.Buf_read.line br in
    if String.length line = 0 || line = "\r" then List.rev acc
    else loop (line :: acc)
  in
  loop []

let rec connect_worker ~sw ~net ~clock ~socket_path ~retries ~delay =
  match Eio.Net.connect ~sw net (`Unix socket_path) with
  | conn -> Some conn
  | exception (Eio.Io _ | Unix.Unix_error _) ->
      if retries <= 0 then None
      else begin
        Eio.Time.sleep clock delay ;
        connect_worker
          ~sw
          ~net
          ~clock
          ~socket_path
          ~retries:(retries - 1)
          ~delay
      end

let proxy_bytes conn worker_conn =
  Eio.Fiber.first
    (fun () -> try Eio.Flow.copy conn worker_conn with _ -> ())
    (fun () -> try Eio.Flow.copy worker_conn conn with _ -> ()) ;
  try Eio.Flow.close worker_conn with _ -> ()

let handle_connection ~sw ~env ~token ~worker_socket_path ~conn =
  try
    let br = Eio.Buf_read.of_flow ~max_size:(1024 * 1024) conn in
    let request_line = Eio.Buf_read.line br in
    match parse_request_line request_line with
    | None -> respond_400 conn
    | Some (meth, uri, version) -> (
        let path, query = split_query uri in
        match strip_session_prefix ~token path with
        | None -> respond_403 conn
        | Some tail -> (
            let header_lines = read_header_lines br in
            (* Any bytes already pulled into [br]'s internal buffer beyond
               the head (e.g. pipelined bytes arriving in the same TCP
               segment) must be replayed verbatim — they belong to the
               worker, not to us, and were never meant to be parsed here. *)
            let residue = Eio.Buf_read.peek br in
            let residue_str = Cstruct.to_string residue in
            Eio.Buf_read.consume br (Cstruct.length residue) ;
            match
              connect_worker
                ~sw
                ~net:env#net
                ~clock:env#clock
                ~socket_path:worker_socket_path
                ~retries:20
                ~delay:0.05
            with
            | None -> respond_502 conn
            | Some worker_conn ->
                let new_uri =
                  match query with Some q -> tail ^ "?" ^ q | None -> tail
                in
                let head = Printf.sprintf "%s %s %s\r\n" meth new_uri version in
                let headers_block =
                  String.concat "" (List.map (fun l -> l ^ "\r\n") header_lines)
                in
                Eio.Flow.copy_string
                  (head ^ headers_block ^ "\r\n" ^ residue_str)
                  worker_conn ;
                proxy_bytes conn worker_conn))
  with exn -> (
    Printf.eprintf
      "[miaou serve proxy] connection error: %s\n%!"
      (Printexc.to_string exn) ;
    try Eio.Flow.close conn with _ -> ())
