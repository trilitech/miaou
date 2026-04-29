(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(** Reusable prompt helpers built on top of {!Modal_manager}.

    These helpers wrap the boilerplate of building a small modal page and
    pushing it onto the modal stack. They mirror the patterns seen in the
    existing example modal modules ({i textbox_modal}, {i select_modal},
    {i password_textbox_modal}) so app code can ask for a yes/no answer, a
    free-form text value, or a list selection in one call.

    All three helpers are non-blocking: they push a modal and return
    immediately. The result is delivered asynchronously through [on_result]
    when the user commits or cancels.

    {b Typical usage}:
    {[
      Prompt.confirm
        ~title:"Delete file?"
        ~message:"This cannot be undone."
        ~on_result:(fun answered_yes ->
          if answered_yes then delete_file () else ())
        ()
    ]}
*)

(** Ask a yes / no question.

    Pushes a centred modal with [message] as the body. The modal commits
    on [Enter] (calling [on_result true]) and cancels on [Esc] (calling
    [on_result false]).

    @param title Title shown at the top of the modal.
    @param message Message body shown to the user.
    @param on_result Callback invoked exactly once with the user's answer.
*)
val confirm :
  title:string -> message:string -> on_result:(bool -> unit) -> unit -> unit

(** Ask the user to type a free-form string.

    Pushes a centred modal containing a single-line textbox. On commit
    ([Enter]) the callback receives [Some text]; on cancel ([Esc]) the
    callback receives [None].

    @param placeholder Optional placeholder shown when the textbox is empty.
    @param initial Initial textbox content (default: empty).
    @param title Title shown at the top of the modal.
    @param on_result Callback invoked exactly once.
*)
val input :
  ?placeholder:string ->
  ?initial:string ->
  title:string ->
  on_result:(string option -> unit) ->
  unit ->
  unit

(** Ask the user to pick one item from a list.

    Pushes a centred modal containing a {!Miaou_widgets_input.Select_widget}
    populated from [items]. On commit ([Enter]) the callback receives
    [Some item]; on cancel ([Esc]) the callback receives [None].

    @param title Title shown at the top of the modal.
    @param items List of items to choose from. May be empty (the user can
      only cancel in that case).
    @param to_string Function used to render each item as a row.
    @param on_result Callback invoked exactly once.
*)
val select :
  title:string ->
  items:'a list ->
  to_string:('a -> string) ->
  on_result:('a option -> unit) ->
  unit ->
  unit

(** {1 Pure helpers (testable without a TUI runtime)}

    These helpers implement the small bits of result-mapping logic used
    internally. They are exposed so unit tests can verify the behaviour
    without spinning up a modal stack. *)

(** [confirm_outcome `Commit] is [true] and [confirm_outcome `Cancel] is
    [false]. *)
val confirm_outcome : [`Commit | `Cancel] -> bool

(** Pure result mapping for {!input}.

    [input_result outcome ~text]:
    - [`Commit] yields [Some text].
    - [`Cancel] yields [None].
*)
val input_result : [`Commit | `Cancel] -> text:string -> string option

(** Pure result mapping for {!select}.

    [select_result outcome ~selected]:
    - [`Commit] yields [selected] (which is [Some _] when a row was selected,
      [None] when the list was empty).
    - [`Cancel] yields [None] regardless.
*)
val select_result : [`Commit | `Cancel] -> selected:'a option -> 'a option
