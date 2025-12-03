(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)
(* Spinner frames; classic braille variant. *)
let frames = [|"⠋"; "⠙"; "⠹"; "⠸"; "⠼"; "⠴"; "⠦"; "⠧"; "⠇"; "⠏"|]

let clamp n x = if x < 0 then 0 else if x >= n then n - 1 else x

(* State *)
type t = {idx : int; label : string option; width : int}

let open_centered ?label ?(width = 60) () = {idx = 0; label; width}

let tick t = {t with idx = (t.idx + 1) mod Array.length frames}

let set_label t lbl = {t with label = lbl}

let render t =
  let glyph = frames.(clamp (Array.length frames) t.idx) in
  let label = match t.label with None -> "" | Some s -> " " ^ s in
  let content = Printf.sprintf "%s%s" glyph label in
  (* Clip to width if needed. *)
  let v = Miaou_helpers.Helpers.visible_chars_count content in
  if v <= t.width then content
  else
    let idx =
      Miaou_helpers.Helpers.visible_byte_index_of_pos content t.width
    in
    String.sub content 0 idx
