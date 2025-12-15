(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)
module Pager = Pager_widget
module Fibers = Miaou_helpers.Fiber_runtime

type tail_strategy =
  | Inotify of {proc_in : in_channel; fd : Unix.file_descr}
  | Polling

type tail_state = {
  path : string;
  mutable pos : int;
  mutable strategy : tail_strategy;
  mutable last_check : float;
  poll_interval_s : float;
  mutable closed : bool;
}

type t = {
  pager : Pager.t;
  mutable tail : tail_state option;
  mutable closed : bool;
  mutable cancel : (unit -> unit) option;
  notify_render : unit -> unit;
}

let runtime_error =
  Error
    "Eio runtime not initialized; call Miaou_helpers.Fiber_runtime.init inside \
     Eio_main.run"

let read_all_lines env path =
  let p = Eio.Path.(env#fs / path) in
  Eio.Path.with_open_in p @@ fun flow ->
  let buf = Eio.Buf_read.of_flow ~max_size:(16 * 1024 * 1024) flow in
  let rec loop acc =
    match Eio.Buf_read.line buf with
    | line -> loop (line :: acc)
    | exception End_of_file -> List.rev acc
  in
  loop []

let start_inotify _path = None (* Poll-only to avoid external process hangs *)

let make_tail env path poll_interval_s =
  try
    let st = Unix.stat path in
    let strategy =
      match start_inotify path with
      | Some (proc_in, fd) -> Inotify {proc_in; fd}
      | None -> Polling
    in
    Some
      {
        path;
        pos = st.Unix.st_size;
        strategy;
        last_check = Eio.Time.now env#clock;
        poll_interval_s;
        closed = false;
      }
  with _ -> None

let close_tail (tail : tail_state) =
  if tail.closed then ()
  else (
    tail.closed <- true ;
    match tail.strategy with Inotify _ -> () | Polling -> ())

let check_inotify tail _env =
  match tail.strategy with
  | Inotify {proc_in; fd} -> (
      try
        (* Use Unix.select instead of Eio.await_readable for raw fds *)
        let ready, _, _ = Unix.select [fd] [] [] 0.0 in
        if ready = [] then false
        else (
          (try ignore (input_line proc_in) with _ -> ()) ;
          true)
      with _ ->
        tail.strategy <- Polling ;
        false)
  | Polling -> false

let read_new_lines _env tail pager =
  match try Some (Unix.stat tail.path) with _ -> None with
  | None -> ()
  | Some st -> (
      if st.Unix.st_size < tail.pos then tail.pos <- st.Unix.st_size ;
      try
        let ic = open_in_bin tail.path in
        seek_in ic tail.pos ;
        let rec loop acc =
          match input_line ic with
          | line -> loop (line :: acc)
          | exception End_of_file -> (List.rev acc, pos_in ic)
        in
        let lines, new_pos = loop [] in
        close_in_noerr ic ;
        tail.pos <- new_pos ;
        if lines <> [] then Pager.append_lines_batched pager lines
      with _ -> ())

let rec tail_loop env t tail =
  if t.closed || Fibers.is_shutdown () then close_tail tail
  else
    let now = Eio.Time.now env#clock in
    let event_ready = check_inotify tail env in
    let should_poll =
      event_ready
      ||
      match tail.strategy with
      | Polling -> now -. tail.last_check >= tail.poll_interval_s
      | Inotify _ -> false
    in
    if should_poll then (
      tail.last_check <- now ;
      read_new_lines env tail t.pager ;
      Pager.flush_pending_if_needed ~force:true t.pager ;
      t.notify_render ()) ;
    (* Check closed flag before sleeping *)
    if (not t.closed) && not (Fibers.is_shutdown ()) then (
      Eio.Time.sleep env#clock tail.poll_interval_s ;
      tail_loop env t tail)

let close t =
  t.closed <- true ;
  (* Trigger cancellation of the tail fiber *)
  Option.iter (fun cancel -> cancel ()) t.cancel ;
  t.cancel <- None ;
  Option.iter
    (fun tail ->
      close_tail tail ;
      t.tail <- None ;
      Pager.stop_streaming t.pager)
    t.tail

let start_tail_watcher t tail =
  let env, sw = Fibers.require_env_and_switch () in
  let cancel_promise, cancel_resolver = Eio.Promise.create () in
  let resolved = ref false in
  t.cancel <-
    Some
      (fun () ->
        if not !resolved then (
          resolved := true ;
          Eio.Promise.resolve cancel_resolver ())) ;
  (* Ensure the pager shuts down when the enclosing page switch closes even if
     callers forget to invoke [close]. *)
  Eio.Switch.on_release sw (fun () -> close t) ;
  let tail_worker () =
    Fun.protect
      ~finally:(fun () ->
        t.closed <- true ;
        close_tail tail ;
        t.tail <- None ;
        Pager.stop_streaming t.pager)
      (fun () ->
        Eio.Fiber.first
          (fun () -> tail_loop env t tail)
          (fun () -> Eio.Promise.await cancel_promise))
  in
  Eio.Fiber.fork ~sw tail_worker

let pager t = t.pager

let open_file ?(follow = false) ?notify_render ?(poll_interval = 0.25) path =
  match Fibers.env_opt () with
  | None -> runtime_error
  | Some env -> (
      try
        let lines = read_all_lines env path in
        let pager = Pager.open_lines ~title:path ?notify_render lines in
        let notify_cb =
          match notify_render with
          | Some f -> f
          | None -> (
              match pager.Pager.notify_render with
              | Some f -> f
              | None -> fun () -> ())
        in
        let t =
          {
            pager;
            tail = None;
            closed = false;
            cancel = None;
            notify_render = notify_cb;
          }
        in
        if follow then (
          Pager.start_streaming t.pager ;
          t.pager.Pager.follow <- true ;
          match make_tail env path poll_interval with
          | Some tail ->
              t.tail <- Some tail ;
              start_tail_watcher t tail
          | None -> ()) ;
        Ok t
      with exn -> Error (Printexc.to_string exn))
