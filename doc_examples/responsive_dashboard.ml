(******************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(******************************************************************************)

module Responsive = Miaou_widgets_layout.Responsive

(* docs:start:responsive-pick *)
type layout = Wide | Medium | Narrow

let layout_for_width width =
  Responsive.pick
    ~width
    ~default:Wide
    [{max_width = 59; layout = Narrow}; {max_width = 119; layout = Medium}]

let cell name value = Printf.sprintf "| %-9s %6s " name value

let render_dashboard ~width =
  match layout_for_width width with
  | Wide ->
      String.concat
        "\n"
        [
          "+----------------+----------------+----------------+----------------+";
          cell "Users" "1.2k" ^ cell "Orders" "342" ^ cell "Revenue" "$9k"
          ^ cell "Errors" "4" ^ "|";
          "+----------------+----------------+----------------+----------------+";
        ]
  | Medium ->
      String.concat
        "\n"
        [
          "+----------------+----------------+";
          cell "Users" "1.2k" ^ cell "Orders" "342" ^ "|";
          "+----------------+----------------+";
          cell "Revenue" "$9k" ^ cell "Errors" "4" ^ "|";
          "+----------------+----------------+";
        ]
  | Narrow ->
      String.concat
        "\n"
        [
          "+----------------+";
          cell "Users" "1.2k" ^ "|";
          cell "Orders" "342" ^ "|";
          cell "Revenue" "$9k" ^ "|";
          cell "Errors" "4" ^ "|";
          "+----------------+";
        ]
(* docs:end:responsive-pick *)

let describe = function
  | Wide -> "four tiles in one row"
  | Medium -> "two by two grid"
  | Narrow -> "single stacked column"

let render ~width =
  let layout = layout_for_width width in
  Printf.sprintf "Dashboard layout: %s" (describe layout)
