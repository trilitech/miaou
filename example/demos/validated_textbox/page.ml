(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

module Inner = struct
  let tutorial_title = "Validated Textbox"
  let tutorial_markdown = [%blob "README.md"]

  module Vtextbox = Miaou_widgets_input.Validated_textbox_widget

  type state = {
    box_debounced : int Vtextbox.t;
    box_immediate : int Vtextbox.t;
    focus_debounced : bool;
    next_page : string option;
  }

  type msg = unit

  (* Simulate an expensive validator with a small delay *)
  let validate_int_slow s =
    (* In real usage, this might be a filesystem check, DB lookup, etc. *)
    Unix.sleepf 0.05;
    match int_of_string_opt s with
    | Some v when v >= 0 && v <= 100 -> Vtextbox.Valid v
    | Some _ -> Vtextbox.Invalid "Must be between 0 and 100"
    | None -> Vtextbox.Invalid "Enter a valid integer"

  let init () =
    let box_debounced =
      Vtextbox.create
        ~title:"With debounce (250ms)"
        ~placeholder:(Some "0-100")
        ~debounce_ms:250
        ~validator:validate_int_slow
        ()
    in
    let box_immediate =
      Vtextbox.create
        ~title:"Immediate (no debounce)"
        ~placeholder:(Some "0-100")
        ~debounce_ms:0
        ~validator:validate_int_slow
        ()
    in
    {box_debounced; box_immediate; focus_debounced = true; next_page = None}

  let update s (_ : msg) = s

  let render_box box ~focus =
    let module W = Miaou_widgets_display.Widgets in
    let rendered = Vtextbox.render box ~focus in
    let pending =
      if Vtextbox.has_pending_validation box then W.yellow " (validating...)"
      else ""
    in
    let status =
      match Vtextbox.validation_result box with
      | Vtextbox.Valid v -> W.green (Printf.sprintf "✓ Valid: %d" v)
      | Vtextbox.Invalid msg -> W.red ("✗ " ^ msg)
    in
    rendered ^ pending ^ "\n" ^ status

  let view s ~focus:_ ~size:_ =
    let module W = Miaou_widgets_display.Widgets in
    let header = W.titleize "Validated Textbox - Debounce Demo" in
    let desc =
      W.dim
        "Compare typing speed between debounced (top) and immediate (bottom) \
         validation.\n\
         The validator has a 50ms delay to simulate expensive I/O."
    in
    let box1 = render_box s.box_debounced ~focus:s.focus_debounced in
    let box2 = render_box s.box_immediate ~focus:(not s.focus_debounced) in
    let focus_indicator =
      if s.focus_debounced then "Focus: [Debounced] / Immediate"
      else "Focus: Debounced / [Immediate]"
    in
    let hint = W.dim "Tab: switch focus • Esc: back • t: tutorial" in
    String.concat "\n\n" [header; desc; box1; box2; focus_indicator; hint]

  let go_back s =
    {s with next_page = Some Demo_shared.Demo_config.launcher_page_name}

  let handle_key s key_str ~size:_ =
    match Miaou.Core.Keys.of_string key_str with
    | Some Miaou.Core.Keys.Escape -> go_back s
    | Some Miaou.Core.Keys.Tab ->
        {s with focus_debounced = not s.focus_debounced}
    | Some k ->
        let key = Miaou.Core.Keys.to_string k in
        if s.focus_debounced then
          {s with box_debounced = Vtextbox.handle_key s.box_debounced ~key}
        else {s with box_immediate = Vtextbox.handle_key s.box_immediate ~key}
    | None -> s

  let move s _ = s
  let refresh s = s
  let enter s = s
  let service_select s _ = s
  let service_cycle s _ = s
  let handle_modal_key s _ ~size:_ = s
  let next_page s = s.next_page
  let keymap (_ : state) = []
  let handled_keys () = []
  let back s = go_back s
  let has_modal _ = false
end

include Demo_shared.Demo_page.Make (Inner)
