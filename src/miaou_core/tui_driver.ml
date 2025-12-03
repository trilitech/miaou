(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

[@@@warning "-32-34-37-69"]

open Tui_page (* Added this line *)

type t = private T

(* Local alias for outcome to ensure compilation when mli changes are applied *)
type outcome = [`Quit | `SwitchTo of string]

let size () = (Obj.magic 0 : t)

let poll_event () = "" (* placeholder synchronous event *)

let draw_text s =
  print_string s ;
  flush stdout

let clear () =
  print_string "\027[2J" ;
  flush stdout

let flush () = ()

(* Added page management logic *)
let current_page : (module PAGE_SIG) option ref = ref None

let set_page (page_module : (module PAGE_SIG)) =
  current_page := Some page_module

let run (initial_page : (module PAGE_SIG)) : outcome =
  (* Delegate to the real interactive driver (lambda_term_driver). We keep a
     tail‑recursive loop to follow `SwitchTo` signals until a final `Quit`. *)
  let rec loop (page : (module PAGE_SIG)) : outcome =
    match Lambda_term_driver.run page with
    | `Quit -> `Quit
    | `SwitchTo "__BACK__" -> `Quit (* demo/back semantics: exit demo *)
    | `SwitchTo next -> (
        (* Look up the next page in the registry; if absent, quit gracefully. *)
        match Registry.find next with
        | Some p -> loop p
        | None -> `Quit)
  in
  loop initial_page

let () =
  ignore size ;
  ignore poll_event ;
  ignore draw_text ;
  ignore clear ;
  ignore flush
