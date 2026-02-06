(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

(* Interactive test to verify if multi-line modal titles get blue background *)

open Miaou.Core
module Select_widget = Miaou_widgets_input.Select_widget

type state = unit

type pstate = state Navigation.t

type key_binding = state Tui_page.key_binding_desc

type msg = unit

let init () = Navigation.make ()

let update ps _ = ps

let view _ps ~focus:_ ~size:_ =
  String.concat
    "\n"
    [
      "\027[1mMultiline Modal Title Test\027[0m";
      "";
      "Press 'm' to open modal with multi-line title";
      "";
      "Expected behavior:";
      "  • Title bar: 'Confirm Action' (with blue background)";
      "  • Message text: plain text (NO blue background)";
      "";
      "Press 'q' to quit";
    ]

let show_multiline_modal () =
  let multiline_text =
    "The following services depend on node-seoulnet and will also be updated:\n\
     baker-seoulnet, accuser-seoulnet\n\
     All services will be stopped, updated to v21.0, and restarted.\n\
     If any service fails to start, all will be rolled back."
  in
  let module Modal = struct
    type state = bool Select_widget.t

    type msg = unit

    type key_binding = state Tui_page.key_binding_desc

    type pstate = state Navigation.t

    let init () =
      Navigation.make
        (Select_widget.open_centered
           ~cursor:0
           ~title:""
           ~items:[true; false]
           ~to_string:(function true -> "Yes" | false -> "No")
           ())

    let update ps _ = ps

    let view ps ~focus ~size =
      Select_widget.render_with_size ps.Navigation.s ~focus ~size

    let move ps _ = ps

    let refresh ps = ps

    let service_select ps _ = ps

    let service_cycle ps _ = ps

    let back ps = ps

    let keymap _ = []

    let handled_keys () = []

    let handle_modal_key ps key ~size:_ =
      let s = ps.Navigation.s in
      let key =
        match Keys.of_string key with
        | Some Keys.Up -> "Up"
        | Some Keys.Down -> "Down"
        | Some Keys.Enter -> "Enter"
        | Some (Keys.Char "Esc")
        | Some (Keys.Char "Escape")
        | Some (Keys.Char "q") ->
            "Esc"
        | _ -> key
      in
      if key = "Enter" || key = "Esc" then ps
      else Navigation.update (fun _ -> Select_widget.handle_key s ~key) ps

    let handle_key = handle_modal_key

    let has_modal _ = true

    let on_key ps key ~size =
      let key_str = Keys.to_string key in
      let ps' = handle_key ps key_str ~size in
      (ps', Miaou_interfaces.Key_event.Bubble)

    let on_modal_key ps key ~size =
      let key_str = Keys.to_string key in
      let ps' = handle_modal_key ps key_str ~size in
      (ps', Miaou_interfaces.Key_event.Bubble)

    let key_hints _ = []
  end in
  (* This is the test: putting multiline message in the title *)
  let title_with_message = Printf.sprintf "Confirm Action\n%s" multiline_text in
  let ui : Modal_manager.ui =
    {
      title = title_with_message;
      left = None;
      max_width = Some (Fixed 80);
      dim_background = true;
    }
  in
  Modal_manager.push_default
    (module Modal)
    ~init:(Modal.init ())
    ~ui
    ~on_close:(fun _pstate reason ->
      match reason with
      | `Commit -> print_endline "User selected: Yes"
      | `Cancel -> print_endline "User selected: No")

let handle_key ps key_str ~size:_ =
  match key_str with
  | "m" ->
      show_multiline_modal () ;
      ps
  | "q" -> failwith "quit"
  | _ -> ps

let move ps _ = ps

let refresh ps = ps

let service_select ps _ = ps

let service_cycle ps _ = ps

let handle_modal_key ps _ ~size:_ = ps

let keymap (_ : pstate) =
  let open Tui_page in
  let noop ps = ps in
  [
    {key = "m"; action = noop; help = "Show modal"; display_only = true};
    {key = "q"; action = noop; help = "Quit"; display_only = true};
  ]

let handled_keys () = []

let back ps = ps

let has_modal _ = false

let on_key ps key ~size =
  let key_str = Keys.to_string key in
  let ps' = handle_key ps key_str ~size in
  (ps', Miaou_interfaces.Key_event.Bubble)

let on_modal_key ps key ~size =
  let key_str = Keys.to_string key in
  let ps' = handle_modal_key ps key_str ~size in
  (ps', Miaou_interfaces.Key_event.Bubble)

let key_hints _ = []

(* Main entry point *)
let () =
  let page : Registry.page =
    (module struct
      type nonrec state = state

      type nonrec pstate = pstate

      type nonrec key_binding = key_binding

      type nonrec msg = msg

      let init = init

      let update = update

      let view = view

      let handle_key = handle_key

      let move = move

      let refresh = refresh

      let service_select = service_select

      let service_cycle = service_cycle

      let handle_modal_key = handle_modal_key

      let keymap = keymap

      let handled_keys = handled_keys

      let back = back

      let has_modal = has_modal

      let on_key = on_key

      let on_modal_key = on_modal_key

      let key_hints = key_hints
    end)
  in
  Eio_main.run @@ fun env ->
  Eio.Switch.run @@ fun sw ->
  Miaou_helpers.Fiber_runtime.init ~env ~sw ;
  ignore (Miaou_runner_tui.Runner_tui.run page)
