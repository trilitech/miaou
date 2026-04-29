(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(* Decode coastline.bin as produced by scripts/build_coastline.py.

   Format (little-endian):
     u32  num_segments
     repeat num_segments times:
       u16  num_points
       repeat num_points times:
         i16  lat * 10
         i16  lon * 10
*)

type segment = (float * float) array

let blob = [%blob "data/coastline.bin"]

let parse (b : string) : segment array =
  let bs = Bytes.of_string b in
  let len = Bytes.length bs in
  let num_segments = Bytes.get_int32_le bs 0 |> Int32.to_int in
  let segments = Array.make num_segments [||] in
  let off = ref 4 in
  for i = 0 to num_segments - 1 do
    if !off + 2 > len then
      failwith
        (Printf.sprintf "coastline: truncated at segment %d (off=%d)" i !off) ;
    let n_pts = Bytes.get_uint16_le bs !off in
    off := !off + 2 ;
    let pts = Array.make n_pts (0.0, 0.0) in
    for j = 0 to n_pts - 1 do
      let lat = Bytes.get_int16_le bs !off in
      let lon = Bytes.get_int16_le bs (!off + 2) in
      pts.(j) <- (float_of_int lat /. 10.0, float_of_int lon /. 10.0) ;
      off := !off + 4
    done ;
    segments.(i) <- pts
  done ;
  segments

let segments : segment array Lazy.t = lazy (parse blob)

(* Flatten all segments into a point cloud — convenient for the globe widget,
   which doesn't draw segment lines (each point is rendered as a single dot). *)
let points : (float * float) array Lazy.t =
  lazy
    (let segs = Lazy.force segments in
     let total = Array.fold_left (fun acc s -> acc + Array.length s) 0 segs in
     let out = Array.make total (0.0, 0.0) in
     let i = ref 0 in
     Array.iter
       (fun seg ->
         Array.iter
           (fun pt ->
             out.(!i) <- pt ;
             incr i)
           seg)
       segs ;
     out)
