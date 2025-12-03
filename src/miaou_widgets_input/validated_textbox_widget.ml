(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)
open Miaou_widgets_display.Widgets

type 'a validation_result = Valid of 'a | Invalid of string

type 'a validator = string -> 'a validation_result

type 'a t = {
  textbox : Textbox_widget.t;
  validator : 'a validator;
  validation_state : 'a validation_result;
}

let create ?title ?(width = 60) ?(initial = "") ?(placeholder = None) ~validator
    () =
  let textbox = Textbox_widget.create ?title ~width ~initial ~placeholder () in
  let validation_state = validator initial in
  {textbox; validator; validation_state}

let open_centered ?title ?(width = 60) ?(initial = "") ?(placeholder = None)
    ~validator () =
  create ?title ~width ~initial ~placeholder ~validator ()

let update_validation t =
  let current_value = Textbox_widget.value t.textbox in
  let validation_state = t.validator current_value in
  {t with validation_state}

let render t ~focus =
  let base_render = Textbox_widget.render t.textbox ~focus in
  match t.validation_state with
  | Valid _ -> base_render
  | Invalid error_msg ->
      let error_display =
        if visible_chars_count error_msg > 60 then
          let idx = visible_byte_index_of_pos error_msg 57 in
          String.sub error_msg 0 idx ^ "..."
        else error_msg
      in
      (* Add red coloring to indicate error and show error message below *)
      let colored_base = red base_render in
      colored_base ^ "\n" ^ red ("⚠ " ^ error_display)

let handle_key t ~key =
  let updated_textbox = Textbox_widget.handle_key t.textbox ~key in
  let updated_t = {t with textbox = updated_textbox} in
  update_validation updated_t

let is_cancelled t = Textbox_widget.is_cancelled t.textbox

let reset_cancelled t =
  let reset_textbox = Textbox_widget.reset_cancelled t.textbox in
  {t with textbox = reset_textbox}

let value t = Textbox_widget.value t.textbox

let validation_result t = t.validation_state

let is_valid t =
  match t.validation_state with Valid _ -> true | Invalid _ -> false

let get_validated_value t =
  match t.validation_state with Valid v -> Some v | Invalid _ -> None

let get_error_message t =
  match t.validation_state with Valid _ -> None | Invalid msg -> Some msg

let width t = Textbox_widget.width t.textbox

let with_width t width =
  let textbox = Textbox_widget.with_width t.textbox width in
  {t with textbox}
