(*****************************************************************************
 *                                                                           *
 * SPDX-License-Identifier: MIT                                              *
 * Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *
 *                                                                           *
 *****************************************************************************)

[@@@warning "-32-34-37-69"]

open Miaou_core.Tui_page
module Widgets = Miaou_widgets_display.Widgets
module Registry = Miaou_core.Registry

(* Local alias for outcome to ensure compilation when mli changes are applied *)
type outcome = [`Quit | `Back | `SwitchTo of string]

type backend = {available : bool; run : (module PAGE_SIG) -> outcome}

(* [type t = private T] plus a [(Obj.magic 0 : t)] "dummy private type"
   stub used to live here as a placeholder driver-interface shape. It was
   never constructed by any real value and had no legitimate producer,
   only this fabricated one — a textbook Obj.magic misuse with no safety
   justification (crash-ub-fixes slice S8). Removed; nothing referenced
   [t] or [size] outside this module. *)

let poll_event () = "" (* placeholder synchronous event *)

let draw_text s =
  (print_string [@allow_forbidden "terminal driver writes to stdout"]) s ;
  flush stdout

let clear () =
  (print_string [@allow_forbidden "terminal driver writes escape sequences"])
    "\027[2J" ;
  flush stdout

let flush () = ()

let current_page : (module PAGE_SIG) option ref = ref None

let set_page (page_module : (module PAGE_SIG)) =
  current_page := Some page_module

let backend_choice ~sdl_available ~matrix_available ~web_available =
  match Sys.getenv_opt "MIAOU_DRIVER" with
  | Some v -> (
      match String.lowercase_ascii (String.trim v) with
      | "matrix" when matrix_available -> `Matrix
      | "sdl" when sdl_available -> `Sdl
      | "term" | "lambda-term" | "lambda_term" -> `Lambda_term
      | "web" when web_available -> `Web
      | "html" when Html_driver.available -> `Html
      | _ -> `Matrix (* Default to matrix for unknown values too *))
  | None ->
      (* Default priority: Matrix > SDL > Lambda_term *)
      if matrix_available then `Matrix
      else if sdl_available then `Sdl
      else `Lambda_term

let run ~term_backend ~sdl_backend ~matrix_backend ~web_backend
    (initial_page : (module PAGE_SIG)) : outcome =
  Widgets.set_backend `Terminal ;
  (* Page stack for Back navigation *)
  let page_stack = ref [] in
  let rec loop (page : (module PAGE_SIG)) : outcome =
    let outcome =
      match
        backend_choice
          ~sdl_available:sdl_backend.available
          ~matrix_available:matrix_backend.available
          ~web_available:web_backend.available
      with
      | `Matrix ->
          Widgets.set_backend `Terminal ;
          matrix_backend.run page
      | `Sdl ->
          Widgets.set_backend `Sdl ;
          sdl_backend.run page
      | `Web ->
          Widgets.set_backend `Terminal ;
          web_backend.run page
      | `Html ->
          Widgets.set_backend `Terminal ;
          Html_driver.run page
      | `Lambda_term ->
          Widgets.set_backend `Terminal ;
          term_backend.run page
    in
    match outcome with
    | `Quit -> `Quit
    | `Back -> (
        match !page_stack with
        | [] -> `Quit (* No history, quit *)
        | prev :: rest ->
            page_stack := rest ;
            loop prev)
    | `SwitchTo next -> (
        match Registry.find next with
        | Some p ->
            page_stack := page :: !page_stack ;
            loop p
        | None -> `Quit)
  in
  let _result = loop initial_page in
  (* Shutdown fibers and exit to avoid Eio.Switch.run waiting for them.
     Kept deliberately (crash-ub-fixes plan, D11): [Fiber_runtime.shutdown]
     does not cancel any outstanding fiber, so removing this hard [exit 0]
     would make the process hang waiting for [Eio.Switch.run] to close over
     fibers that are never asked to stop (e.g. a reader fiber blocked in a
     blocking await with no more input). Replacing it with a graceful
     return requires a real fiber-cancellation design and is deferred to
     the structural-debt backlog, not fixed piecemeal here. *)
  exit 0

let () =
  ignore poll_event ;
  ignore draw_text ;
  ignore clear ;
  ignore flush
