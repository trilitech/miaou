(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

(* Functor that wraps a page and adds tutorial support.

   Usage:

   module Inner = struct
     let tutorial_title = "My Demo"
     let tutorial_markdown = [%blob "README.md"]

     type state = { ... ; next_page : string option }
     type msg = ...

     let init () = ...
     let view s ~focus ~size = ...
     let handle_key s key_str ~size = ...
     (* etc. *)
   end

   module Page = Demo_page.Make(Inner)
*)

module type DEMO_PAGE_INPUT = sig
  (** Title shown in the tutorial modal *)
  val tutorial_title : string

  (** Markdown content for the tutorial (use [%blob "README.md"]) *)
  val tutorial_markdown : string

  (** The inner page state *)
  type state

  type msg

  val init : unit -> state

  val update : state -> msg -> state

  val view : state -> focus:bool -> size:LTerm_geom.size -> string

  val handle_key : state -> string -> size:LTerm_geom.size -> state

  val move : state -> int -> state

  val refresh : state -> state

  val enter : state -> state

  val service_select : state -> int -> state

  val service_cycle : state -> int -> state

  val handle_modal_key : state -> string -> size:LTerm_geom.size -> state

  val next_page : state -> string option

  val keymap : state -> (string * (state -> state) * string) list

  val handled_keys : unit -> Miaou.Core.Keys.t list

  val back : state -> state

  val has_modal : state -> bool
end

module Make (P : DEMO_PAGE_INPUT) : Miaou.Core.Tui_page.PAGE_SIG = struct
  type state = P.state

  type msg = P.msg

  let init = P.init

  let update = P.update

  let view = P.view

  let move = P.move

  let refresh = P.refresh

  let enter = P.enter

  let service_select = P.service_select

  let service_cycle = P.service_cycle

  let handle_modal_key = P.handle_modal_key

  let next_page = P.next_page

  let keymap = P.keymap

  let handled_keys = P.handled_keys

  let back = P.back

  let has_modal = P.has_modal

  let show_tutorial () =
    Tutorial_modal.show ~title:P.tutorial_title ~markdown:P.tutorial_markdown ()

  let handle_key s key_str ~size =
    match Miaou.Core.Keys.of_string key_str with
    | Some (Miaou.Core.Keys.Char k) when String.lowercase_ascii k = "t" ->
        show_tutorial () ;
        s
    | _ -> P.handle_key s key_str ~size
end
