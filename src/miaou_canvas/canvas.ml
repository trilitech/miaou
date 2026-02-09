(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

module H = Miaou_helpers.Helpers

type style = {
  fg : int;
  bg : int;
  bold : bool;
  dim : bool;
  underline : bool;
  reverse : bool;
}

type cell = {char : string; style : style}

type t = {rows : int; cols : int; grid : cell array array}

type border_style = Single | Double | Rounded | Ascii | Heavy

type border_chars = {
  tl : string;
  tr : string;
  bl : string;
  br : string;
  h : string;
  v : string;
}

let default_style =
  {
    fg = -1;
    bg = -1;
    bold = false;
    dim = false;
    underline = false;
    reverse = false;
  }

let empty_cell = {char = " "; style = default_style}

let create ~rows ~cols =
  if rows < 0 || cols < 0 then
    invalid_arg "Canvas.create: rows and cols must be non-negative" ;
  let grid = Array.init rows (fun _ -> Array.init cols (fun _ -> empty_cell)) in
  {rows; cols; grid}

let rows t = t.rows

let cols t = t.cols

let in_bounds t ~row ~col = row >= 0 && row < t.rows && col >= 0 && col < t.cols

let set_char t ~row ~col ~char ~style =
  if in_bounds t ~row ~col then t.grid.(row).(col) <- {char; style}

let get_cell t ~row ~col =
  if not (in_bounds t ~row ~col) then
    invalid_arg
      (Printf.sprintf
         "Canvas.get_cell: (%d, %d) out of bounds (%d x %d)"
         row
         col
         t.rows
         t.cols) ;
  t.grid.(row).(col)

let fill_rect t ~row ~col ~width ~height ~char ~style =
  let r0 = max 0 row in
  let c0 = max 0 col in
  let r1 = min t.rows (row + height) in
  let c1 = min t.cols (col + width) in
  for r = r0 to r1 - 1 do
    for c = c0 to c1 - 1 do
      t.grid.(r).(c) <- {char; style}
    done
  done

let clear t =
  for r = 0 to t.rows - 1 do
    for c = 0 to t.cols - 1 do
      t.grid.(r).(c) <- empty_cell
    done
  done

(* Iterate over UTF-8 grapheme clusters in a plain-text string (no ANSI).
   Each cluster is one "character" occupying one cell. *)
let iter_graphemes s f =
  let len = String.length s in
  let rec loop i =
    if i >= len then ()
    else begin
      (* Find end of this grapheme cluster: skip continuation bytes *)
      let j = ref (i + 1) in
      while !j < len && not (H.is_utf8_lead s.[!j]) do
        incr j
      done ;
      f (String.sub s i (!j - i)) ;
      loop !j
    end
  in
  loop 0

let draw_text t ~row ~col ~style text =
  let c = ref col in
  iter_graphemes text (fun grapheme ->
      if in_bounds t ~row ~col:!c then
        t.grid.(row).(!c) <- {char = grapheme; style} ;
      incr c)

let draw_hline t ~row ~col ~len ~char ~style =
  for i = 0 to len - 1 do
    set_char t ~row ~col:(col + i) ~char ~style
  done

let draw_vline t ~row ~col ~len ~char ~style =
  for i = 0 to len - 1 do
    set_char t ~row:(row + i) ~col ~char ~style
  done

(* Border character sets *)

let single_chars =
  {
    tl = "\xe2\x94\x8c";
    tr = "\xe2\x94\x90";
    bl = "\xe2\x94\x94";
    br = "\xe2\x94\x98";
    h = "\xe2\x94\x80";
    v = "\xe2\x94\x82";
  }

let double_chars =
  {
    tl = "\xe2\x95\x94";
    tr = "\xe2\x95\x97";
    bl = "\xe2\x95\x9a";
    br = "\xe2\x95\x9d";
    h = "\xe2\x95\x90";
    v = "\xe2\x95\x91";
  }

let rounded_chars =
  {
    tl = "\xe2\x95\xad";
    tr = "\xe2\x95\xae";
    bl = "\xe2\x95\xb0";
    br = "\xe2\x95\xaf";
    h = "\xe2\x94\x80";
    v = "\xe2\x94\x82";
  }

let heavy_chars =
  {
    tl = "\xe2\x94\x8f";
    tr = "\xe2\x94\x93";
    bl = "\xe2\x94\x97";
    br = "\xe2\x94\x9b";
    h = "\xe2\x94\x81";
    v = "\xe2\x94\x83";
  }

let ascii_chars = {tl = "+"; tr = "+"; bl = "+"; br = "+"; h = "-"; v = "|"}

let border_chars_of_style = function
  | Single -> single_chars
  | Double -> double_chars
  | Rounded -> rounded_chars
  | Heavy -> heavy_chars
  | Ascii -> ascii_chars

let draw_box_with_chars t ~row ~col ~width ~height ~chars ~style =
  if width >= 2 && height >= 2 then begin
    (* Corners *)
    set_char t ~row ~col ~char:chars.tl ~style ;
    set_char t ~row ~col:(col + width - 1) ~char:chars.tr ~style ;
    set_char t ~row:(row + height - 1) ~col ~char:chars.bl ~style ;
    set_char
      t
      ~row:(row + height - 1)
      ~col:(col + width - 1)
      ~char:chars.br
      ~style ;
    (* Horizontal edges *)
    draw_hline t ~row ~col:(col + 1) ~len:(width - 2) ~char:chars.h ~style ;
    draw_hline
      t
      ~row:(row + height - 1)
      ~col:(col + 1)
      ~len:(width - 2)
      ~char:chars.h
      ~style ;
    (* Vertical edges *)
    draw_vline t ~row:(row + 1) ~col ~len:(height - 2) ~char:chars.v ~style ;
    draw_vline
      t
      ~row:(row + 1)
      ~col:(col + width - 1)
      ~len:(height - 2)
      ~char:chars.v
      ~style
  end

let draw_box t ~row ~col ~width ~height ~border ~style =
  let chars = border_chars_of_style border in
  draw_box_with_chars t ~row ~col ~width ~height ~chars ~style

let blit ~src ~dst ~row ~col =
  for r = 0 to src.rows - 1 do
    let dr = row + r in
    if dr >= 0 && dr < dst.rows then
      for c = 0 to src.cols - 1 do
        let dc = col + c in
        if dc >= 0 && dc < dst.cols then begin
          let cell = src.grid.(r).(c) in
          if cell.char <> " " then dst.grid.(dr).(dc) <- cell
        end
      done
  done

let blit_all ~src ~dst ~row ~col =
  for r = 0 to src.rows - 1 do
    let dr = row + r in
    if dr >= 0 && dr < dst.rows then
      for c = 0 to src.cols - 1 do
        let dc = col + c in
        if dc >= 0 && dc < dst.cols then dst.grid.(dr).(dc) <- src.grid.(r).(c)
      done
  done

(* ANSI rendering *)

let style_equal a b =
  a.fg = b.fg && a.bg = b.bg && a.bold = b.bold && a.dim = b.dim
  && a.underline = b.underline && a.reverse = b.reverse

let emit_sgr buf style =
  (* Build SGR parameter list for the given style *)
  Buffer.add_string buf "\027[0" ;
  if style.bold then Buffer.add_string buf ";1" ;
  if style.dim then Buffer.add_string buf ";2" ;
  if style.underline then Buffer.add_string buf ";4" ;
  if style.reverse then Buffer.add_string buf ";7" ;
  if style.fg >= 0 then begin
    Buffer.add_string buf ";38;5;" ;
    Buffer.add_string buf (string_of_int style.fg)
  end ;
  if style.bg >= 0 then begin
    Buffer.add_string buf ";48;5;" ;
    Buffer.add_string buf (string_of_int style.bg)
  end ;
  Buffer.add_char buf 'm'

let to_ansi t =
  if t.rows = 0 || t.cols = 0 then ""
  else
    (* Estimate: ~4 bytes per cell on average *)
    let buf = Buffer.create (t.rows * t.cols * 4) in
    let current_style = ref default_style in
    for r = 0 to t.rows - 1 do
      if r > 0 then Buffer.add_char buf '\n' ;
      for c = 0 to t.cols - 1 do
        let cell = t.grid.(r).(c) in
        if not (style_equal !current_style cell.style) then begin
          emit_sgr buf cell.style ;
          current_style := cell.style
        end ;
        Buffer.add_string buf cell.char
      done
    done ;
    (* Reset at end if we changed style *)
    if not (style_equal !current_style default_style) then
      Buffer.add_string buf "\027[0m" ;
    Buffer.contents buf

let iter t ~f =
  for r = 0 to t.rows - 1 do
    for c = 0 to t.cols - 1 do
      f ~row:r ~col:c t.grid.(r).(c)
    done
  done
