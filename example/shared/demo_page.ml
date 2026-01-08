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

  type pstate = state Miaou.Core.Navigation.t

  let init () = Miaou.Core.Navigation.make (P.init ())

  let update ps msg = Miaou.Core.Navigation.update (fun s -> P.update s msg) ps

  let view ps ~focus ~size = P.view ps.Miaou.Core.Navigation.s ~focus ~size

  let move ps delta = Miaou.Core.Navigation.update (fun s -> P.move s delta) ps

  let refresh ps = Miaou.Core.Navigation.update P.refresh ps

  let service_select ps idx =
    Miaou.Core.Navigation.update (fun s -> P.service_select s idx) ps

  let service_cycle ps delta =
    Miaou.Core.Navigation.update (fun s -> P.service_cycle s delta) ps

  let handle_modal_key ps key_str ~size =
    Miaou.Core.Navigation.update
      (fun s -> P.handle_modal_key s key_str ~size)
      ps

  let keymap ps =
    List.map
      (fun (key, f, help) ->
        (key, (fun ps -> Miaou.Core.Navigation.update f ps), help))
      (P.keymap ps.Miaou.Core.Navigation.s)

  let handled_keys = P.handled_keys

  let back ps =
    let s' = P.back ps.Miaou.Core.Navigation.s in
    match P.next_page s' with
    | Some target -> Miaou.Core.Navigation.goto target ps
    | None -> Miaou.Core.Navigation.back ps

  let has_modal ps = P.has_modal ps.Miaou.Core.Navigation.s

  let show_tutorial () =
    Tutorial_modal.show ~title:P.tutorial_title ~markdown:P.tutorial_markdown ()

  let handle_key ps key_str ~size =
    match Miaou.Core.Keys.of_string key_str with
    | Some (Miaou.Core.Keys.Char k) when String.lowercase_ascii k = "t" ->
        show_tutorial () ;
        ps
    | _ -> (
        let s' = P.handle_key ps.Miaou.Core.Navigation.s key_str ~size in
        match P.next_page s' with
        | Some target -> Miaou.Core.Navigation.goto target {ps with s = s'}
        | None -> {ps with s = s'})
end
