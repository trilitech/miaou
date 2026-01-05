(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

type t = {mutable current_style : Matrix_cell.style}

let create () = {current_style = Matrix_cell.default_style}

let reset t = t.current_style <- Matrix_cell.default_style

(* ANSI control sequences *)
let cursor_hide = "\027[?25l"

let cursor_show = "\027[?25h"

let cursor_home = "\027[H"

let reset_style = "\027[0m"

(* Move cursor to row, col (converting from 0-indexed to 1-indexed for ANSI) *)
let cursor_move ~row ~col = Printf.sprintf "\027[%d;%dH" (row + 1) (col + 1)

(* Generate SGR sequence for a style *)
let style_to_sgr style =
  let open Matrix_cell in
  let parts = ref [] in

  (* Always start with reset if we have any attributes to set *)
  if
    style.fg <> -1 || style.bg <> -1 || style.bold || style.dim
    || style.underline || style.reverse
  then parts := "0" :: !parts ;

  (* Bold *)
  if style.bold then parts := "1" :: !parts ;

  (* Dim *)
  if style.dim then parts := "2" :: !parts ;

  (* Underline *)
  if style.underline then parts := "4" :: !parts ;

  (* Reverse *)
  if style.reverse then parts := "7" :: !parts ;

  (* Foreground color *)
  if style.fg >= 0 && style.fg <= 255 then
    parts := Printf.sprintf "38;5;%d" style.fg :: !parts
  else if style.fg = -1 then ()
  else () ;

  (* Background color *)
  if style.bg >= 0 && style.bg <= 255 then
    parts := Printf.sprintf "48;5;%d" style.bg :: !parts
  else if style.bg = -1 then ()
  else () ;

  match !parts with
  | [] -> ""
  | ps -> "\027[" ^ String.concat ";" (List.rev ps) ^ "m"

(* Render changes to ANSI string *)
let render t changes =
  let buf = Buffer.create 1024 in

  List.iter
    (fun change ->
      match change with
      | Matrix_diff.MoveTo (row, col) ->
          Buffer.add_string buf (cursor_move ~row ~col)
      | Matrix_diff.SetStyle style ->
          if not (Matrix_cell.style_equal style t.current_style) then begin
            (* If new style is default, just reset *)
            if Matrix_cell.style_equal style Matrix_cell.default_style then
              Buffer.add_string buf reset_style
            else Buffer.add_string buf (style_to_sgr style) ;
            t.current_style <- style
          end
      | Matrix_diff.WriteChar c -> Buffer.add_string buf c
      | Matrix_diff.WriteRun (c, n) ->
          for _ = 1 to n do
            Buffer.add_string buf c
          done)
    changes ;

  Buffer.contents buf
