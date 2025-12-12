(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)
open Eio.Std

module type RUNTIME = sig
  val env : Eio_unix.Stdenv.base

  val sw : Eio.Switch.t
end

let runtime : (module RUNTIME) option ref = ref None

let init ~env ~sw =
  runtime :=
    Some
      (module struct
        let env = env

        let sw = sw
      end)

let env_opt () =
  match !runtime with Some (module R) -> Some R.env | None -> None

let switch_opt () =
  match !runtime with Some (module R) -> Some R.sw | None -> None

let require_runtime () =
  match !runtime with
  | Some (module R) -> (R.env, R.sw)
  | None ->
      invalid_arg
        "Fiber runtime not initialized; call Fiber_runtime.init from \
         Eio_main.run"

let with_env f =
  match env_opt () with
  | Some env -> f env
  | None ->
      invalid_arg
        "Fiber runtime not initialized; call Fiber_runtime.init from \
         Eio_main.run"

let spawn f =
  let env, sw = require_runtime () in
  Fiber.fork ~sw (fun () -> f env) |> ignore

let sleep seconds = with_env (fun env -> Eio.Time.sleep env#clock seconds)
