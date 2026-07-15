open Alcotest
module WS = Miaou_driver_web.Web_websocket

(* Pure-parts coverage of the RFC 6455 WebSocket handshake and framing: the
   known-answer accept-key derivation, a text-frame roundtrip, a masked
   client frame, ping->pong, and close — all driven through in-memory Eio
   buffers ([Eio.Buf_read.of_string] for reads, a [Buffer.t] standing in
   for the socket write side), no real network or [Eio_main] scheduler
   needed. *)

let capture_write () =
  let buf = Buffer.create 256 in
  ((fun s -> Buffer.add_string buf s), buf)

(* --- Test-local client-frame builder: client frames must be masked per
   RFC 6455 6.1; the module only ever emits unmasked (server) frames via
   its private [build_frame], so a masked frame must be constructed here to
   exercise the read side realistically. *)
let mask_key = "\x12\x34\x56\x78"

let build_client_frame ~opcode payload =
  let len = String.length payload in
  let buf = Buffer.create (len + 10) in
  Buffer.add_uint8 buf (0x80 lor opcode) ;
  let mask_bit = 0x80 in
  if len < 126 then Buffer.add_uint8 buf (mask_bit lor len)
  else begin
    Buffer.add_uint8 buf (mask_bit lor 126) ;
    Buffer.add_uint16_be buf len
  end ;
  Buffer.add_string buf mask_key ;
  String.iteri
    (fun i c ->
      let m = Char.code mask_key.[i mod 4] in
      Buffer.add_char buf (Char.chr (Char.code c lxor m)))
    payload ;
  Buffer.contents buf

(* Decode one *server* (unmasked) frame, as written by [WS.send_text] /
   [WS.upgrade]'s ping/pong/close replies, from a captured byte string.
   Returns (opcode, payload, rest). *)
let decode_server_frame s =
  let b0 = Char.code s.[0] in
  let opcode = b0 land 0x0F in
  let b1 = Char.code s.[1] in
  let len, hdr_len =
    if b1 < 126 then (b1, 2)
    else
      let hi = Char.code s.[2] and lo = Char.code s.[3] in
      ((hi * 256) + lo, 4)
  in
  let payload = String.sub s hdr_len len in
  let rest = String.sub s (hdr_len + len) (String.length s - hdr_len - len) in
  (opcode, payload, rest)

let opcode_text = 0x1

let opcode_close = 0x8

let opcode_ping = 0x9

let opcode_pong = 0xA

let test_accept_key_known_answer () =
  (* RFC 6455 section 1.3's worked example. *)
  let headers = Hashtbl.create 4 in
  Hashtbl.replace headers "upgrade" "websocket" ;
  Hashtbl.replace headers "sec-websocket-key" "dGhlIHNhbXBsZSBub25jZQ==" ;
  let write, buf = capture_write () in
  match WS.upgrade headers ~write with
  | None -> fail "expected the upgrade to succeed"
  | Some _ws ->
      let response = Buffer.contents buf in
      check
        bool
        "response is a 101 Switching Protocols"
        true
        (Test_helpers.contains_substring response "101 Switching Protocols") ;
      check
        bool
        "response carries the RFC 6455 known-answer accept key"
        true
        (Test_helpers.contains_substring
           response
           "Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=")

let test_upgrade_rejects_non_websocket_requests () =
  let headers = Hashtbl.create 4 in
  Hashtbl.replace headers "sec-websocket-key" "dGhlIHNhbXBsZSBub25jZQ==" ;
  let write, _buf = capture_write () in
  check
    bool
    "upgrade without an Upgrade: websocket header is rejected"
    true
    (WS.upgrade headers ~write = None)

let test_upgrade_rejects_missing_key () =
  let headers = Hashtbl.create 4 in
  Hashtbl.replace headers "upgrade" "websocket" ;
  let write, _buf = capture_write () in
  check
    bool
    "upgrade without Sec-WebSocket-Key is rejected"
    true
    (WS.upgrade headers ~write = None)

let upgraded_ws () =
  let headers = Hashtbl.create 4 in
  Hashtbl.replace headers "upgrade" "websocket" ;
  Hashtbl.replace headers "sec-websocket-key" "dGhlIHNhbXBsZSBub25jZQ==" ;
  let write, buf = capture_write () in
  Buffer.clear buf ;
  (* discard the handshake response from the capture buffer *)
  match WS.upgrade headers ~write with
  | Some ws ->
      Buffer.clear buf ;
      (ws, buf)
  | None -> fail "expected upgrade to succeed in test setup"

let test_send_text_frame_roundtrip () =
  let ws, buf = upgraded_ws () in
  WS.send_text ws "hello world" ;
  let opcode, payload, _rest = decode_server_frame (Buffer.contents buf) in
  check int "send_text uses the text opcode" opcode_text opcode ;
  check string "payload roundtrips" "hello world" payload

let test_recv_text_decodes_a_masked_client_frame () =
  let ws, _buf = upgraded_ws () in
  let frame = build_client_frame ~opcode:opcode_text "ping from client" in
  let br = Eio.Buf_read.of_string frame in
  match WS.recv_text ws br with
  | Some msg ->
      check
        string
        "recv_text unmasks and decodes the client payload"
        "ping from client"
        msg
  | None -> fail "expected Some payload"

let test_recv_text_responds_to_ping_with_pong () =
  let ws, buf = upgraded_ws () in
  let ping = build_client_frame ~opcode:opcode_ping "keepalive" in
  (* Ping is auto-handled; recv_text keeps reading until an actual text
     frame or EOF, so append a text frame after it to observe the result
     of a single call. *)
  let text = build_client_frame ~opcode:opcode_text "after ping" in
  let br = Eio.Buf_read.of_string (ping ^ text) in
  (match WS.recv_text ws br with
  | Some msg ->
      check
        string
        "text frame after the ping is still delivered"
        "after ping"
        msg
  | None -> fail "expected the text frame after the ping to be delivered") ;
  let opcode, payload, _rest = decode_server_frame (Buffer.contents buf) in
  check
    int
    "a pong frame was written in response to the ping"
    opcode_pong
    opcode ;
  check string "the pong payload echoes the ping payload" "keepalive" payload

let test_recv_text_handles_close () =
  let ws, buf = upgraded_ws () in
  let close_frame = build_client_frame ~opcode:opcode_close "" in
  let br = Eio.Buf_read.of_string close_frame in
  check
    (option string)
    "recv_text returns None on a close frame"
    None
    (WS.recv_text ws br) ;
  check
    bool
    "is_closed becomes true after receiving a close frame"
    true
    (WS.is_closed ws) ;
  let opcode, _payload, _rest = decode_server_frame (Buffer.contents buf) in
  check int "a close frame is echoed back" opcode_close opcode

let test_close_marks_closed_and_suppresses_further_sends () =
  let ws, buf = upgraded_ws () in
  check bool "not closed before close" false (WS.is_closed ws) ;
  WS.close ws ;
  check bool "closed after close" true (WS.is_closed ws) ;
  Buffer.clear buf ;
  WS.send_text ws "should be dropped" ;
  check int "send_text after close writes nothing" 0 (Buffer.length buf)

let () =
  run
    "web_websocket"
    [
      ( "handshake",
        [
          test_case
            "accept key: RFC 6455 known-answer"
            `Quick
            test_accept_key_known_answer;
          test_case
            "upgrade rejects non-websocket requests"
            `Quick
            test_upgrade_rejects_non_websocket_requests;
          test_case
            "upgrade rejects a missing key"
            `Quick
            test_upgrade_rejects_missing_key;
        ] );
      ( "framing",
        [
          test_case
            "send_text frame roundtrip"
            `Quick
            test_send_text_frame_roundtrip;
          test_case
            "recv_text decodes a masked client frame"
            `Quick
            test_recv_text_decodes_a_masked_client_frame;
          test_case
            "recv_text responds to ping with pong"
            `Quick
            test_recv_text_responds_to_ping_with_pong;
          test_case
            "recv_text handles a close frame"
            `Quick
            test_recv_text_handles_close;
          test_case
            "close marks closed and suppresses further sends"
            `Quick
            test_close_marks_closed_and_suppresses_further_sends;
        ] );
    ]
