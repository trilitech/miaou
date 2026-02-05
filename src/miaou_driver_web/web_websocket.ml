(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(** Minimal WebSocket (RFC 6455) implementation for Eio.

    Uses direct flow writes instead of Buf_write to avoid buffering issues
    with the WebSocket protocol upgrade. *)

type t = {mutable closed : bool; write : string -> unit}

let websocket_magic = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

let accept_key client_key =
  let open Digestif in
  let hash = SHA1.digest_string (client_key ^ websocket_magic) in
  Base64.encode_exn (SHA1.to_raw_string hash)

(* Parse HTTP headers from buf_read until blank line *)
let parse_headers br =
  let headers = Hashtbl.create 16 in
  let rec loop () =
    let line = Eio.Buf_read.line br in
    if String.length line = 0 || line = "\r" then headers
    else
      match String.index_opt line ':' with
      | Some i ->
          let key =
            String.lowercase_ascii (String.trim (String.sub line 0 i))
          in
          let value =
            String.trim (String.sub line (i + 1) (String.length line - i - 1))
          in
          Hashtbl.replace headers key value ;
          loop ()
      | None -> loop ()
  in
  loop ()

let upgrade headers ~write =
  let is_upgrade =
    match Hashtbl.find_opt headers "upgrade" with
    | Some v -> String.lowercase_ascii v = "websocket"
    | None -> false
  in
  let ws_key = Hashtbl.find_opt headers "sec-websocket-key" in
  match (is_upgrade, ws_key) with
  | true, Some key ->
      let accept = accept_key key in
      let response =
        Printf.sprintf
          "HTTP/1.1 101 Switching Protocols\r\n\
           Upgrade: websocket\r\n\
           Connection: Upgrade\r\n\
           Sec-WebSocket-Accept: %s\r\n\
           \r\n"
          accept
      in
      write response ;
      Some {closed = false; write}
  | _ -> None

(* WebSocket frame opcodes *)
let _opcode_continuation = 0x0

let opcode_text = 0x1

let _opcode_binary = 0x2

let opcode_close = 0x8

let opcode_ping = 0x9

let opcode_pong = 0xA

(* Build a WebSocket frame as a string (server frames are NOT masked) *)
let build_frame ~opcode payload =
  let len = String.length payload in
  let buf = Buffer.create (len + 10) in
  (* FIN bit + opcode *)
  Buffer.add_uint8 buf (0x80 lor opcode) ;
  (* Payload length (no mask bit for server) *)
  if len < 126 then Buffer.add_uint8 buf len
  else if len < 65536 then begin
    Buffer.add_uint8 buf 126 ;
    Buffer.add_uint16_be buf len
  end
  else begin
    Buffer.add_uint8 buf 127 ;
    (* Write 64-bit length *)
    Buffer.add_int32_be buf 0l ;
    Buffer.add_int32_be buf (Int32.of_int len)
  end ;
  if len > 0 then Buffer.add_string buf payload ;
  Buffer.contents buf

let write_frame t ~opcode payload = t.write (build_frame ~opcode payload)

(* Read a WebSocket frame, returns (opcode, payload) *)
let read_frame br =
  let b0 = Eio.Buf_read.uint8 br in
  let _fin = b0 land 0x80 <> 0 in
  let opcode = b0 land 0x0F in
  let b1 = Eio.Buf_read.uint8 br in
  let masked = b1 land 0x80 <> 0 in
  let len = b1 land 0x7F in
  let len =
    if len = 126 then Eio.Buf_read.BE.uint16 br
    else if len = 127 then
      let _high = Eio.Buf_read.BE.uint32 br in
      Int32.to_int (Eio.Buf_read.BE.uint32 br)
    else len
  in
  let mask_key = if masked then Some (Eio.Buf_read.take 4 br) else None in
  let payload = Eio.Buf_read.take len br in
  let payload =
    match mask_key with
    | None -> payload
    | Some mask ->
        let buf = Bytes.of_string payload in
        for i = 0 to Bytes.length buf - 1 do
          let b = Bytes.get_uint8 buf i in
          let m = Char.code mask.[i mod 4] in
          Bytes.set_uint8 buf i (b lxor m)
        done ;
        Bytes.to_string buf
  in
  (opcode, payload)

let send_text t msg = if not t.closed then write_frame t ~opcode:opcode_text msg

let rec recv_text t br =
  if t.closed then None
  else
    match read_frame br with
    | exception End_of_file ->
        t.closed <- true ;
        None
    | exception Eio.Io _ ->
        t.closed <- true ;
        None
    | opcode, _payload when opcode = opcode_close ->
        t.closed <- true ;
        (* Send close frame back *)
        (try write_frame t ~opcode:opcode_close "" with _ -> ()) ;
        None
    | opcode, payload when opcode = opcode_ping ->
        (* Respond with pong *)
        (try write_frame t ~opcode:opcode_pong payload with _ -> ()) ;
        recv_text t br
    | opcode, _payload when opcode = opcode_pong ->
        (* Ignore pong *)
        recv_text t br
    | _opcode, payload -> Some payload

let close t =
  if not t.closed then begin
    t.closed <- true ;
    try write_frame t ~opcode:opcode_close "" with _ -> ()
  end

let is_closed t = t.closed
