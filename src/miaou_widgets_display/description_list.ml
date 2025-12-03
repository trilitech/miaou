(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)
open Widgets

type t = {
  title : string option;
  key_width : int option;
  items : (string * string) list;
}

let create ?title ?key_width ?(items = []) () = {title; key_width; items}

let set_items t items = {t with items}

let compute_key_width ?(max_width = 30) items =
  let max_k =
    List.fold_left (fun acc (k, _) -> max acc (visible_chars_count k)) 0 items
  in
  min max_width max_k

let trunc_visible n s =
  let v = visible_chars_count s in
  if v <= n then s
  else
    let byte_idx = visible_byte_index_of_pos s (max 0 (n - 1)) in
    String.sub s 0 byte_idx ^ "…"

let pad s w =
  if visible_chars_count s >= w then trunc_visible w s
  else s ^ String.make (w - visible_chars_count s) ' '

let render t ~focus:_ =
  let key_w =
    match t.key_width with
    | Some w -> w
    | None -> compute_key_width ~max_width:30 t.items
  in
  let lines = List.map (fun (k, v) -> pad k key_w ^ "  " ^ v) t.items in
  match t.title with
  | Some title -> titleize title ^ "\n" ^ String.concat "\n" lines
  | None -> String.concat "\n" lines
