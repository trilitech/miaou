(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

type role = Controller | Viewer

type t = {value : string; role : role}

let entropy_bytes = 32

let hex_of_bytes (b : bytes) =
  let buf = Buffer.create (Bytes.length b * 2) in
  Bytes.iter
    (fun c -> Buffer.add_string buf (Printf.sprintf "%02x" (Char.code c)))
    b ;
  Buffer.contents buf

let generate ~env ~role =
  let buf = Cstruct.create entropy_bytes in
  Eio.Flow.read_exact env#secure_random buf ;
  let value = hex_of_bytes (Cstruct.to_bytes buf) in
  {value; role}

let role t = t.role

let to_string t = t.value

let matches t ~candidate = Eqaf.equal t.value candidate
