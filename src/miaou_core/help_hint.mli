(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)
(** A hint can provide independent [short] and [long] variants. The driver
    selects which one to render based on available width, preferring [long]
    when the layout is wide enough, falling back to [short] otherwise. *)
type hint = {short : string option; long : string option}

(** Set the active hint (both variants) replacing any existing hints. Passing
    [None] clears all hints. For backward compatibility, [set (Some s)] sets
    the short variant to [s] and clears the long variant. *)
val set : string option -> unit

(** Clear all hints. *)
val clear : unit -> unit

(** Push a new hint on top of the stack. Use this when opening a sub-modal.
    Call [pop] in the modal's on_close callback to restore the previous hint. *)
val push : ?short:string -> ?long:string -> unit -> unit

(** Pop the most recently pushed hint. Safe to call even if the stack is empty. *)
val pop : unit -> unit

(** Get the currently active hint (top of stack), if any. *)
val get_active : unit -> hint option

(** Deprecated: returns only the short variant of the active hint. *)
val get : unit -> string option
