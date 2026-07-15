(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

let is_loopback host =
  match host with "127.0.0.1" | "::1" | "localhost" -> true | _ -> false

type refusal = No_auth_on_public_bind of {bind : string}

let refusal_message = function
  | No_auth_on_public_bind {bind} ->
      Printf.sprintf
        "miaou serve: refusing to bind %s without an auth token (fail-closed \
         default). Pass --auth-token/--auth-file, bind to 127.0.0.1, or pass \
         --insecure-allow-plaintext-external to explicitly accept the risk \
         (see docs/serve.md)."
        bind

let check ~bind ~has_auth ~insecure_allow_plaintext_external =
  if is_loopback bind then Ok ()
  else if has_auth || insecure_allow_plaintext_external then Ok ()
  else Error (No_auth_on_public_bind {bind})
