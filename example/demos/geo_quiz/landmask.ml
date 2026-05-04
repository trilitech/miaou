(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(* Decoded land/sea bitmap derived from Natural Earth ne_50m_land at
   1°-per-2-pixel resolution (720×360). One bit per pixel, MSB-first. *)

let raw = [%blob "data/landmask.bin"]

type t = {width : int; height : int; bits : Bytes.t}

let mask =
  lazy
    (let w = Char.code raw.[0] lor (Char.code raw.[1] lsl 8) in
     let h = Char.code raw.[2] lor (Char.code raw.[3] lsl 8) in
     let n = ((w * h) + 7) / 8 in
     let bits = Bytes.create n in
     Bytes.blit_string raw 4 bits 0 n ;
     {width = w; height = h; bits})

let is_land ~lat ~lon =
  let m = Lazy.force mask in
  let lon = mod_float (lon +. 540.0) 360.0 -. 180.0 in
  let col = int_of_float ((lon +. 180.0) /. 360.0 *. float_of_int m.width) in
  let col =
    if col < 0 then 0 else if col >= m.width then m.width - 1 else col
  in
  let row = int_of_float ((90.0 -. lat) /. 180.0 *. float_of_int m.height) in
  let row =
    if row < 0 then 0 else if row >= m.height then m.height - 1 else row
  in
  let idx = (row * m.width) + col in
  let byte = Char.code (Bytes.unsafe_get m.bits (idx lsr 3)) in
  byte land (0x80 lsr (idx land 7)) <> 0
