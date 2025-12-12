(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)
(** Simple shared Eio runtime helpers.

    The application must call {!init} once from inside [Eio_main.run] to
    provide the standard environment and a long-lived switch. *)

val init : env:Eio_unix.Stdenv.base -> sw:Eio.Switch.t -> unit

val env_opt : unit -> Eio_unix.Stdenv.base option

val switch_opt : unit -> Eio.Switch.t option

(** @raise Invalid_argument if the runtime is not initialized *)
val require_runtime : unit -> Eio_unix.Stdenv.base * Eio.Switch.t

val with_env : (Eio_unix.Stdenv.base -> 'a) -> 'a

val spawn : (Eio_unix.Stdenv.base -> unit) -> unit

val sleep : float -> unit
