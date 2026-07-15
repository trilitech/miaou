(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

module Dummy_page : Miaou_core.Tui_page.PAGE_SIG with type state = unit = struct
  type state = unit

  type key_binding = state Miaou_core.Tui_page.key_binding_desc

  type pstate = state Miaou_core.Navigation.t

  type msg = unit

  module Consuming_modal : Miaou_core.Tui_page.PAGE_SIG = struct
    type state = unit

    type key_binding = state Miaou_core.Tui_page.key_binding_desc

    type pstate = state Miaou_core.Navigation.t

    type msg = unit

    include Test_helpers.Stub_page_defaults (struct
      type nonrec state = state

      type nonrec pstate = pstate
    end)

    let init () = Miaou_core.Navigation.make ()

    let update ps _ = ps

    let view _ps ~focus:_ ~size:_ = ""

    let handle_modal_key ps key ~size:_ =
      (match key with
      | "Enter" ->
          Miaou_core.Modal_manager.set_consume_next_key () ;
          Miaou_core.Modal_manager.close_top `Commit
      | "Esc" ->
          Miaou_core.Modal_manager.set_consume_next_key () ;
          Miaou_core.Modal_manager.close_top `Cancel
      | _ -> ()) ;
      ps

    let handle_key = handle_modal_key

    let keymap _ = []

    let handled_keys () = []

    let on_key ps key ~size =
      let key_str = Miaou_core.Keys.to_string key in
      let ps' = handle_key ps key_str ~size in
      (ps', Miaou_interfaces.Key_event.Bubble)

    let on_modal_key ps key ~size =
      let key_str = Miaou_core.Keys.to_string key in
      let ps' = handle_modal_key ps key_str ~size in
      (ps', Miaou_interfaces.Key_event.Bubble)
  end

  let push_modal () =
    Miaou_core.Modal_manager.push
      (module Consuming_modal)
      ~init:(Consuming_modal.init ())
      ~ui:
        {title = "test"; left = None; max_width = None; dim_background = false}
      ~commit_on:[]
      ~cancel_on:[]
      ~on_close:(fun _ outcome ->
        match outcome with
        | `Commit ->
            Miaou_core.Modal_manager.set_pending_navigation
              (Miaou_core.Navigation.Goto "NEXT")
        | `Cancel -> ())

  include Test_helpers.Stub_page_defaults (struct
    type nonrec state = state

    type nonrec pstate = pstate
  end)

  let init () =
    Miaou_core.Modal_manager.clear () ;
    push_modal () ;
    Miaou_core.Navigation.make ()

  let update ps _ = ps

  let view _ps ~focus:_ ~size:_ = ""

  let keymap _ = []

  let handled_keys () = []

  (* Keys that reach the page directly (no modal active) are inert: this
     fixture's only observable behavior is the modal's commit/cancel path. *)
  let handle_key ps _ ~size:_ = ps

  let has_modal _ = Miaou_core.Modal_manager.has_active ()

  let on_key ps key ~size =
    let key_str = Miaou_core.Keys.to_string key in
    let ps' = handle_key ps key_str ~size in
    (ps', Miaou_interfaces.Key_event.Bubble)
end
