(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(* Decode cities.bin as produced by scripts/build_cities.py.

   Format (little-endian):
     u32 num_cities
     repeat:
       u8  tier        (1..5; lowest tier where this city qualifies)
       u8  is_capital
       i32 population
       f32 lat
       f32 lon
       u16 name_len ; bytes name (utf-8)
       u16 country_len ; bytes country (utf-8)
*)

type city = {
  name : string;
  country : string;
  lat : float;
  lon : float;
  population : int;
  tier : int;
  is_capital : bool;
}

let blob = [%blob "data/cities.bin"]

let parse (b : string) : city array =
  let bs = Bytes.of_string b in
  let total_len = Bytes.length bs in
  let num = Bytes.get_int32_le bs 0 |> Int32.to_int in
  let cities =
    Array.make
      num
      {
        name = "";
        country = "";
        lat = 0.0;
        lon = 0.0;
        population = 0;
        tier = 0;
        is_capital = false;
      }
  in
  let off = ref 4 in
  for i = 0 to num - 1 do
    if !off + 14 > total_len then
      failwith (Printf.sprintf "cities: truncated header at %d (off=%d)" i !off) ;
    let tier = Bytes.get_uint8 bs !off in
    let is_capital = Bytes.get_uint8 bs (!off + 1) = 1 in
    let population = Bytes.get_int32_le bs (!off + 2) |> Int32.to_int in
    let lat = Bytes.get_int32_le bs (!off + 6) |> Int32.float_of_bits in
    let lon = Bytes.get_int32_le bs (!off + 10) |> Int32.float_of_bits in
    off := !off + 14 ;
    let name_len = Bytes.get_uint16_le bs !off in
    off := !off + 2 ;
    let name = Bytes.sub_string bs !off name_len in
    off := !off + name_len ;
    let country_len = Bytes.get_uint16_le bs !off in
    off := !off + 2 ;
    let country = Bytes.sub_string bs !off country_len in
    off := !off + country_len ;
    cities.(i) <- {name; country; lat; lon; population; tier; is_capital}
  done ;
  cities

let all : city array Lazy.t = lazy (parse blob)

(* For tier T, return all cities with city.tier <= T (i.e. cities qualifying
   for an easier or equal tier). *)
let pool ~tier =
  let all = Lazy.force all in
  Array.of_list
    (Array.fold_left
       (fun acc c -> if c.tier <= tier then c :: acc else acc)
       []
       all)

let tier_label = function
  | 1 -> "Easy"
  | 2 -> "Normal"
  | 3 -> "Hard"
  | 4 -> "Expert"
  | 5 -> "Master"
  | _ -> "?"

let tier_description = function
  | 1 -> "Capitals of the largest countries"
  | 2 -> "All capitals"
  | 3 -> "Capitals + cities >1M"
  | 4 -> "Cities >100K"
  | 5 -> "Cities >15K (everything)"
  | _ -> ""
