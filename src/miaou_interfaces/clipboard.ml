(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

[@@@warning "-32-34-37-69"]

type t = {copy : string -> unit; copy_available : unit -> bool}

let key : t Capability.key = Capability.create ~name:"Clipboard"

let set v = Capability.set key v

let get () = Capability.get key

let require () = Capability.require key

(** Base64 encoding alphabet *)
let base64_chars =
  "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

(** Encode a string to base64. *)
let base64_encode s =
  let len = String.length s in
  let output_len = (len + 2) / 3 * 4 in
  let buf = Buffer.create output_len in
  let i = ref 0 in
  while !i < len do
    let b0 = Char.code s.[!i] in
    let b1 = if !i + 1 < len then Char.code s.[!i + 1] else 0 in
    let b2 = if !i + 2 < len then Char.code s.[!i + 2] else 0 in
    Buffer.add_char buf base64_chars.[(b0 lsr 2) land 0x3F] ;
    Buffer.add_char buf base64_chars.[(b0 lsl 4) lor (b1 lsr 4) land 0x3F] ;
    if !i + 1 < len then
      Buffer.add_char buf base64_chars.[(b1 lsl 2) lor (b2 lsr 6) land 0x3F]
    else Buffer.add_char buf '=' ;
    if !i + 2 < len then Buffer.add_char buf base64_chars.[b2 land 0x3F]
    else Buffer.add_char buf '=' ;
    i := !i + 3
  done ;
  Buffer.contents buf

(** Encode text as OSC 52 escape sequence for clipboard.
    Format: ESC ] 52 ; c ; <base64> BEL
    - "c" specifies the clipboard selection (system clipboard)
    - base64-encoded payload is the text to copy
    - BEL (\007) is more widely supported than ESC \ as terminator *)
let osc52_encode text =
  let b64 = base64_encode text in
  Printf.sprintf "\027]52;c;%s\007" b64

(** Try to copy using native clipboard tools (wl-copy, xclip, pbcopy).
    Returns true if a tool was found and executed. *)
let copy_native text =
  (* Try clipboard tools in order of preference *)
  let tools =
    [
      ("wl-copy", [|"wl-copy"; "--"|]);
      (* Wayland *)
      ("xclip", [|"xclip"; "-selection"; "clipboard"|]);
      (* X11 *)
      ("xsel", [|"xsel"; "--clipboard"; "--input"|]);
      (* X11 alternative *)
      ("pbcopy", [|"pbcopy"|]);
      (* macOS *)
    ]
  in
  let try_tool (cmd, argv) =
    try
      (* Check if command exists *)
      let which_status =
        Unix.system (Printf.sprintf "which %s >/dev/null 2>&1" cmd)
      in
      if which_status <> Unix.WEXITED 0 then false
      else begin
        (* Create pipe and fork *)
        let pipe_read, pipe_write = Unix.pipe () in
        match Unix.fork () with
        | 0 ->
            (* Child process *)
            Unix.close pipe_write ;
            Unix.dup2 pipe_read Unix.stdin ;
            Unix.close pipe_read ;
            (try Unix.execvp cmd argv with _ -> ()) ;
            exit 1
        | pid ->
            (* Parent process *)
            Unix.close pipe_read ;
            let _ =
              Unix.write_substring pipe_write text 0 (String.length text)
            in
            Unix.close pipe_write ;
            let _, status = Unix.waitpid [] pid in
            status = Unix.WEXITED 0
      end
    with _ -> false
  in
  List.exists try_tool tools

let register ~write ?on_copy ?(enabled = true) () =
  let copy_fn =
    if enabled then (fun text ->
      (* Try native clipboard first, fall back to OSC 52 *)
      if not (copy_native text) then write (osc52_encode text) ;
      match on_copy with Some f -> f text | None -> ())
    else fun _ -> ()
  in
  let cap : t = {copy = copy_fn; copy_available = (fun () -> enabled)} in
  set cap
