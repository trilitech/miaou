(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(** Animated spinner widget for indicating ongoing operations.

    This widget provides animated spinners with optional label,
    useful for showing that a background task is in progress.

    Two styles are available:
    - [Dots]: Classic braille dot spinner (⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
    - [Block]: Block cursor spinner inside a small box (renders as 3 lines)

    {b Typical usage}:
    {[
      (* Create a classic spinner *)
      let spinner = Spinner_widget.open_centered ~label:(Some "Loading...") () in

      (* Or create a block cursor spinner *)
      let spinner = Spinner_widget.open_centered ~style:Block ~label:(Some "Build") () in

      (* In your render loop, tick the spinner to advance animation *)
      let spinner' = Spinner_widget.tick spinner in
      let output = Spinner_widget.render spinner' in
      (* Dots: "⠋ Loading..." *)
      (* Block: "┌─┐\n│█│\n└─┘\nBuild" *)

      (* Update the label *)
      let spinner' = Spinner_widget.set_label spinner' (Some "Processing...") in
    ]}
*)

(** Spinner style variants *)
type style =
  | Dots  (** Classic braille dot spinner: ⠋ ⠙ ⠹ ⠸ ... (single line) *)
  | Block  (** Block cursor spinner: renders as 3x3 box with animated fill *)

(** The spinner state *)
type t

(** {1 Creation} *)

(** Create a centered spinner.

    @param label Optional label displayed after the spinner glyph
    @param width Maximum width in columns (content truncated if longer, default: 60)
    @param style Spinner style (default: [Dots])
*)
val open_centered : ?label:string -> ?width:int -> ?style:style -> unit -> t

(** {1 Animation} *)

(** Advance the spinner animation to the next frame.

    Call this repeatedly (e.g., on each render or timer tick) to
    animate the spinner. The spinner cycles through frames:
    - Unicode: ⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏ (10 frames)
    - ASCII: | / - \\ (4 frames)
*)
val tick : t -> t

(** {1 State Updates} *)

(** Set or update the label.

    @param label New label (use [Some "text"] to set, [None] to clear)
    @return Updated spinner with new label
*)
val set_label : t -> string option -> t

(** Change the spinner style.

    @param style New style ([Dots] or [Block])
    @return Updated spinner with new style
*)
val set_style : t -> style -> t

(** {1 Rendering} *)

(** Render the spinner.

    Returns a string with the current animation frame and label:
    - ["⠋ Loading..."] (Unicode mode)
    - ["| Loading..."] (ASCII mode)

    The output is automatically truncated to the configured width.

    @param backend Rendering backend (Terminal or SDL, default: current backend)
*)
val render : ?backend:Miaou_widgets_display.Widgets.backend -> t -> string

(** Render with explicit backend selection (advanced).

    @param backend Rendering backend to use
*)
val render_with_backend : Miaou_widgets_display.Widgets.backend -> t -> string
