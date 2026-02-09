(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

module Clock = Miaou_interfaces.Clock

(* State *)
type t = {idx : int; label : string option; width : int}

let open_centered ?label ?(width = 60) () = {idx = 0; label; width}

let tick t = {t with idx = t.idx + 1}

let set_label t lbl = {t with label = lbl}

let frames_unicode = [|"⠋"; "⠙"; "⠹"; "⠸"; "⠼"; "⠴"; "⠦"; "⠧"; "⠇"; "⠏"|]

let frames_ascii = [|"|"; "/"; "-"; "\\"|]

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

let render_with_backend backend t =
  let frames =
    if Miaou_widgets_display.Widgets.prefer_ascii ~backend () then frames_ascii
    else frames_unicode
  in
  let frame_count = Array.length frames in
  let glyph = frames.(frame_index t frame_count) in
  let label = match t.label with None -> "" | Some s -> " " ^ s in
  let content = Printf.sprintf "%s%s" glyph label in
  let v = Miaou_helpers.Helpers.visible_chars_count content in
  if v <= t.width then content
  else
    let idx = Miaou_helpers.Helpers.visible_byte_index_of_pos content t.width in
    String.sub content 0 idx

let render
    ?(backend : Miaou_widgets_display.Widgets.backend =
      Miaou_widgets_display.Widgets.get_backend ()) t =
  render_with_backend backend t
