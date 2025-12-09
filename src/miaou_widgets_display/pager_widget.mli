(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(** Scrollable text pager widget with search and streaming support.

    This widget provides a full-featured text viewer with:
    - Scrolling (Up/Down, PageUp/PageDown, Home/End)
    - Search with regex support (/, n/N for next/prev match)
    - Follow mode for streaming logs
    - Batched appends for performance
    - Line wrapping support
    - JSON syntax highlighting (optional)

    {b Typical usage}:
    {[
      (* Create a pager from text *)
      let pager = Pager_widget.open_text ~title:"Logs" "Line 1\nLine 2\nLine 3" in

      (* Or from lines *)
      let pager = Pager_widget.open_lines ~title:"Output" ["Line 1"; "Line 2"] in

      (* Render in your view *)
      let view state ~size ~focus =
        Pager_widget.render_with_size ~size pager ~focus

      (* Handle keyboard input *)
      let handle_key state ~key ~size =
        let pager', consumed = Pager_widget.handle_key pager ~key in
        if consumed then {state with pager = pager'} else ...

      (* For streaming logs, use batched appends *)
      let pager = Pager_widget.start_streaming pager in
      Pager_widget.append_text_batched pager "new log line\n" ;
      (* pager automatically flushes pending lines on render *)
    ]}
*)

(** The pager state.

    This type is opaque - use the provided functions to create and manipulate
    pager instances. Internal state includes scroll position, lines, search
    query, and streaming buffers.
*)
type t = {
  title : string option;
  mutable lines : string list;
  mutable offset : int;
  mutable follow : bool;
  mutable streaming : bool;
  mutable spinner_pos : int;
  mutable pending_lines : string list;
  mutable pending_rev : string list;
  mutable pending_dirty : bool;
  mutable cached_body : string option;
  mutable last_flush : float;
  mutable flush_interval_ms : int;
  mutable search : string option;
  mutable is_regex : bool;
  mutable input_mode : [`None | `Search_edit | `Lookup];
  mutable input_buffer : string;
  mutable input_pos : int;
}

(** {1 Creation} *)

(** Create a pager from a list of lines.

    @param title Optional title displayed at the top
    @param lines Initial list of lines to display
*)
val open_lines : ?title:string -> string list -> t

(** Create a pager from text (splits on newlines).

    @param title Optional title displayed at the top
    @param text Text content (will be split on '\\n')
*)
val open_text : ?title:string -> string -> t

(** {1 Content Updates} *)

(** Append lines immediately (synchronous).

    Lines are added to the pager's content right away. For high-frequency
    updates from background threads, prefer {!append_lines_batched}.

    @param lines Lines to append
*)
val append_lines : t -> string list -> unit

(** Append text immediately (synchronous).

    Text is split on newlines and appended. For high-frequency updates,
    prefer {!append_text_batched}.

    @param text Text to append (will be split on '\\n')
*)
val append_text : t -> string -> unit

(** Append lines in batched mode (for streaming/performance).

    Lines are buffered and flushed at a limited rate (default: 200ms intervals)
    to avoid excessive rendering. Useful for streaming logs from background
    threads.

    Note: Call {!start_streaming} first to enable streaming mode.

    @param lines Lines to append to the pending buffer
*)
val append_lines_batched : t -> string list -> unit

(** Append text in batched mode (for streaming/performance).

    Text is split on newlines and added to the pending buffer. Flushed
    at limited rate during rendering.

    @param text Text to append (will be split on '\\n')
*)
val append_text_batched : t -> string -> unit

(** {1 Streaming Mode} *)

(** Enable streaming mode with spinner animation.

    In streaming mode:
    - Spinner shows activity
    - Batched appends are buffered
    - Automatic flush at limited rate
    - Follow mode available

    Typical usage: enable before starting a background task that will
    call {!append_text_batched} repeatedly.
*)
val start_streaming : t -> unit

(** Disable streaming mode and flush all pending lines.

    Stops the spinner animation and ensures all buffered lines are
    displayed immediately.
*)
val stop_streaming : t -> unit

(** Flush pending batched lines if needed.

    Manually triggers a flush of buffered lines. Normally called
    automatically during rendering.

    @param force If true, flushes regardless of interval timer
*)
val flush_pending_if_needed : ?force:bool -> t -> unit

(** {1 Navigation} *)

(** Set the scroll offset (line number at top of viewport).

    @param offset Line number to scroll to (0-indexed)
    @return New pager with updated offset
*)
val set_offset : t -> int -> t

(** {1 Search} *)

(** Set search query and jump to first match.

    Resets offset to 0 and highlights all matching lines.

    @param query Search string (supports regex if configured)
    @return New pager with search query set
*)
val set_search : t -> string option -> t

(** {1 Rendering} *)

(** Render the pager with explicit window size.

    @param cols Terminal width in columns (optional, for wrapping)
    @param wrap Enable line wrapping (default: true)
    @param win Visible window height in lines
    @param focus Whether the pager has focus (affects styling)
    @return Rendered string
*)
val render : ?cols:int -> ?wrap:bool -> win:int -> t -> focus:bool -> string

(** Render with size-aware window calculation.

    Convenience wrapper that extracts window size from LambdaTerm size record.

    @param size Terminal/window size
    @param focus Whether the pager has focus
    @return Rendered string
*)
val render_with_size : size:'a -> t -> focus:bool -> string

(** {1 Input Handling} *)

(** Handle keyboard input.

    Processes navigation keys, search commands, and other pager controls.

    Supported keys:
    - [Up]/[Down]: Scroll by line
    - [PageUp]/[PageDown]: Scroll by page
    - [Home]/[End]: Jump to start/end
    - [/]: Enter search mode
    - [n]/[N]: Next/previous search match
    - [f]: Toggle follow mode

    @param win Visible window height in lines (optional)
    @param key Key string (e.g., "Up", "Down", "/", "n")
    @return Tuple of (updated pager, consumed flag). If consumed is true,
            the key was handled by the pager. If false, the key should be
            processed by the parent.
*)
val handle_key : ?win:int -> t -> key:string -> t * bool

(** {1 JSON Streaming (Advanced)} *)

(** JSON streamer state for incremental parsing with syntax highlighting *)
type json_streamer

(** Create a new JSON streamer for incremental parsing. *)
val json_streamer_create : unit -> json_streamer

(** Feed a chunk of JSON to the streamer.

    Returns newly completed, colorized lines.

    @param chunk Raw JSON text chunk
    @return List of completed, syntax-highlighted lines
*)
val json_streamer_feed : json_streamer -> string -> string list

(** {1 Background Notification} *)

(** Set callback for requesting renders from background threads.

    The pager can notify the UI driver when new content is available,
    allowing responsive updates without polling.

    @param callback Optional callback to invoke when render is needed
                     (typically set by the driver)
*)
val set_notify_render : (unit -> unit) option -> unit
