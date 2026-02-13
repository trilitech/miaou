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

(** Run a shell command with text written to a temp file.
    Uses temp file + shell redirection since piping stdin via
    create_process doesn't work reliably with wl-copy on Wayland
    (OCaml 5 domains prevent using fork). *)
let run_clipboard_cmd text cmd_fmt =
  try
    let tmp = Filename.temp_file "miaou_clip" ".txt" in
    let oc = open_out tmp in
    output_string oc text ;
    close_out oc ;
    let cmd = Printf.sprintf cmd_fmt (Filename.quote tmp) in
    let dev_null = Unix.openfile "/dev/null" [Unix.O_RDWR] 0 in
    let pid =
      Unix.create_process "sh" [|"sh"; "-c"; cmd|] dev_null dev_null dev_null
    in
    Unix.close dev_null ;
    (* Wait for shell to finish *)
    Unix.sleepf 0.15 ;
    let waited_pid, status = Unix.waitpid [Unix.WNOHANG] pid in
    let success =
      if waited_pid = 0 then begin
        (* Process still running - wait a bit more then assume success *)
        Unix.sleepf 0.1 ;
        true
      end
      else
        match status with
        | Unix.WEXITED 0 -> true
        | Unix.WEXITED _ | Unix.WSIGNALED _ | Unix.WSTOPPED _ -> false
    in
    (* Clean up temp file *)
    Unix.sleepf 0.05 ;
    (try Unix.unlink tmp with _ -> ()) ;
    success
  with _ -> false

(** Copy to system clipboard (Ctrl+V paste).
    Uses setsid to run wl-copy in a new session so it survives parent exit. *)
let copy_native text =
  run_clipboard_cmd text "setsid wl-copy < %s"
  || run_clipboard_cmd text "wl-copy < %s"
  || run_clipboard_cmd text "xclip -selection clipboard < %s"
  || run_clipboard_cmd text "xsel --clipboard --input < %s"
  || run_clipboard_cmd text "pbcopy < %s"

(** Copy to primary selection (middle-click paste).
    Uses setsid to run wl-copy in a new session so it survives parent exit. *)
let copy_primary text =
  run_clipboard_cmd text "setsid wl-copy --primary < %s"
  || run_clipboard_cmd text "wl-copy --primary < %s"
  || run_clipboard_cmd text "xclip -selection primary < %s"
  || run_clipboard_cmd text "xsel --primary --input < %s"
(* macOS doesn't have primary selection *)

(** Copy to both clipboard and primary selection. *)
let copy_both text =
  let _native_ok = copy_native text in
  let _primary_ok = copy_primary text in
  true

let register ~write ?on_copy ?(enabled = true) () =
  let copy_fn =
    if enabled then (fun text ->
      (* Copy to both clipboard and primary selection for middle-click paste.
         Fall back to OSC 52 if native tools unavailable. *)
      if not (copy_both text) then write (osc52_encode text) ;
      match on_copy with Some f -> f text | None -> ())
    else fun _ -> ()
  in
  let cap : t = {copy = copy_fn; copy_available = (fun () -> enabled)} in
  set cap
