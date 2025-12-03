(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)
type t = {
  left : string;
  right : string;
  left_ratio : float; (* fraction of width for left pane, between 0.0 and 1.0 *)
}

let create ?(left_ratio = 0.5) ~left ~right () = {left; right; left_ratio}

let set_left t s = {t with left = s}

let set_right t s = {t with right = s}

(* Preserve ANSI escape sequences and UTF-8 visible widths when padding or
	 trimming. Uses helpers so we don't cut escape sequences and we always append
	 a reset when truncating to avoid background color bleed into adjacent text. *)
let pad_or_trim s w =
  let module H = Miaou_helpers.Helpers in
  let vis = H.visible_chars_count s in
  if vis = w then s
  else if vis < w then
    (* Pad by inserting spaces before trailing reset if present. *)
    let rec build acc =
      if H.visible_chars_count acc >= w then acc
      else build (H.insert_before_reset acc " ")
    in
    build s
  else
    (* Truncate at visible character boundary to avoid chopping UTF-8 or ANSI
			 sequences. Ensure we append a reset sequence if the truncation removed
			 the trailing reset so coloring does not leak to the right pane. *)
    let byte_idx = H.visible_byte_index_of_pos s w in
    let trunc = String.sub s 0 byte_idx in
    if H.has_trailing_reset trunc then trunc else trunc ^ "\027[0m"

let split_lines s =
  let len = String.length s in
  if len = 0 then []
  else
    let rec loop acc i last =
      if i >= len then List.rev (String.sub s last (len - last) :: acc)
      else if s.[i] = '\n' then
        let part = String.sub s last (i - last) in
        loop (part :: acc) (i + 1) (i + 1)
      else loop acc (i + 1) last
    in
    loop [] 0 0

let render t width =
  let left_w = max 0 (int_of_float (float width *. t.left_ratio)) in
  let right_w = max 0 (width - left_w - 1) in
  let left_lines = split_lines t.left in
  let right_lines = split_lines t.right in
  let max_lines = max (List.length left_lines) (List.length right_lines) in
  let nth_or_empty l i = if i < List.length l then List.nth l i else "" in
  let lines =
    List.init max_lines (fun i ->
        let l = pad_or_trim (nth_or_empty left_lines i) left_w in
        let r = pad_or_trim (nth_or_empty right_lines i) right_w in
        String.concat "" [l; " "; r])
  in
  String.concat "\n" lines
