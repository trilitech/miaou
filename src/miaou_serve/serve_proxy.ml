(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

let session_prefix = "/s/"

let split_session_path path =
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
    Some (candidate, tail)

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

let respond_409 conn msg = respond conn ~status:"409 Conflict" msg

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

(* [tail] never carries a query string here: [handle_connection] splits
   the query off the full URI before stripping the [/s/<token>] prefix,
   and reattaches it (unchanged) to whatever tail this module chooses to
   forward — see the [new_uri] construction below. *)
let is_controller_ws_path tail = tail = "/ws"

let rewrite_to_viewer tail = if tail = "/ws" then "/ws/viewer" else tail

(* Resolves [(session, role, tail)] into the worker socket path to
   forward to, and the (possibly rewritten) tail to forward, or an
   outcome that closes [conn] without ever contacting a worker.
   Never raises. *)
let resolve ~sw ~env session role tail :
    [ `Forward of string * string * (unit -> unit)
    | `Refuse_403
    | `Refuse_409 of string
    | `Refuse_502 ] =
  match (role, is_controller_ws_path tail) with
  | Serve_session.Viewer, true ->
      (* FR-032: a viewer-scoped token must never grant controller-role
         attach, checked server-side against the token's role claim, not
         a client-declared field. *)
      `Refuse_403
  | Serve_session.Viewer, false ->
      if not (Serve_session.has_worker session) then
        (* No controller has ever attached to this session: there is no
           worker to view, and a viewer alone must never bring one into
           existence. *)
        `Refuse_409 "No controller connected yet"
      else begin
        match
          Serve_session.ensure_worker
            session
            ~sw
            ~proc_mgr:env#process_mgr
            ~net:env#net
            ~clock:env#clock
        with
        | Ok socket_path -> `Forward (socket_path, tail, fun () -> ())
        | Error Serve_session.Unreachable -> `Refuse_502
      end
  | Serve_session.Controller, _ -> (
      match
        Serve_session.ensure_worker
          session
          ~sw
          ~proc_mgr:env#process_mgr
          ~net:env#net
          ~clock:env#clock
      with
      | Error Serve_session.Unreachable -> `Refuse_502
      | Ok socket_path ->
          if is_controller_ws_path tail then begin
            match Serve_session.controller_attach session with
            | `Attach ->
                `Forward
                  ( socket_path,
                    tail,
                    fun () -> Serve_session.controller_detach session )
            | `Downgrade ->
                `Forward (socket_path, rewrite_to_viewer tail, fun () -> ())
          end
          else `Forward (socket_path, tail, fun () -> ()))

let handle_connection ~sw ~env ~sessions ~conn =
  try
    let br = Eio.Buf_read.of_flow ~max_size:(1024 * 1024) conn in
    let request_line = Eio.Buf_read.line br in
    match parse_request_line request_line with
    | None -> respond_400 conn
    | Some (meth, uri, version) -> (
        let path, query = split_query uri in
        match split_session_path path with
        | None -> respond_403 conn
        | Some (candidate, tail) -> (
            match Serve_session.find sessions ~candidate with
            | None -> respond_403 conn
            | Some (session, role) -> (
                match resolve ~sw ~env session role tail with
                | `Refuse_403 -> respond_403 conn
                | `Refuse_409 msg -> respond_409 conn msg
                | `Refuse_502 -> respond_502 conn
                | `Forward (worker_socket_path, forward_tail, on_close) ->
                    (* [on_close] (a controller detach, or a no-op for a
                       viewer/downgraded connection) MUST run no matter
                       how this branch exits — a 502 from
                       [connect_worker] below, or any exception raised
                       reading the rest of the head — not only the
                       [proxy_bytes] happy path. [controller_attach] (in
                       [resolve], above) already flipped
                       [controller_live] to [true] before this branch was
                       ever reached; failing to pair it with
                       [controller_detach] here would leave that flag
                       stuck [true] forever, permanently downgrading every
                       future controller attach for this session with no
                       recovery (the regression this [Fun.protect] fixes
                       — see [test_serve_multi_session.ml]'s
                       "worker unreachable then fresh controller
                       reattaches" scenario). *)
                    Fun.protect ~finally:on_close (fun () ->
                        let header_lines = read_header_lines br in
                        (* Any bytes already pulled into [br]'s internal
                           buffer beyond the head (e.g. pipelined bytes
                           arriving in the same TCP segment) must be
                           replayed verbatim — they belong to the worker,
                           not to us, and were never meant to be parsed
                           here. *)
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
                              match query with
                              | Some q -> forward_tail ^ "?" ^ q
                              | None -> forward_tail
                            in
                            let head =
                              Printf.sprintf "%s %s %s\r\n" meth new_uri version
                            in
                            let headers_block =
                              String.concat
                                ""
                                (List.map (fun l -> l ^ "\r\n") header_lines)
                            in
                            Eio.Flow.copy_string
                              (head ^ headers_block ^ "\r\n" ^ residue_str)
                              worker_conn ;
                            proxy_bytes conn worker_conn))))
  with exn -> (
    Printf.eprintf
      "[miaou serve proxy] connection error: %s\n%!"
      (Printexc.to_string exn) ;
    try Eio.Flow.close conn with _ -> ())
