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
  | Blocks  (** Animated blocks with gradient: ■ ■ ■ ■ ■ ■ (moving highlight) *)

(** Direction for block animation *)
type direction = Left | Right

(** Glyph style for blocks *)
type glyph = Square | Circle | Dot

(* State *)
type t = {
  idx : int;
  label : string option;
  width : int;
  style : style;
  blocks_count : int;
  direction : direction;
  glyph : glyph;
}

let open_centered ?label ?(width = 60) ?(style = Dots) ?(blocks_count = 5)
    ?(direction = Right) ?(glyph = Square) () =
  {
    idx = 0;
    label;
    width;
    style;
    blocks_count = max 2 blocks_count;
    direction;
    glyph;
  }

let tick t = {t with idx = t.idx + 1}

let set_label t lbl = {t with label = lbl}

let set_style t style = {t with style}

(* Dots style frames *)
let frames_dots_unicode = [|"⠋"; "⠙"; "⠹"; "⠸"; "⠼"; "⠴"; "⠦"; "⠧"; "⠇"; "⠏"|]

let frames_dots_ascii = [|"|"; "/"; "-"; "\\"|]

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

(** Color gradient for blocks - from bright to dim (blue tones) *)
let gradient_colors = [|75; 68; 67; 60; 240|]

(** Glyphs by size: large (lead), medium, small, tiny, dim *)
let size_glyphs_square_unicode = [|"■"; "▪"; "•"; "·"; "·"|]

let size_glyphs_circle_unicode = [|"●"; "○"; "•"; "·"; "·"|]

let size_glyphs_dot_unicode = [|"•"; "∙"; "·"; "·"; "·"|]

let size_glyphs_ascii = [|"#"; "o"; "."; "."; "."|]

(** Render the blocks animation with gradient and size progression.
    Shows glyphs that shrink from the lead: ■ ▪ • · ·
    The lead block is largest/brightest, trail gets smaller and dimmer. *)
let render_blocks_glyph ~prefer_ascii ~blocks_count ~direction ~glyph frame_idx
    =
  let module W = Miaou_widgets_display.Widgets in
  let glyphs =
    if prefer_ascii then size_glyphs_ascii
    else
      match glyph with
      | Square -> size_glyphs_square_unicode
      | Circle -> size_glyphs_circle_unicode
      | Dot -> size_glyphs_dot_unicode
  in
  (* The highlight position moves across the blocks *)
  let highlight_pos = frame_idx mod blocks_count in
  let buf = Buffer.create (blocks_count * 8) in
  for i = 0 to blocks_count - 1 do
    (* Calculate distance from highlight, taking direction into account *)
    let pos =
      match direction with Right -> i | Left -> blocks_count - 1 - i
    in
    (* Distance considers the trail behind the highlight (wrapping) *)
    let raw_dist =
      let d = highlight_pos - pos in
      if d < 0 then d + blocks_count else d
    in
    (* Map distance to size and color *)
    let idx = min raw_dist (Array.length gradient_colors - 1) in
    let color = gradient_colors.(idx) in
    let char = glyphs.(min idx (Array.length glyphs - 1)) in
    Buffer.add_string buf (W.fg color char)
  done ;
  Buffer.contents buf

let render_with_backend backend t =
  let prefer_ascii = Miaou_widgets_display.Widgets.prefer_ascii ~backend () in
  match t.style with
  | Blocks ->
      let frame_idx = frame_index t t.blocks_count in
      let blocks =
        render_blocks_glyph
          ~prefer_ascii
          ~blocks_count:t.blocks_count
          ~direction:t.direction
          ~glyph:t.glyph
          frame_idx
      in
      let label = match t.label with None -> "" | Some s -> "  " ^ s in
      blocks ^ label
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
