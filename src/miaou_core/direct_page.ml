(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

type _ Effect.t +=
  | Navigate : string -> unit Effect.t
  | Go_back : unit Effect.t
  | Quit_app : unit Effect.t

let navigate page = Effect.perform (Navigate page)

let go_back () = Effect.perform Go_back

let quit () = Effect.perform Quit_app

let run f =
  let nav = ref None in
  let result =
    Effect.Deep.try_with
      f
      ()
      {
        effc =
          (fun (type a) (eff : a Effect.t) ->
            match eff with
            | Navigate page ->
                Some
                  (fun (k : (a, _) Effect.Deep.continuation) ->
                    nav := Some (`Goto page) ;
                    Effect.Deep.continue k ())
            | Go_back ->
                Some
                  (fun (k : (a, _) Effect.Deep.continuation) ->
                    nav := Some `Back ;
                    Effect.Deep.continue k ())
            | Quit_app ->
                Some
                  (fun (k : (a, _) Effect.Deep.continuation) ->
                    nav := Some `Quit ;
                    Effect.Deep.continue k ())
            | _ -> None);
      }
  in
  (result, !nav)

module type REQUIRED = sig
  type state

  val init : unit -> state

  val view : state -> focus:bool -> size:LTerm_geom.size -> string

  val on_key : state -> string -> size:LTerm_geom.size -> state
end

module type FULL = sig
  include REQUIRED

  val keymap : state -> (string * string) list

  val refresh : state -> state

  val has_modal : state -> bool

  val on_modal_key : state -> string -> size:LTerm_geom.size -> state
end

module With_defaults (R : REQUIRED) : FULL with type state = R.state = struct
  include R

  let keymap _ = []

  let refresh s = s

  let has_modal _ = false

  let on_modal_key s _ ~size:_ = s
end

module Make (D : FULL) : Tui_page.PAGE_SIG = struct
  type state = D.state

  type msg = unit

  type key_binding = state Tui_page.key_binding_desc

  type pstate = state Navigation.t

  let init () = Navigation.make (D.init ())

  let update ps _ = ps

  let view ps ~focus ~size = D.view ps.Navigation.s ~focus ~size

  let with_nav ps f =
    let s', nav = run (fun () -> f ps.Navigation.s) in
    let ps' = {ps with Navigation.s = s'} in
    match nav with
    | Some (`Goto page) -> Navigation.goto page ps'
    | Some `Back -> Navigation.back ps'
    | Some `Quit -> Navigation.quit ps'
    | None -> ps'

  let handle_key ps key ~size = with_nav ps (fun s -> D.on_key s key ~size)

  let handle_modal_key ps key ~size =
    with_nav ps (fun s -> D.on_modal_key s key ~size)

  let refresh ps = with_nav ps (fun s -> D.refresh s)

  let keymap ps =
    List.map
      (fun (key, help) ->
        {Tui_page.key; action = Fun.id; help; display_only = true})
      (D.keymap ps.Navigation.s)

  let has_modal ps = D.has_modal ps.Navigation.s

  let move ps _ = ps

  let service_select ps _ = ps

  let service_cycle ps _ = ps

  let back ps = Navigation.back ps

  let handled_keys () = []
end
