(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

type event =
  | Key of string
  | Mouse of int * int
  | Resize
  | Refresh (* Time for service_cycle - rate limited *)
  | Idle (* No input, not time for refresh - just keep rendering *)
  | Quit

type t = {
  terminal : Matrix_terminal.t;
  fd : Unix.file_descr;
  pending : Buffer.t; (* Using Buffer for efficient append *)
  exit_flag : bool Atomic.t;
  mutable last_refresh_time : float; (* Rate limit refresh events *)
}

(* Refresh interval in seconds - controls how often service_cycle is called *)
let refresh_interval = 1.0

let create terminal =
  let fd = Matrix_terminal.fd terminal in
  let exit_flag =
    Matrix_terminal.install_signals terminal (fun () ->
        Matrix_terminal.cleanup terminal)
  in
  {
    terminal;
    fd;
    pending = Buffer.create 256;
    exit_flag;
    last_refresh_time = 0.0;
  }

(* Get current pending content as string *)
let pending_contents t = Buffer.contents t.pending

(* Get pending buffer length *)
let pending_length t = Buffer.length t.pending

(* Clear pending buffer *)
let clear_pending t = Buffer.clear t.pending

(* Fill pending buffer from fd with timeout *)
let refill t timeout_s =
  try
    let r, _, _ = Unix.select [t.fd] [] [] timeout_s in
    if r = [] then 0
    else
      let buf = Bytes.create 256 in
      try
        let n = Unix.read t.fd buf 0 256 in
        if n <= 0 then 0
        else begin
          Buffer.add_subbytes t.pending buf 0 n ;
          n
        end
      with Unix.Unix_error (Unix.EINTR, _, _) -> 0
  with Unix.Unix_error (Unix.EINTR, _, _) -> 0

(* Consume n bytes from pending buffer *)
let consume t n =
  let len = pending_length t in
  if n >= len then clear_pending t
  else begin
    (* Keep the remaining bytes *)
    let remaining = Buffer.sub t.pending n (len - n) in
    clear_pending t ;
    Buffer.add_string t.pending remaining
  end

(* Get character at index in pending buffer *)
let pending_char t i =
  if i < pending_length t then Some (Buffer.nth t.pending i) else None

(* Parse key from pending buffer *)
let parse_key t =
  if pending_length t = 0 then None
  else
    let first = Buffer.nth t.pending 0 in
    let code = Char.code first in

    (* Non-escape characters *)
    if code <> 27 then begin
      consume t 1 ;
      if first = '\000' then Some Refresh
      else if first = '\n' || first = '\r' then Some (Key "Enter")
      else if code = 9 then Some (Key "Tab")
      else if code = 127 then Some (Key "Backspace")
      else if code >= 1 && code <= 26 then
        let letter = Char.chr (code + 96) in
        Some (Key ("C-" ^ String.make 1 letter))
      else Some (Key (String.make 1 first))
    end
    (* Escape sequences *)
      else begin
      (* Ensure we have enough bytes for escape sequence *)
      for _ = 1 to 5 do
        if pending_length t >= 3 then () else ignore (refill t 0.02)
      done ;

      let len = pending_length t in

      if len = 1 then begin
        consume t 1 ;
        Some (Key "Esc")
      end
      else if len >= 3 && Buffer.nth t.pending 1 = '[' then begin
        let c = Buffer.nth t.pending 2 in

        (* SGR mouse: ESC [ < btn;col;row (M|m) *)
        if len >= 6 && c = '<' then begin
          (* Wait for complete mouse sequence *)
          let rec wait_for_terminator n =
            if n <= 0 then ()
            else
              let l = pending_length t in
              if l > 0 then
                let last = Buffer.nth t.pending (l - 1) in
                if last = 'M' || last = 'm' then ()
                else begin
                  ignore (refill t 0.02) ;
                  wait_for_terminator (n - 1)
                end
              else begin
                ignore (refill t 0.02) ;
                wait_for_terminator (n - 1)
              end
          in
          wait_for_terminator 20 ;

          (* Parse mouse sequence *)
          let seq = pending_contents t in
          let seq_len = String.length seq in
          let term_idx =
            let rec find i =
              if i >= seq_len then seq_len - 1
              else if seq.[i] = 'M' || seq.[i] = 'm' then i
              else find (i + 1)
            in
            find 0
          in
          let chunk_len = min (term_idx + 1) seq_len in
          consume t chunk_len ;

          (* Try to parse btn;col;row *)
          if chunk_len >= 6 then
            try
              let body = String.sub seq 3 (chunk_len - 4) in
              let lastc = seq.[chunk_len - 1] in
              match String.split_on_char ';' body with
              | [_btn; col; row] ->
                  let col = int_of_string col in
                  let row = int_of_string (String.trim row) in
                  if lastc = 'm' then Some (Mouse (row, col))
                  else Some Refresh (* Motion events as refresh *)
              | _ -> Some (Key "Esc")
            with _ -> Some (Key "Esc")
          else Some (Key "Esc")
        end
        (* Arrow keys and others *)
          else begin
          consume t 3 ;
          match c with
          | 'A' -> Some (Key "Up")
          | 'B' -> Some (Key "Down")
          | 'C' -> Some (Key "Right")
          | 'D' -> Some (Key "Left")
          | '3' ->
              (* Delete: ESC [ 3 ~ *)
              if len >= 4 && pending_char t 0 = Some '~' then begin
                consume t 1 ;
                Some (Key "Delete")
              end
              else Some (Key "3")
          | _ -> Some (Key (String.make 1 c))
        end
      end
      else if len >= 3 && Buffer.nth t.pending 1 = 'O' then begin
        let c = Buffer.nth t.pending 2 in
        consume t 3 ;
        match c with
        | 'A' -> Some (Key "Up")
        | 'B' -> Some (Key "Down")
        | 'C' -> Some (Key "Right")
        | 'D' -> Some (Key "Left")
        | _ -> Some (Key (String.make 1 c))
      end
      else if len >= 2 then begin
        let second = Buffer.nth t.pending 1 in
        consume t 2 ;
        Some (Key (String.make 1 second))
      end
      else begin
        consume t 1 ;
        Some (Key "Esc")
      end
    end

let poll t ~timeout_ms =
  (* Check exit flag *)
  if Atomic.get t.exit_flag then Quit (* Check resize *)
  else if Matrix_terminal.resize_pending t.terminal then begin
    Matrix_terminal.clear_resize_pending t.terminal ;
    Resize
  end
  (* Try to read input *)
    else begin
    if pending_length t = 0 then begin
      let timeout_s = float_of_int timeout_ms /. 1000.0 in
      ignore (refill t timeout_s)
    end ;
    if pending_length t = 0 then begin
      (* Rate-limit refresh events to avoid calling service_cycle too often.
         Pages like Diagnostics do expensive I/O in service_cycle. *)
      let now = Unix.gettimeofday () in
      if now -. t.last_refresh_time >= refresh_interval then begin
        t.last_refresh_time <- now ;
        Buffer.add_char t.pending '\000' (* Inject refresh marker *)
      end
    end ;
    match parse_key t with
    | Some event -> event
    | None -> Idle (* No input, not time for refresh *)
  end

(* Drain consecutive navigation keys to prevent scroll lag *)
let drain_nav_keys t event =
  let is_nav_key = function
    | Key "Up" | Key "Down" | Key "Left" | Key "Right" | Key "Tab" -> true
    | _ -> false
  in
  if not (is_nav_key event) then 0
  else
    let count = ref 0 in
    let rec drain () =
      ignore (refill t 0.0) ;
      (* Non-blocking *)
      match parse_key t with
      | Some e when e = event ->
          incr count ;
          drain ()
      | _ -> ()
    in
    drain () ;
    !count
