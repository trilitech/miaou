(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

(** Multiline text input widget with cursor and scroll support.

    This widget provides a multiline text editor with:
    - Multiple line support with automatic scrolling
    - Shift+Enter to insert newlines (Enter is reserved for form submission)
    - Cursor navigation with arrow keys, Home, End
    - Line joining on backspace/delete at line boundaries
    - Placeholder text when empty
    - Line count indicator

    {b Typical usage}:
    {[
      (* Create a textarea *)
      let textarea = Textarea_widget.open_centered
        ~title:"Description"
        ~width:60
        ~height:8
        ~placeholder:(Some "Enter a description...")
        ()

      (* In your PAGE_SIG module *)
      let view state ~focus ~size =
        Textarea_widget.render state ~focus

      (* Handle keys - Shift+Enter for newlines, Enter for submit *)
      let handle_key state ~key ~size =
        match key with
        | "Enter" -> (* submit form *)
        | _ -> Textarea_widget.handle_key state ~key

      (* Extract the final text *)
      let text = Textarea_widget.get_text state
    ]}
*)

(** The textarea state. *)
type t

(** {1 Creation} *)

(** Create a new textarea with the specified configuration.

    @param title Optional title displayed above the textarea
    @param width Display width in characters (default: 60, minimum: 10)
    @param height Number of visible lines (default: 10, minimum: 3)
    @param initial Initial text content (may contain newlines)
    @param placeholder Optional placeholder text shown when empty (displayed dimmed)
*)
val create :
  ?title:string ->
  ?width:int ->
  ?height:int ->
  ?initial:string ->
  ?placeholder:string ->
  unit ->
  t

(** Alias for {!create}. *)
val open_centered :
  ?title:string ->
  ?width:int ->
  ?height:int ->
  ?initial:string ->
  ?placeholder:string ->
  unit ->
  t

(** {1 Rendering} *)

(** Render the textarea as a string for display.

    Returns a formatted string including:
    - Optional title
    - Border box with content
    - Cursor (shown as underscore [_])
    - Scroll indicator when content exceeds visible area
    - Line count indicator (e.g., "Line 3/10")

    @param focus Whether the widget has focus (currently unused)
*)
val render : t -> focus:bool -> string

(** {1 Input Handling} *)

(** Handle a keyboard input event.

    Supported keys:
    - [S-Enter] / [Shift-Enter]: Insert newline
    - Printable characters: Insert at cursor
    - [Backspace]: Delete before cursor (joins lines at boundary)
    - [Delete]: Delete at cursor (joins lines at boundary)
    - [Left]/[Right]: Move cursor (wraps at line boundaries)
    - [Up]/[Down]: Move between lines
    - [Home]: Move to start of line
    - [End]: Move to end of line
    - [Esc]/[Escape]: Mark as cancelled

    {b Note}: [Enter] is NOT handled - use it for form submission.

    @deprecated Use [on_key] for new code.
*)
val handle_key : t -> key:string -> t

(** Handle key with unified result type.
    Returns [Handled] for editing keys, [Bubble] for unknown keys. *)
val on_key : t -> key:string -> t * Miaou_interfaces.Key_event.result

(** {1 Text Access} *)

(** Get all text as a single string with newlines. *)
val get_text : t -> string

(** Alias for {!get_text}. *)
val value : t -> string

(** Set the text content. Cursor is adjusted if needed. *)
val set_text : t -> string -> t

(** {1 State Queries} *)

(** Check if the user pressed Esc/Escape. *)
val is_cancelled : t -> bool

(** Clear the cancelled flag. *)
val reset_cancelled : t -> t

(** Get cursor position as [(row, col)] (0-indexed). *)
val cursor_position : t -> int * int

(** Get total number of lines. *)
val line_count : t -> int

(** Get the display width. *)
val width : t -> int

(** Get the visible height (number of lines). *)
val height : t -> int

(** Set new dimensions. Width minimum: 10, height minimum: 3. *)
val with_dimensions : t -> width:int -> height:int -> t
