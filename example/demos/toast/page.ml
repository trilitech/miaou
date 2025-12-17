(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

let _tutorial_markdown = [%blob "README.md"]

module Toast = Miaou_widgets_layout.Toast_widget
module Flash_bus = Lib_miaou_internal.Flash_bus
module Flash_toast = Lib_miaou_internal.Flash_toast_renderer

type state = {toasts : Toast.t; next_page : string option}

type msg = unit

let init () = {toasts = Toast.empty (); next_page = None}

let update s (_ : msg) = s

let positions = [|`Top_left; `Top_right; `Bottom_right; `Bottom_left|]

let cycle_position p =
  let rec loop i =
    if i >= Array.length positions then 0
    else if positions.(i) = p then i
    else loop (i + 1)
  in
  positions.((loop 0 + 1) mod Array.length positions)

let go_back s = {s with next_page = Some Demo_shared.Demo_config.launcher_page_name}

let add severity label s =
  let idx = List.length (Toast.to_list s.toasts) + 1 in
  let message = Printf.sprintf "%s #%d" label idx in
  {s with toasts = Toast.enqueue s.toasts severity message}

let dismiss_oldest s =
  match Toast.to_list s.toasts with
  | [] -> s
  | t :: _ -> {s with toasts = Toast.dismiss s.toasts ~id:t.id}

let set_position s =
  let next = cycle_position s.toasts.position in
  {s with toasts = Toast.with_position s.toasts next}

let view s ~focus:_ ~size =
  let module W = Miaou_widgets_display.Widgets in
  let header = W.titleize "Toast notifications" in
  let tips =
    W.dim
      "1: info • 2: ok • 3: warn • 4: error • b: flash bus • d: dismiss • p: \n\
      \         position • Esc: back"
  in
  let rendered = Toast.render s.toasts ~cols:size.LTerm_geom.cols in
  let bus_block =
    let snapshot = Flash_bus.snapshot () in
    if snapshot = [] then W.dim "(flash bus empty)"
    else
      Flash_toast.render_snapshot
        ~position:`Bottom_right
        ~cols:size.LTerm_geom.cols
        snapshot
  in
  String.concat "\n" [header; tips; ""; rendered; ""; bus_block]

let handle_key s key_str ~size:_ =
  match Miaou.Core.Keys.of_string key_str with
  | Some (Miaou.Core.Keys.Char "Esc") | Some (Miaou.Core.Keys.Char "Escape") ->
      go_back s
  | Some (Miaou.Core.Keys.Char "1") -> add Toast.Info "Info" s
  | Some (Miaou.Core.Keys.Char "2") -> add Toast.Success "Success" s
  | Some (Miaou.Core.Keys.Char "3") -> add Toast.Warn "Warning" s
  | Some (Miaou.Core.Keys.Char "4") -> add Toast.Error "Error" s
  | Some (Miaou.Core.Keys.Char "b") ->
      Flash_bus.push ~level:Flash_bus.Warn "Bus warning" ;
      s
  | Some (Miaou.Core.Keys.Char "d") -> dismiss_oldest s
  | Some (Miaou.Core.Keys.Char "p") -> set_position s
  | _ -> s

let move s _ = s
let refresh s = {s with toasts = Toast.tick s.toasts}
let enter s = s
let service_select s _ = s
let service_cycle s _ = refresh s
let handle_modal_key s _ ~size:_ = s
let next_page s = s.next_page
let keymap (_ : state) = []
let handled_keys () = []
let back s = go_back s
let has_modal _ = false
