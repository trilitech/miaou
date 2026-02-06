(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

open Miaou_widgets_display.Widgets

type t = {
  label : string option;
  checked_ : bool;
  cancelled : bool;
  disabled : bool;
}

let create ?label ?(checked_ = false) ?(disabled = false) () =
  {label; checked_; cancelled = false; disabled}

let open_centered ?label ?(checked_ = false) ?disabled () =
  create ?label ~checked_ ?disabled ()

let render (t : t) ~focus =
  let box = if t.checked_ then "[X]" else "[ ]" in
  match t.label with
  | None -> box
  | Some l ->
      let lbl = if focus then bold l else l in
      box ^ " " ^ lbl

(** New unified key handler returning Key_event.result *)
let on_key (t : t) ~key =
  if t.disabled then (t, Miaou_interfaces.Key_event.Bubble)
  else
    match key with
    | " " | "Space" | "Enter" ->
        ({t with checked_ = not t.checked_}, Miaou_interfaces.Key_event.Handled)
    | "Esc" | "Escape" ->
        ({t with cancelled = true}, Miaou_interfaces.Key_event.Handled)
    | _ -> (t, Miaou_interfaces.Key_event.Bubble)

(** @deprecated Use [on_key] instead. Returns just state for backward compat. *)
let handle_key (t : t) ~key =
  let t', _ = on_key t ~key in
  t'

let is_checked t = t.checked_

let set_checked t v = {t with checked_ = v}

let is_cancelled t = t.cancelled

let reset_cancelled t = {t with cancelled = false}
