(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

[@@@warning "-67"]

(** Direct page: effect-based page development on top of PAGE_SIG.

    Pages work with plain [state] (not [Navigation.t]) and use
    algebraic effects for navigation instead of manually threading
    [Navigation.t].

    {[
      module My_page = Direct_page.Make (Direct_page.With_defaults (struct
        type state = int
        let init () = 0
        let view n ~focus:_ ~size:_ = Printf.sprintf "Count: %d" n
        let on_key n key ~size:_ = match key with
          | "Up" -> n + 1
          | "q"  -> Direct_page.quit () ; n
          | _    -> n
      end))
    ]} *)

(** {1 Navigation effects}

    These functions perform algebraic effects that are caught by the
    [Make] functor and translated to [Navigation.goto/back/quit].
    Call them from [on_key], [on_modal_key], or [refresh]. *)

val navigate : string -> unit

val go_back : unit -> unit

val quit : unit -> unit

(** {1 Testing helper} *)

(** Run a function with navigation effect handlers installed.
    Returns the result and any captured navigation effect.
    Useful for unit-testing [on_key] directly. *)
val run : (unit -> 'a) -> 'a * [`Goto of string | `Back | `Quit] option

(** {1 Page definition} *)

(** Minimal input: the 3 functions every page must provide. *)
module type REQUIRED = sig
  type state

  val init : unit -> state

  val view : state -> focus:bool -> size:LTerm_geom.size -> string

  val on_key : state -> string -> size:LTerm_geom.size -> state
end

(** Full input with optional overrides (all have defaults). *)
module type FULL = sig
  include REQUIRED

  (** Display-only key hints for footer. *)
  val key_hints : state -> (string * string) list

  (** @deprecated Use [key_hints] instead. *)
  val keymap : state -> (string * string) list

  val refresh : state -> state

  val has_modal : state -> bool

  val on_modal_key : state -> string -> size:LTerm_geom.size -> state
end

(** Add sensible defaults for all optional functions. *)
module With_defaults (R : REQUIRED) : FULL with type state = R.state

(** Build a [PAGE_SIG] from a direct-page description.
    Installs effect handlers that translate [navigate]/[go_back]/[quit]
    calls into [Navigation.goto]/[Navigation.back]/[Navigation.quit]. *)
module Make (D : FULL) : Tui_page.PAGE_SIG
