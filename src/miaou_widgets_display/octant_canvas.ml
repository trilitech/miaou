(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Mathias Bourgoin <mathias.bourgoin@atacama.tech>        *)
(*                                                                            *)
(******************************************************************************)

(* Octant canvas using Unicode 16 block octant characters (U+1CD00 range).
   Mirrors braille_canvas.ml but uses row-major bit ordering and per-cell
   fg color for richer rendering.

   Bit layout (row-major, matching Unicode 16 octant naming convention):
     bit 0 (0x01): (row 0, col 0)   bit 1 (0x02): (row 0, col 1)
     bit 2 (0x04): (row 1, col 0)   bit 3 (0x08): (row 1, col 1)
     bit 4 (0x10): (row 2, col 0)   bit 5 (0x20): (row 2, col 1)
     bit 6 (0x40): (row 3, col 0)   bit 7 (0x80): (row 3, col 1)

   Unicode 16 base: U+1CD00 (Symbols for Legacy Computing Supplement).
   Mapping: codepoint = U+1CD00 + bit_pattern (for pattern 1..254).
   Pattern 0x00 → space, pattern 0xFF → U+2588 FULL BLOCK (already in Unicode). *)

let octant_base = 0x1CD00

(* Encode a codepoint >= U+10000 to 4-byte UTF-8 *)
let encode_cp4 cp =
  String.init 4 (fun i ->
      match i with
      | 0 -> Char.chr (0xF0 lor (cp lsr 18))
      | 1 -> Char.chr (0x80 lor ((cp lsr 12) land 0x3F))
      | 2 -> Char.chr (0x80 lor ((cp lsr 6) land 0x3F))
      | _ -> Char.chr (0x80 lor (cp land 0x3F)))

(* Precompute UTF-8 glyphs for all 256 octant patterns.
   U+2588 FULL BLOCK in UTF-8: E2 96 88 *)
let octant_glyphs : string array =
  Array.init 256 (fun pattern ->
      match pattern with
      | 0 -> " "
      | 0xFF -> "\xE2\x96\x88"
      | p -> encode_cp4 (octant_base + p))

(* Map dot position within a 2×4 cell to its bitmask (row-major) *)
let dot_to_bit ~dot_x ~dot_y =
  match (dot_y, dot_x) with
  | 0, 0 -> 0x01
  | 0, 1 -> 0x02
  | 1, 0 -> 0x04
  | 1, 1 -> 0x08
  | 2, 0 -> 0x10
  | 2, 1 -> 0x20
  | 3, 0 -> 0x40
  | 3, 1 -> 0x80
  | _ -> 0

type t = {
  width : int;
  height : int;
  patterns : int array array; (* [height][width] — 8-bit bitmask per cell *)
  fg : string option array array; (* [height][width] — ANSI SGR fg color *)
}

let create ~width ~height =
  {
    width;
    height;
    patterns = Array.make_matrix height width 0;
    fg = Array.make_matrix height width None;
  }

let get_dimensions t = (t.width, t.height)

let get_dot_dimensions t = (t.width * 2, t.height * 4)

let set_dot t ~x ~y ~color =
  if x >= 0 && y >= 0 then
    let cell_x = x / 2 in
    let cell_y = y / 4 in
    if cell_y < t.height && cell_x < t.width then begin
      let dot_x = x mod 2 in
      let dot_y = y mod 4 in
      let bit = dot_to_bit ~dot_x ~dot_y in
      t.patterns.(cell_y).(cell_x) <- t.patterns.(cell_y).(cell_x) lor bit ;
      (* Update fg color when a color is provided *)
      match color with
      | Some _ -> t.fg.(cell_y).(cell_x) <- color
      | None -> ()
    end

let clear_dot t ~x ~y =
  if x >= 0 && y >= 0 then
    let cell_x = x / 2 in
    let cell_y = y / 4 in
    if cell_y < t.height && cell_x < t.width then begin
      let dot_x = x mod 2 in
      let dot_y = y mod 4 in
      let bit = dot_to_bit ~dot_x ~dot_y in
      t.patterns.(cell_y).(cell_x) <- t.patterns.(cell_y).(cell_x) land lnot bit
    end

let get_dot t ~x ~y =
  if x >= 0 && y >= 0 then
    let cell_x = x / 2 in
    let cell_y = y / 4 in
    if cell_y < t.height && cell_x < t.width then
      let dot_x = x mod 2 in
      let dot_y = y mod 4 in
      let bit = dot_to_bit ~dot_x ~dot_y in
      t.patterns.(cell_y).(cell_x) land bit <> 0
    else false
  else false

let clear t =
  for y = 0 to t.height - 1 do
    for x = 0 to t.width - 1 do
      t.patterns.(y).(x) <- 0 ;
      t.fg.(y).(x) <- None
    done
  done

let draw_line t ~x0 ~y0 ~x1 ~y1 ~color =
  let dx = abs (x1 - x0) in
  let dy = abs (y1 - y0) in
  let sx = if x0 < x1 then 1 else -1 in
  let sy = if y0 < y1 then 1 else -1 in
  let rec loop x y err =
    set_dot t ~x ~y ~color ;
    if x = x1 && y = y1 then ()
    else
      let e2 = 2 * err in
      let x', err' = if e2 > -dy then (x + sx, err - dy) else (x, err) in
      let y', err'' = if e2 < dx then (y + sy, err' + dx) else (y, err') in
      loop x' y' err''
  in
  loop x0 y0 (dx - dy)

let add_cell_bits t ~cell_x ~cell_y ~bits ~color =
  if cell_x >= 0 && cell_x < t.width && cell_y >= 0 && cell_y < t.height then begin
    t.patterns.(cell_y).(cell_x) <- t.patterns.(cell_y).(cell_x) lor bits ;
    match color with Some _ -> t.fg.(cell_y).(cell_x) <- color | None -> ()
  end

let render t =
  let ansi_reset = "\027[0m" in
  (* Estimate: each cell ~20 bytes (ANSI codes + UTF-8 char) + newlines *)
  let buf = Buffer.create (t.height * ((t.width * 20) + 1)) in
  for y = 0 to t.height - 1 do
    if y > 0 then Buffer.add_char buf '\n' ;
    for x = 0 to t.width - 1 do
      let pattern = t.patterns.(y).(x) in
      let glyph = octant_glyphs.(pattern) in
      match t.fg.(y).(x) with
      | None -> Buffer.add_string buf glyph
      | Some color ->
          Buffer.add_string buf (Printf.sprintf "\027[%sm" color) ;
          Buffer.add_string buf glyph ;
          Buffer.add_string buf ansi_reset
    done
  done ;
  Buffer.contents buf

let glyph_of_pattern pattern = octant_glyphs.(pattern land 0xFF)

[@@@enforce_exempt] (* non-widget module *)
