(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

(** Effect-based style context for implicit theme access.
    
    This module provides a way to access the current theme and style context
    without explicitly threading it through all function calls. It uses OCaml 5
    effects for this purpose.
    
    Usage:
    {[
    (* At application startup or driver level *)
    Style_context.with_theme (Theme_loader.load ()) (fun () ->
      (* In any nested code, theme is accessible *)
      let theme = Style_context.current_theme () in
      ...
    )
    
    (* Or use convenience functions *)
    let my_view () =
      let border_style = Style_context.border ~focus:true in
      let text_style = Style_context.primary () in
      ...
    ]}
    
    Widgets can also push their own context for their children:
    {[
    let render_children children =
      children |> List.mapi (fun i child ->
        Style_context.with_child_context 
          ~index:i 
          ~count:(List.length children)
          ~ancestors:[widget_name]
          (fun () -> child.render ())
      )
    ]}
*)

(** {2 Theme effects} *)

(** Effect for getting the current theme *)
type _ Effect.t += Get_theme : Theme.t Effect.t

(** Effect for getting the current match context (for selector matching) *)
type _ Effect.t += Get_match_context : Selector.match_context Effect.t

(** {2 Running with context} *)

(** Run a computation with a specific theme.
    This sets up the effect handler for theme access. *)
val with_theme : Theme.t -> (unit -> 'a) -> 'a

(** Run a computation with both theme and match context *)
val with_context : Theme.t -> Selector.match_context -> (unit -> 'a) -> 'a

(** Run a computation with updated match context (for child widgets).
    Inherits the current theme. *)
val with_child_context :
  ?widget_name:string ->
  ?focused:bool ->
  ?selected:bool ->
  ?index:int ->
  ?count:int ->
  ?ancestors:string list ->
  (unit -> 'a) ->
  'a

(** {2 Accessing current context} *)

(** Get the current theme. Returns [Theme.default] if no handler is installed. *)
val current_theme : unit -> Theme.t

(** Get the current match context. Returns [Selector.empty_context] if no handler. *)
val current_context : unit -> Selector.match_context

(** {2 Convenience style accessors} *)

(** Get resolved style for current context (applies all matching rules) *)
val current_style : unit -> Theme.widget_style

(** Get a semantic style from the theme *)
val primary : unit -> Style.t

val secondary : unit -> Style.t

val accent : unit -> Style.t

val error : unit -> Style.t

val warning : unit -> Style.t

val success : unit -> Style.t

val info : unit -> Style.t

val text : unit -> Style.t

val text_muted : unit -> Style.t

val text_emphasized : unit -> Style.t

val background : unit -> Style.t

val background_secondary : unit -> Style.t

val selection : unit -> Style.t

(** Get border style, optionally based on focus state *)
val border : ?focus:bool -> unit -> Style.t

(** Get the default border style (character set) *)
val default_border_style : unit -> Border.style

(** {2 Higher-level helpers} *)

(** Apply current style to a string *)
val styled : string -> string

(** Apply a semantic style to a string *)
val styled_with : Style.t -> string -> string

(** Get style for a named widget, applying all matching rules *)
val widget_style : string -> Theme.widget_style
