(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(** Matrix driver input handling - uses shared Input_parser. *)

module Parser = Miaou_driver_common.Input_parser

type t = {
  terminal : Matrix_terminal.t;
  parser : Parser.t;
  exit_flag : bool Atomic.t;
  mutable last_refresh_time : float;
}

(* Refresh interval in seconds - controls how often service_cycle is called *)
let refresh_interval = 1.0

let create terminal =
  let fd = Matrix_terminal.fd terminal in
  let exit_flag =
    Matrix_terminal.install_signals terminal (fun () ->
        Matrix_terminal.cleanup terminal)
  in
  {terminal; parser = Parser.create fd; exit_flag; last_refresh_time = 0.0}

(** Convert Parser.key to event *)
let key_to_event = function
  | Parser.Mouse {row; col; release} ->
      if release then Matrix_io.Mouse (row, col) else Matrix_io.Refresh
  | Parser.Refresh -> Matrix_io.Refresh
  | key -> Matrix_io.Key (Parser.key_to_string key)

let poll t ~timeout_ms:_ =
  (* Check exit flag *)
  if Atomic.get t.exit_flag then Matrix_io.Quit
  else if Matrix_terminal.resize_pending t.terminal then begin
    Matrix_terminal.clear_resize_pending t.terminal ;
    Matrix_io.Resize
  end
  else if Miaou_helpers.Render_notify.should_render () then Matrix_io.Refresh
  else begin
    (* Try to read input with minimal timeout - let Eio handle actual timing
       to allow other fibers to run *)
    if Parser.pending_length t.parser = 0 then
      ignore (Parser.refill t.parser ~timeout_s:0.001) ;
    (* Rate-limit refresh events *)
    if Parser.pending_length t.parser = 0 then begin
      let now = Unix.gettimeofday () in
      if now -. t.last_refresh_time >= refresh_interval then begin
        t.last_refresh_time <- now ;
        Matrix_io.Refresh
      end
      else Matrix_io.Idle
    end
    else
      match Parser.parse_key t.parser with
      | Some key -> key_to_event key
      | None -> Matrix_io.Idle
  end

(** Convert event to Parser.key for draining *)
let event_to_parser_key = function
  | Matrix_io.Key "Up" -> Some Parser.Up
  | Matrix_io.Key "Down" -> Some Parser.Down
  | Matrix_io.Key "Left" -> Some Parser.Left
  | Matrix_io.Key "Right" -> Some Parser.Right
  | Matrix_io.Key "Tab" -> Some Parser.Tab
  | Matrix_io.Key "Delete" -> Some Parser.Delete
  | _ -> None

(* Drain consecutive navigation keys to prevent scroll lag *)
let drain_nav_keys t event =
  match event_to_parser_key event with
  | Some key -> Parser.drain_matching t.parser key
  | None -> 0

(* Drain any pending Esc keys from buffer.
   Call after modal close to prevent double-Esc navigation. *)
let drain_esc_keys t = Parser.drain_esc t.parser
