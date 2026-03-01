(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(* Copyright (c) 2026 Mathias Bourgoin <mathias.bourgoin@atacama.tech>       *)
(*                                                                           *)
(*****************************************************************************)

(* SDL-specific render entrypoint kept in its own module to keep backend code
   split from the terminal spinner implementation. *)

let render (t : Spinner_widget.t) : string =
  Spinner_widget.render_with_backend `Sdl t

[@@@enforce_exempt] (* non-widget module *)
