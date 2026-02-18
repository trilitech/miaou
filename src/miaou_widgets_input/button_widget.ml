(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

type t = {label : string; on_click : unit -> unit; disabled : bool}

let create ?(disabled = false) ~label ~on_click () = {label; on_click; disabled}

let render t ~focus =
  let open Miaou_widgets_display.Widgets in
  let base = "[ " ^ t.label ^ " ]" in
  (* Use themed_selection for focus state instead of hardcoded colors *)
  let decorated = if focus then themed_selection (bold base) else base in
  if t.disabled then themed_muted decorated else decorated

(** New unified key handler returning Key_event.result *)
let on_key t ~key =
  if t.disabled then (t, Miaou_interfaces.Key_event.Bubble)
  else
    match key with
    | "Enter" | " " ->
        t.on_click () ;
        (t, Miaou_interfaces.Key_event.Handled)
    | key ->
        (* Mouse click triggers button - but we can't verify bounds without
           knowing our position, so we trust the dispatcher to only send
           clicks that are relevant to us. For standalone buttons, any click
           when focused should activate. *)
        if Miaou_helpers.Mouse.is_click key then (
          t.on_click () ;
          (t, Miaou_interfaces.Key_event.Handled))
        else (t, Miaou_interfaces.Key_event.Bubble)

(** @deprecated Use [on_key] instead. Kept for backward compatibility. *)
let handle_key t ~key =
  let t', result = on_key t ~key in
  (t', Miaou_interfaces.Key_event.to_bool result)
