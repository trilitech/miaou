(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)
(* (c) 2025 Nomadic Labs <contact@nomadic-labs.com> *)

(** Lightweight networking capability (injected by the executable).
		Core only provides the typed API and relies on Capability to fetch it. *)

type t = {
  (* Fetch the content of the given URL as text. Returns Error with a
		 human-readable message on failure. Implementations should use short
		 timeouts to avoid freezing the TUI. *)
  get_url : url:string -> (string, string) result;
}

(** Unique typed key for the Net capability. *)
val key : t Miaou_interfaces.Capability.key

val set : t -> unit

val get : unit -> t option

(** Register, retrieve, or require the Net capability implementation. *)
val require : unit -> t
