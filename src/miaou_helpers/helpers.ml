(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

let is_utf8_lead b = Char.code b land 0xC0 <> 0x80

(* Check if s[i] starts a CSI sequence (ESC [ ...). *)
let is_esc_start s i =
  i + 1 < String.length s && s.[i] = '\027' && s.[i + 1] = '['

(* Check if s[i] starts an OSC sequence (ESC ] ...). *)
let is_osc_start s i =
  i + 1 < String.length s && s.[i] = '\027' && s.[i + 1] = ']'

(* Skip characters until 'm' (SGR terminator) is found. *)
let rec skip_ansi_until_m s i =
  if i >= String.length s then i
  else if s.[i] = 'm' then i + 1
  else skip_ansi_until_m s (i + 1)

(* Skip characters until String Terminator (ESC \ or \x9c) is found.
   Used for OSC sequences like OSC 8 hyperlinks. *)
let rec skip_osc_until_st s i =
  let len = String.length s in
  if i >= len then i
  else if s.[i] = '\x9c' then i + 1
  else if s.[i] = '\027' && i + 1 < len && s.[i + 1] = '\\' then i + 2
  else skip_osc_until_st s (i + 1)

let utf8_decode s i =
  let len = String.length s in
  if i >= len then (0, i + 1)
  else
    let byte = Char.code s.[i] in
    if byte land 0x80 = 0 then (byte, i + 1)
    else if byte land 0xE0 = 0xC0 && i + 1 < len then
      let b1 = Char.code s.[i + 1] land 0x3F in
      (((byte land 0x1F) lsl 6) lor b1, i + 2)
    else if byte land 0xF0 = 0xE0 && i + 2 < len then
      let b1 = Char.code s.[i + 1] land 0x3F in
      let b2 = Char.code s.[i + 2] land 0x3F in
      (((byte land 0x0F) lsl 12) lor (b1 lsl 6) lor b2, i + 3)
    else if byte land 0xF8 = 0xF0 && i + 3 < len then
      let b1 = Char.code s.[i + 1] land 0x3F in
      let b2 = Char.code s.[i + 2] land 0x3F in
      let b3 = Char.code s.[i + 3] land 0x3F in
      (((byte land 0x07) lsl 18) lor (b1 lsl 12) lor (b2 lsl 6) lor b3, i + 4)
    else (byte, i + 1)

let is_wide cp =
  (cp >= 0x1100 && cp <= 0x115F)
  || (cp >= 0x2329 && cp <= 0x232A)
  || (cp >= 0x2E80 && cp <= 0xA4CF)
  || (cp >= 0xAC00 && cp <= 0xD7A3)
  || (cp >= 0xF900 && cp <= 0xFAFF)
  || (cp >= 0xFE10 && cp <= 0xFE19)
  || (cp >= 0xFE30 && cp <= 0xFE6F)
  || (cp >= 0xFF00 && cp <= 0xFF60)
  || (cp >= 0xFFE0 && cp <= 0xFFE6)
  || (cp >= 0x1F300 && cp <= 0x1F64F)
  || (cp >= 0x1F900 && cp <= 0x1F9FF)
  || (cp >= 0x1FA70 && cp <= 0x1FAFF)
  || (cp >= 0x20000 && cp <= 0x2FFFD)
  || (cp >= 0x30000 && cp <= 0x3FFFD)

let is_zero_width cp =
  cp = 0x200D
  || (cp >= 0xFE00 && cp <= 0xFE0F)
  || (cp >= 0x0300 && cp <= 0x036F)
  || (cp >= 0x1AB0 && cp <= 0x1AFF)
  || (cp >= 0x1DC0 && cp <= 0x1DFF)
  || (cp >= 0x20D0 && cp <= 0x20FF)
  || (cp >= 0xFE20 && cp <= 0xFE2F)

let visible_chars_count s =
  let rec loop i cnt =
    if i >= String.length s then cnt
    else if is_esc_start s i then
      let j = skip_ansi_until_m s (i + 2) in
      loop j cnt
    else if is_osc_start s i then
      let j = skip_osc_until_st s (i + 2) in
      loop j cnt
    else
      let cp, j = utf8_decode s i in
      let w = if is_zero_width cp then 0 else if is_wide cp then 2 else 1 in
      loop j (cnt + w)
  in
  loop 0 0

let visible_byte_index_of_pos s pos =
  let len = String.length s in
  let rec loop i cnt =
    if cnt >= pos then i
    else if i >= len then len
    else if is_esc_start s i then
      let j = skip_ansi_until_m s (i + 2) in
      loop j cnt
    else if is_osc_start s i then
      let j = skip_osc_until_st s (i + 2) in
      loop j cnt
    else
      let cp, j = utf8_decode s i in
      let w = if is_zero_width cp then 0 else if is_wide cp then 2 else 1 in
      if cnt + w > pos then i else loop j (cnt + w)
  in
  loop 0 0

let has_trailing_reset s =
  let l = String.length s in
  l >= 4 && String.sub s (l - 4) 4 = "\027[0m"

let insert_before_reset s tail =
  let l = String.length s in
  if has_trailing_reset s then
    let prefix = String.sub s 0 (l - 4) in
    prefix ^ tail ^ "\027[0m"
  else s ^ tail

let pad_to_width s target_width pad_char =
  let v = visible_chars_count s in
  if v >= target_width then s
  else
    let needed = target_width - v in
    let l = String.length s in
    if has_trailing_reset s then (
      let buf = Buffer.create (l + needed + 4) in
      Buffer.add_substring buf s 0 (l - 4) ;
      for _ = 1 to needed do
        Buffer.add_char buf pad_char
      done ;
      Buffer.add_string buf "\027[0m" ;
      Buffer.contents buf)
    else
      let buf = Buffer.create (l + needed) in
      Buffer.add_string buf s ;
      for _ = 1 to needed do
        Buffer.add_char buf pad_char
      done ;
      Buffer.contents buf

let concat_lines lines =
  match lines with
  | [] -> ""
  | hd :: tl ->
      let buf =
        let est =
          List.fold_left (fun acc l -> acc + String.length l + 1) 0 lines
        in
        Buffer.create est
      in
      Buffer.add_string buf hd ;
      List.iter
        (fun l ->
          Buffer.add_char buf '\n' ;
          Buffer.add_string buf l)
        tl ;
      Buffer.contents buf

let concat_with_sep sep parts =
  match parts with
  | [] -> ""
  | hd :: tl ->
      let buf =
        let est =
          List.fold_left (fun acc p -> acc + String.length p) 0 parts
          + (String.length sep * max 0 (List.length parts - 1))
        in
        Buffer.create est
      in
      Buffer.add_string buf hd ;
      List.iter
        (fun p ->
          Buffer.add_string buf sep ;
          Buffer.add_string buf p)
        tl ;
      Buffer.contents buf
