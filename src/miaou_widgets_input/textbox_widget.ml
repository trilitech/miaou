(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                 *)
(* Copyright (c) 2026 Mathias Bourgoin <mathias.bourgoin@atacama.tech>        *)
(*                                                                            *)
(******************************************************************************)

open Miaou_widgets_display.Widgets

type t = {
  buf : string;
  cursor : int; (* UTF-8 boundary byte offset *)
  title : string option;
  width : int;
  cancelled : bool;
  placeholder : string option;
  mask : bool;
}

module H = Miaou_helpers.Helpers

let clamp_cursor s cursor = H.utf8_clamp_boundary s cursor

let utf8_char_count_until s cursor =
  let cursor = clamp_cursor s cursor in
  let rec loop i count =
    if i >= cursor then count
    else
      let next = H.utf8_next_boundary s i in
      if next <= i then count else loop next (count + 1)
  in
  loop 0 0

let masked_display_and_cursor s cursor =
  let char_count = utf8_char_count_until s (String.length s) in
  let cursor = utf8_char_count_until s cursor in
  (String.make char_count '*', cursor)

let is_named_non_text_key = function
  | "Tab" | "S-Tab" | "Shift-Tab" | "BackTab" | "Enter" | "A-Enter"
  | "Alt-Enter" | "Backspace" | "Delete" | "Left" | "Right" | "Up" | "Down"
  | "Home" | "End" | "Esc" | "Escape" | "PageUp" | "PageDown" | "WheelUp"
  | "WheelDown" ->
      true
  | key when String.length key >= 2 && String.sub key 0 2 = "C-" -> true
  | key when String.length key >= 2 && key.[0] = 'F' -> (
      match int_of_string_opt (String.sub key 1 (String.length key - 1)) with
      | Some _ -> true
      | None -> false)
  | key when Miaou_helpers.Mouse.is_click key || Miaou_helpers.Mouse.is_drag key
    ->
      true
  | _ -> false

let is_text_key key =
  key <> ""
  && (not (is_named_non_text_key key))
  && not
       (String.exists
          (fun c -> c = '\027' || c = '\000' || c = '\n' || c = '\r')
          key)

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
      let display, cursor =
        if st.mask then masked_display_and_cursor content st.cursor
        else (content, clamp_cursor content st.cursor)
      in
      let left = String.sub display 0 cursor in
      let right =
        if cursor < String.length display then
          String.sub display cursor (String.length display - cursor)
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
        let cursor = clamp_cursor s st.cursor in
        let prev = H.utf8_prev_boundary s cursor in
        let left = String.sub s 0 prev in
        let right = String.sub s cursor (String.length s - cursor) in
        ({st with buf = left ^ right; cursor = prev}, Handled)
      else (st, Handled) (* Consumed even if no-op *)
  | "Delete" ->
      let s = st.buf in
      let cursor = clamp_cursor s st.cursor in
      if cursor < String.length s then
        let next = H.utf8_next_boundary s cursor in
        let left = String.sub s 0 cursor in
        let right = String.sub s next (String.length s - next) in
        ({st with buf = left ^ right}, Handled)
      else (st, Handled)
      (* Consumed even if no-op *)
  | "Left" ->
      if st.cursor > 0 then
        ({st with cursor = H.utf8_prev_boundary st.buf st.cursor}, Handled)
      else (st, Handled)
  | "Right" ->
      if st.cursor < String.length st.buf then
        ({st with cursor = H.utf8_next_boundary st.buf st.cursor}, Handled)
      else (st, Handled)
  | "Home" -> ({st with cursor = 0}, Handled)
  | "End" -> ({st with cursor = String.length st.buf}, Handled)
  | "Esc" | "Escape" -> ({st with cancelled = true}, Handled)
  | k when is_text_key k ->
      let s = st.buf in
      let cursor = clamp_cursor s st.cursor in
      let left = String.sub s 0 cursor in
      let right = String.sub s cursor (String.length s - cursor) in
      ( {st with buf = left ^ k ^ right; cursor = cursor + String.length k},
        Handled )
  | key -> (
      (* Check for mouse click to position cursor *)
      match Miaou_helpers.Mouse.parse_click key with
      | Some {col; _} ->
          (* Account for "[" prefix (1 char) *)
          let text_col = col - 1 in
          let new_cursor =
            H.visible_byte_index_of_pos st.buf (max 0 text_col)
          in
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

let set_text t s = {t with buf = s; cursor = clamp_cursor s t.cursor}

let set_text_with_cursor t ~text ~cursor =
  let c = clamp_cursor text cursor in
  {t with buf = text; cursor = c}

let cursor t = t.cursor

let width t = t.width

let with_width t width =
  let width = max 4 width in
  if width = t.width then t else {t with width}

let () =
  Miaou_registry.register ~name:"textbox" ~mli:[%blob "textbox_widget.mli"] ()
