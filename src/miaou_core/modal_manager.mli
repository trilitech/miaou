(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

[@@@warning "-32-34-37-69"]

type outcome = [`Commit | `Cancel]

type ui = {
  title : string;
  left : int option;
  max_width : int option;
  dim_background : bool;
}

val has_active : unit -> bool

val clear : unit -> unit

val push :
  (module Tui_page.PAGE_SIG with type state = 's) ->
  init:'s ->
  ui:ui ->
  commit_on:string list ->
  cancel_on:string list ->
  on_close:('s -> outcome -> unit) ->
  unit

val handle_key : string -> unit

(* Convenience wrapper: push with sensible defaults for UI and keys.
  - title: modal title shown in header
  - left/max_width/dim_background: optional ui overrides
  - commit_on/cancel_on: default to ["Enter"] / ["Esc"]
  This avoids repeating the common ui/keys boilerplate at call sites.
*)
val push_default :
  (module Tui_page.PAGE_SIG with type state = 's) ->
  init:'s ->
  ui:ui ->
  on_close:('s -> outcome -> unit) ->
  unit

val set_current_size : int -> int -> unit

(* Get the last known terminal size (rows, cols) as published by the driver. *)
val get_current_size : unit -> int * int

(* Mark that the next key used to close a modal should be consumed by the
  driver and not propagated to the underlying page. *)
val set_consume_next_key : unit -> unit

(* Read and clear the consume-next-key flag. Returns true exactly once after
  it was set. *)
val take_consume_next_key : unit -> bool

(* Access the UI metadata for the top-most modal, if any. *)
val top_ui_opt : unit -> ui option

(* Return the title of the top-most modal, if any. *)
val top_title_opt : unit -> string option

(* Programmatically close the top-most modal with the given outcome, invoking
  its on_close callback. No-op if no modal is active. *)
val close_top : outcome -> unit

(* Higher-level convenience helpers. These are thin wrappers around existing
   modal pages that simplify common patterns: alerts (message-only),
   confirm (yes/no via a select modal), and prompt (textbox). They accept a
   small callback invoked with the result. These helpers do not block the
   caller; they integrate with the existing modal on_close callback model. *)

val alert :
  (module Tui_page.PAGE_SIG with type state = 's) ->
  init:'s ->
  ?title:string ->
  ?left:int ->
  ?max_width:int ->
  ?dim_background:bool ->
  unit ->
  unit

val confirm :
  (module Tui_page.PAGE_SIG with type state = 's) ->
  init:'s ->
  ?title:string ->
  ?left:int ->
  ?max_width:int ->
  ?dim_background:bool ->
  on_result:(bool -> unit) ->
  unit ->
  unit

val confirm_with_extract :
  (module Tui_page.PAGE_SIG with type state = 's) ->
  init:'s ->
  ?title:string ->
  ?left:int ->
  ?max_width:int ->
  ?dim_background:bool ->
  extract:('s -> 'a option) ->
  on_result:('a option -> unit) ->
  unit ->
  unit

val prompt :
  (module Tui_page.PAGE_SIG with type state = 's) ->
  init:'s ->
  ?title:string ->
  ?left:int ->
  ?max_width:int ->
  ?dim_background:bool ->
  extract:('s -> 'a option) ->
  on_result:('a option -> unit) ->
  unit ->
  unit
