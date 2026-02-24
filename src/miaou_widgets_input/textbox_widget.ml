(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

open Miaou_widgets_display.Widgets

type t = {
  buf : string;
  cursor : int; (* index in characters *)
  title : string option;
  width : int;
  cancelled : bool;
  placeholder : string option;
  mask : bool;
}

let create ?title ?(width = 60) ?(initial = "") ?(placeholder = None)
    ?(mask = false) () =
  {
    buf = initial;
    cursor = String.length initial;
    title;
    width;
    cancelled = false;
    placeholder;
    mask;
  }

let open_centered ?title ?(width = 60) ?(initial = "") ?(placeholder = None)
    ?(mask = false) () =
  create ?title ~width ~initial ~placeholder ~mask ()

let render st ~focus:(_ : bool) =
  let content = st.buf in
  let show_placeholder = String.length content = 0 in
  let visible =
    if show_placeholder then
      match st.placeholder with Some p -> p | None -> ""
    else content
  in
  let _visible_len = String.length visible in
  (* Render with a simple visible cursor (underscore) at cursor_pos when focused. *)
  let with_cursor =
    if show_placeholder then (* dim placeholder *) themed_muted visible
    else
      let display =
        if st.mask then String.make (String.length content) '*' else content
      in
      let left = String.sub display 0 (min st.cursor (String.length display)) in
      let right =
        if st.cursor < String.length display then
          String.sub display st.cursor (String.length display - st.cursor)
        else ""
      in
      themed_text (left ^ "_" ^ right)
  in
  let padded =
    if String.length with_cursor >= st.width then
      String.sub with_cursor 0 (st.width - 1) ^ "…"
    else with_cursor ^ String.make (st.width - String.length with_cursor) ' '
  in
  let box = themed_border ("[" ^ padded ^ "]") in
  match st.title with Some t -> titleize t ^ "\n" ^ box | None -> box

(** New unified key handler returning Key_event.result *)
let on_key st ~key =
  let open Miaou_interfaces.Key_event in
  match key with
  | "Backspace" ->
      if st.cursor > 0 then
        let s = st.buf in
        let left = String.sub s 0 (st.cursor - 1) in
        let right = String.sub s st.cursor (String.length s - st.cursor) in
        ({st with buf = left ^ right; cursor = st.cursor - 1}, Handled)
      else (st, Handled) (* Consumed even if no-op *)
  | "Delete" ->
      let s = st.buf in
      if st.cursor < String.length s then
        let left = String.sub s 0 st.cursor in
        let right =
          String.sub s (st.cursor + 1) (String.length s - st.cursor - 1)
        in
        ({st with buf = left ^ right}, Handled)
      else (st, Handled)
      (* Consumed even if no-op *)
  | "Left" ->
      if st.cursor > 0 then ({st with cursor = st.cursor - 1}, Handled)
      else (st, Handled)
  | "Right" ->
      if st.cursor < String.length st.buf then
        ({st with cursor = st.cursor + 1}, Handled)
      else (st, Handled)
  | "Home" -> ({st with cursor = 0}, Handled)
  | "End" -> ({st with cursor = String.length st.buf}, Handled)
  | "Esc" | "Escape" -> ({st with cancelled = true}, Handled)
  | k when String.length k = 1 ->
      let s = st.buf in
      let left = String.sub s 0 st.cursor in
      let right = String.sub s st.cursor (String.length s - st.cursor) in
      ({st with buf = left ^ k ^ right; cursor = st.cursor + 1}, Handled)
  | key -> (
      (* Check for mouse click to position cursor *)
      match Miaou_helpers.Mouse.parse_click key with
      | Some {col; _} ->
          (* Account for "[" prefix (1 char) *)
          let text_col = col - 1 in
          let new_cursor = max 0 (min (String.length st.buf) text_col) in
          ({st with cursor = new_cursor}, Handled)
      | None -> (st, Bubble))

(** @deprecated Use [on_key] instead. Returns just state for backward compat. *)
let handle_key st ~key =
  let st', _ = on_key st ~key in
  st'

let is_cancelled t = t.cancelled

let reset_cancelled t = {t with cancelled = false}

let value t = t.buf

let get_text t = value t

(* Reference get_text to avoid unused-value warning when it's only used by modal on_close handlers *)
let () = ignore (get_text : t -> string)

let set_text t s = {t with buf = s; cursor = min (String.length s) t.cursor}

let set_text_with_cursor t ~text ~cursor =
  let c = max 0 (min (String.length text) cursor) in
  {t with buf = text; cursor = c}

let cursor t = t.cursor

let width t = t.width

let with_width t width =
  let width = max 4 width in
  if width = t.width then t else {t with width}
