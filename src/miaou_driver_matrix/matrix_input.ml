(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(** Matrix driver input handling — decoupled reader fiber with event queue.

    A dedicated Eio fiber continuously awaits readability on the terminal fd
    via {!Eio_unix.await_readable}, reads bytes with a non-blocking
    {!Input_parser.refill_nonblocking}, parses keys, and pushes
    {!Matrix_io.event} values into a mutex-protected queue.

    The main tick loop drains the queue at the start of every tick and
    processes all buffered events, giving sub-millisecond input latency
    regardless of the TPS setting. *)

module Parser = Miaou_driver_common.Input_parser

(** {2 Event queue} *)

module Event_queue : sig
  type t

  val create : unit -> t

  (** Push an event (called from reader fiber). *)
  val push : t -> Matrix_io.event -> unit

  (** Drain all pending events into a list (oldest first).
      Returns the empty list when the queue is empty. *)
  val drain : t -> Matrix_io.event list
end = struct
  type t = {mu : Mutex.t; q : Matrix_io.event Queue.t}

  let create () = {mu = Mutex.create (); q = Queue.create ()}

  let push t ev =
    Mutex.lock t.mu ;
    Queue.push ev t.q ;
    Mutex.unlock t.mu

  let drain t =
    Mutex.lock t.mu ;
    let events = Queue.fold (fun acc ev -> ev :: acc) [] t.q in
    Queue.clear t.q ;
    Mutex.unlock t.mu ;
    List.rev events
end

(** {2 Input reader} *)

type t = {
  terminal : Matrix_terminal.t;
  parser : Parser.t;
  exit_flag : bool Atomic.t;
  queue : Event_queue.t;
  shutdown : bool Atomic.t;
  mutable last_refresh_time : float;
}

(* Refresh interval in seconds — controls how often a synthetic Refresh
   event is injected so that service_cycle runs even when idle. *)
let refresh_interval = 1.0

(** Convert Parser.key to event *)
let key_to_event = function
  | Parser.Mouse {row; col; button; release} ->
      if release then Matrix_io.Mouse (row, col, button)
      else Matrix_io.MousePress (row, col, button)
  | Parser.MouseDrag {row; col} -> Matrix_io.MouseDrag (row, col)
  | Parser.Refresh -> Matrix_io.Refresh
  | key -> Matrix_io.Key (Parser.key_to_string key)

(** Check for non-input events (quit signal, resize, render_notify). *)
let check_non_input_events (t : t) =
  if Atomic.get t.exit_flag then (
    Event_queue.push t.queue Matrix_io.Quit ;
    true)
  else if Matrix_terminal.resize_pending t.terminal then (
    Matrix_terminal.clear_resize_pending t.terminal ;
    Event_queue.push t.queue Matrix_io.Resize ;
    true)
  else if Miaou_helpers.Render_notify.should_render () then (
    Event_queue.push t.queue Matrix_io.Refresh ;
    true)
  else false

(** Inject a periodic Refresh event so service_cycle runs when idle. *)
let maybe_inject_refresh (t : t) =
  let now = Unix.gettimeofday () in
  if now -. t.last_refresh_time >= refresh_interval then (
    t.last_refresh_time <- now ;
    Event_queue.push t.queue Matrix_io.Refresh)

(** Parse all available keys from the parser buffer into the queue. *)
let parse_all_into_queue (t : t) =
  let rec go () =
    match Parser.parse_key t.parser with
    | Some key ->
        Event_queue.push t.queue (key_to_event key) ;
        go ()
    | None -> ()
  in
  go ()

(** Reader-fiber main loop.  Uses {!Eio_unix.await_readable} to yield to
    the Eio scheduler while waiting for terminal input, then performs a
    non-blocking read + parse burst. *)
let reader_loop (t : t) _env =
  let fd = Parser.fd t.parser in
  while not (Atomic.get t.shutdown) do
    if not (check_non_input_events t) then begin
      (* Yield to the Eio scheduler until the fd has data *)
      (try Eio_unix.await_readable fd with
      | Eio.Cancel.Cancelled _ -> ()
      | Unix.Unix_error (Unix.EINTR, _, _) -> ()) ;
      if not (Atomic.get t.shutdown) then begin
        let n = Parser.refill_nonblocking t.parser in
        if n > 0 then parse_all_into_queue t else maybe_inject_refresh t
      end
    end
  done

let create terminal =
  let fd = Matrix_terminal.fd terminal in
  let exit_flag =
    Matrix_terminal.install_signals terminal (fun () ->
        Matrix_terminal.cleanup terminal)
  in
  {
    terminal;
    parser = Parser.create fd;
    exit_flag;
    queue = Event_queue.create ();
    shutdown = Atomic.make false;
    last_refresh_time = 0.0;
  }

(** Start the background reader fiber.  Must be called after terminal
    raw-mode setup, from inside an Eio switch. *)
let start t =
  let open Miaou_helpers.Fiber_runtime in
  spawn (fun env -> reader_loop t env)

(** Signal the reader fiber to stop. *)
let stop t = Atomic.set t.shutdown true

(** Drain all pending events (oldest first). *)
let drain t = Event_queue.drain t.queue
