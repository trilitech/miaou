(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(** Generic multi-step wizard.

    A wizard drives a user through an ordered sequence of named {!step}s. The
    wizard owns navigation, breadcrumb rendering, validation and final / cancel
    state; each step owns the rendering and key handling of its own content
    via the polymorphic [`'state`] payload.

    {b Reserved keys} (intercepted by the wizard before any step sees them):
    - [Enter] — validate the current step and advance, or finish on the last
      step.
    - [Escape] / [Esc] — cancel the wizard.
    - [C-Left] / [Shift-Tab] — go to the previous step (no-op on the first).

    Any other key is forwarded to {!step.on_key}, so a step can compose any
    input widgets.
*)

(** A single wizard step, parameterised by the wizard's user state ['state]. *)
type 'state step = {
  title : string;  (** Short title shown in the breadcrumb bar. *)
  render : 'state -> focus:bool -> size:LTerm_geom.size -> string;
      (** Render the step body. The wizard adds chrome (breadcrumbs, error,
          nav hints) above and below. *)
  validate : 'state -> (unit, string) result;
      (** Decide whether [Enter] may advance from this step. Returning
          [Error msg] surfaces the message in red below the step body and
          keeps the wizard on the same step. *)
  on_key : 'state -> key:string -> 'state;
      (** Handle a key forwarded by the wizard. Pure state transformer. *)
}

(** Wizard widget. Opaque. *)
type 'state t

(** {1 Construction} *)

(** Create a wizard with the given non-empty step array and initial user
    state. Raises [Invalid_argument] if [steps] is empty. *)
val create : steps:'state step array -> initial:'state -> 'state t

(** {1 Rendering} *)

(** Render the wizard: breadcrumb bar, current step body, optional validation
    error, and a navigation-hint line at the bottom. *)
val render : 'state t -> focus:bool -> size:LTerm_geom.size -> string

(** {1 Input handling} *)

(** Handle a key event. Reserved keys (Enter / Escape / C-Left / Shift-Tab)
    drive navigation; all other keys are forwarded to the current step. *)
val handle_key : 'state t -> key:string -> 'state t

(** Advance to the next step (or set [is_finished] on the last step) only if
    the current step's [validate] succeeds. Identical effect to pressing
    [Enter]. *)
val advance : 'state t -> 'state t

(** Move to the previous step. No-op on the first step. *)
val back : 'state t -> 'state t

(** Mark the wizard as cancelled. *)
val cancel : 'state t -> 'state t

(** {1 Inspection} *)

(** The current user state. *)
val state : 'state t -> 'state

(** Replace the user state without changing step position. *)
val set_state : 'state t -> 'state -> 'state t

(** Index of the current step (0-based). *)
val current_index : 'state t -> int

(** Number of steps. *)
val step_count : 'state t -> int

(** Title of the current step. *)
val current_title : 'state t -> string

(** [true] once the user has successfully advanced past the last step. *)
val is_finished : 'state t -> bool

(** [true] once the user pressed [Escape] (or {!cancel} was called). *)
val is_cancelled : 'state t -> bool

(** The validation error from the last failed advance attempt, if any. *)
val current_error : 'state t -> string option
