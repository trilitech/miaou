(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

open Miaou_widgets_display.Widgets

type t = {label : string option; on : bool; cancelled : bool; disabled : bool}

let create ?label ?(on = false) ?(disabled = false) () =
  {label; on; cancelled = false; disabled}

let open_centered ?label ?(on = false) ?disabled () =
  create ?label ~on ?disabled ()

let render (t : t) ~focus =
  let core = if t.on then "[ ON ]" else "[ OFF ]" in
  let sw = if t.on then green core else dim core in
  match t.label with
  | None -> sw
  | Some l ->
      let lbl = if focus then bold l else l in
      lbl ^ ": " ^ sw

(** New unified key handler returning Key_event.result *)
let on_key (t : t) ~key =
  if t.disabled then (t, Miaou_interfaces.Key_event.Bubble)
  else
    match key with
    | " " | "Space" | "Enter" ->
        ({t with on = not t.on}, Miaou_interfaces.Key_event.Handled)
    | "Esc" | "Escape" ->
        ({t with cancelled = true}, Miaou_interfaces.Key_event.Handled)
    | _ -> (t, Miaou_interfaces.Key_event.Bubble)

(** @deprecated Use [on_key] instead. Returns just state for backward compat. *)
let handle_key (t : t) ~key =
  let t', _ = on_key t ~key in
  t'

let is_on t = t.on

let set_on t v = {t with on = v}

let is_cancelled t = t.cancelled

let reset_cancelled t = {t with cancelled = false}
