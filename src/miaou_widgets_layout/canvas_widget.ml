(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

module Canvas = Miaou_canvas.Canvas

type t = {
  mutable canvas : Canvas.t option;
  mutable c_rows : int;
  mutable c_cols : int;
}

let create () = {canvas = None; c_rows = 0; c_cols = 0}

let canvas t = t.canvas

let canvas_exn t =
  match t.canvas with
  | Some c -> c
  | None -> invalid_arg "Canvas_widget.canvas_exn: canvas not allocated yet"

let ensure_size t ~rows ~cols =
  if t.c_rows = rows && t.c_cols = cols && t.canvas <> None then ()
  else begin
    t.canvas <- Some (Canvas.create ~rows ~cols) ;
    t.c_rows <- rows ;
    t.c_cols <- cols
  end

let ensure t ~rows ~cols =
  ensure_size t ~rows ~cols ;
  t

let clear t =
  (match t.canvas with Some c -> Canvas.clear c | None -> ()) ;
  t

let render t ~size =
  let rows = size.LTerm_geom.rows in
  let cols = size.LTerm_geom.cols in
  ensure_size t ~rows ~cols ;
  match t.canvas with Some c -> Canvas.to_ansi c | None -> ""

let rows t = t.c_rows

let cols t = t.c_cols
