(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

module Clock = Miaou_interfaces.Clock

(** Spinner style variants *)
type style =
  | Dots  (** Classic braille dot spinner: ⠋ ⠙ ⠹ ⠸ ... *)
  | Block  (** Block cursor spinner: [ ] [▌] [█] [▐] *)

(* State *)
type t = {idx : int; label : string option; width : int; style : style}

let open_centered ?label ?(width = 60) ?(style = Dots) () =
  {idx = 0; label; width; style}

let tick t = {t with idx = t.idx + 1}

let set_label t lbl = {t with label = lbl}

let set_style t style = {t with style}

(* Dots style frames *)
let frames_dots_unicode = [|"⠋"; "⠙"; "⠹"; "⠸"; "⠼"; "⠴"; "⠦"; "⠧"; "⠇"; "⠏"|]

let frames_dots_ascii = [|"|"; "/"; "-"; "\\"|]

(* Block cursor style frames - renders as a box with animated fill *)
let frames_block_unicode = [|" "; "▌"; "█"; "▐"|]

let frames_block_ascii = [|" "; "["; "#"; "]"|]

(* Legacy aliases for backward compatibility *)
let frames_unicode = frames_dots_unicode

let frames_ascii = frames_dots_ascii

(* Frames per second for time-based animation *)
let spinner_fps = 10.0

(** Compute the frame index.  When the Clock capability is available the
    index is derived from elapsed wall-clock time so that the rotation
    speed is consistent regardless of TPS.  Falls back to the
    counter-based [t.idx] otherwise. *)
let frame_index t frame_count =
  match Clock.get () with
  | Some c ->
      let elapsed = c.elapsed () in
      int_of_float (elapsed *. spinner_fps) mod frame_count
  | None -> t.idx mod frame_count

(** Render the block cursor style with a box outline *)
let render_block_glyph ~prefer_ascii frame_idx =
  let frames =
    if prefer_ascii then frames_block_ascii else frames_block_unicode
  in
  let frame_count = Array.length frames in
  let inner = frames.(frame_idx mod frame_count) in
  let tl, tr, bl, br, h, v =
    if prefer_ascii then ("+", "+", "+", "+", "-", "|")
    else ("┌", "┐", "└", "┘", "─", "│")
  in
  let top = tl ^ h ^ tr in
  let mid = v ^ inner ^ v in
  let bot = bl ^ h ^ br in
  String.concat "\n" [top; mid; bot]

let render_with_backend backend t =
  let prefer_ascii = Miaou_widgets_display.Widgets.prefer_ascii ~backend () in
  match t.style with
  | Block ->
      let frame_idx = frame_index t (Array.length frames_block_unicode) in
      let glyph = render_block_glyph ~prefer_ascii frame_idx in
      let label = match t.label with None -> "" | Some s -> "\n" ^ s in
      glyph ^ label
  | Dots ->
      let frames = if prefer_ascii then frames_ascii else frames_unicode in
      let frame_count = Array.length frames in
      let glyph = frames.(frame_index t frame_count) in
      let label = match t.label with None -> "" | Some s -> " " ^ s in
      let content = Printf.sprintf "%s%s" glyph label in
      let v = Miaou_helpers.Helpers.visible_chars_count content in
      if v <= t.width then content
      else
        let idx =
          Miaou_helpers.Helpers.visible_byte_index_of_pos content t.width
        in
        String.sub content 0 idx

let render
    ?(backend : Miaou_widgets_display.Widgets.backend =
      Miaou_widgets_display.Widgets.get_backend ()) t =
  render_with_backend backend t
