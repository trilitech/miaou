(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(** Static assets embedded at compile time. *)

let index_html = [%blob "static/index.html"]

let viewer_html = [%blob "static/viewer.html"]

let client_js = [%blob "static/client.js"]
