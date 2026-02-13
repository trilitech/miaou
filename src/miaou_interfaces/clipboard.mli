(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(** Clipboard capability — copy text to the system clipboard via OSC 52.

    OSC 52 is a terminal escape sequence that allows terminal applications
    to set the system clipboard contents. It is supported by most modern
    terminals including:
    - iTerm2
    - Alacritty
    - kitty
    - WezTerm
    - tmux (with [set-clipboard on])
    - Windows Terminal

    {b Usage in pages / widgets}:
    {[
      let clipboard = Clipboard.require () in
      clipboard.copy "Hello, world!"
    ]}

    {b Usage in drivers}:
    {[
      Clipboard.register ~write:(fun s -> output_string stdout s; flush stdout)
    ]}

    {b Note}: Reading from clipboard (paste) is not supported because it
    requires asynchronous terminal responses. Use the terminal's native
    paste (Ctrl+Shift+V or Cmd+V) which sends text as regular key input.
*)

(** The clipboard interface exposed to pages and widgets. *)
type t = {
  copy : string -> unit;
      (** Copy the given text to the system clipboard using OSC 52.
          If a toast callback was registered, shows a brief notification. *)
  copy_available : unit -> bool;
      (** Returns [true] if OSC 52 clipboard support is enabled.
          May return [false] if the driver doesn't support it or if
          clipboard was explicitly disabled. *)
}

(** {1 Capability access} *)

val key : t Capability.key

val set : t -> unit

val get : unit -> t option

val require : unit -> t

(** {1 Driver-side API} *)

(** Register the clipboard capability.
    @param write Function to write raw output to the terminal
    @param on_copy Optional callback invoked after each copy with the copied
           text. Use this to show a toast notification, e.g.:
           [~on_copy:(fun _text -> Toast_widget.enqueue toasts Success "Copied!")]
    @param enabled Whether clipboard support is enabled (default: true) *)
val register :
  write:(string -> unit) ->
  ?on_copy:(string -> unit) ->
  ?enabled:bool ->
  unit ->
  unit

(** Encode text as an OSC 52 escape sequence.
    Exported for testing. The sequence format is:
    [ESC ] 52 ; c ; <base64-encoded-text> BEL]
    BEL (0x07) is used as terminator for wider terminal compatibility. *)
val osc52_encode : string -> string
