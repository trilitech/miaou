(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

type t = {
  config : Matrix_config.t;
  buffer : Matrix_buffer.t;
  writer : Matrix_ansi_writer.t;
  terminal : Matrix_terminal.t;
  mutable frame_requested : bool;
  mutable last_frame_time : float;
  mutable frame_count : int;
  mutable fps_start_time : float;
  mutable current_fps : float;
  mutable is_shutdown : bool;
}

let create ~config ~buffer ~writer ~terminal =
  let now = Unix.gettimeofday () in
  {
    config;
    buffer;
    writer;
    terminal;
    frame_requested = false;
    last_frame_time = now;
    frame_count = 0;
    fps_start_time = now;
    current_fps = 0.0;
    is_shutdown = false;
  }

let request_frame t = t.frame_requested <- true

let frame_pending t = t.frame_requested

let do_render t =
  (* Reset terminal style and writer state to ensure consistency *)
  Matrix_terminal.write t.terminal "\027[0m" ;
  Matrix_ansi_writer.reset t.writer ;

  (* Compute diff *)
  let changes = Matrix_diff.compute t.buffer in

  (* Generate ANSI output *)
  let ansi = Matrix_ansi_writer.render t.writer changes in

  (* Write to terminal *)
  if String.length ansi > 0 then Matrix_terminal.write t.terminal ansi ;

  (* Swap buffers *)
  Matrix_buffer.swap t.buffer ;

  (* Update frame timing *)
  let now = Unix.gettimeofday () in
  t.last_frame_time <- now ;
  t.frame_count <- t.frame_count + 1 ;

  (* Update FPS calculation every second *)
  let elapsed = now -. t.fps_start_time in
  if elapsed >= 1.0 then begin
    t.current_fps <- float_of_int t.frame_count /. elapsed ;
    t.frame_count <- 0 ;
    t.fps_start_time <- now
  end

let render_if_needed t =
  if t.is_shutdown then false
  else if not t.frame_requested then false
  else begin
    (* Check FPS cap *)
    let now = Unix.gettimeofday () in
    let elapsed_ms = (now -. t.last_frame_time) *. 1000.0 in
    if elapsed_ms < t.config.frame_time_ms then false
    else begin
      t.frame_requested <- false ;
      do_render t ;
      true
    end
  end

let force_render t =
  if not t.is_shutdown then begin
    t.frame_requested <- false ;
    do_render t
  end

let shutdown t = t.is_shutdown <- true

let current_fps t = t.current_fps
