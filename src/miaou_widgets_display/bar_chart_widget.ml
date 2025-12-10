(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

module Helpers = Miaou_helpers.Helpers

module W = Widgets

type bar = string * float * string option

type threshold = {value : float; color : string}

type t = {
  width : int;
  height : int;
  data : bar list;
  title : string option;
  color : string option;
  min_value : float option;
  max_value : float option;
}

let create ~width ~height ~data ?title ?color ?min_value ?max_value () =
  {
    width;
    height;
    data;
    title;
    color = (match color with Some c -> Some c | None -> None);
    min_value;
    max_value;
  }

let update_data t ~data = {t with data}

let set_default_color t ~color = {t with color = Some color}

(* Calculate value bounds *)
let calculate_bounds t =
  let values = List.map (fun (_, v, _) -> v) t.data in
  let data_min, data_max = Chart_utils.bounds values in
  let min_val =
    match t.min_value with Some v -> v | None -> min 0.0 data_min
  in
  let max_val =
    match t.max_value with Some v -> v | None -> max 1.0 data_max
  in
  (min_val, max_val)

let get_color ~thresholds ~default_color (value, bar_color) =
  let sorted_thresholds =
    List.sort (fun a b -> Float.compare b.value a.value) thresholds
  in
  match bar_color with
  | Some c -> Some c
  | None -> (
      match List.find_opt (fun t -> value > t.value) sorted_thresholds with
      | Some t -> Some t.color
      | None -> default_color)

let render t ~show_values ?(thresholds = []) () =
  if t.data = [] then ""
  else
    let min_val, max_val = calculate_bounds t in
    let range = max_val -. min_val in
    let num_bars = List.length t.data in
    let bar_width = max 1 (t.width / num_bars) in

    let lines = ref [] in

    let repeat ch count =
      let buf = Buffer.create count in
      for _ = 1 to count do
        Buffer.add_string buf ch
      done ;
      Buffer.contents buf
    in

    (* Title *)
    (match t.title with
    | Some title -> lines := W.bold title :: !lines
    | None -> ()) ;

    (* Chart area *)
    for row = t.height - 1 downto 0 do
      let line_buf = Buffer.create t.width in
      let y_val_at_row =
        min_val +. (range *. (float_of_int row /. float_of_int t.height))
      in
      List.iter
        (fun (_label, value, bar_color) ->
          let bar_height =
            if range = 0. then t.height
            else
              int_of_float ((value -. min_val) /. range *. float_of_int t.height)
          in
          let color =
            get_color ~thresholds ~default_color:t.color (value, bar_color)
          in
          let bar_char = if W.prefer_ascii () then "#" else "█" in
          let top_char = if W.prefer_ascii () then "-" else "▀" in

          let segment =
            if row < bar_height then repeat bar_char bar_width
            else if row = bar_height && value > y_val_at_row then
              repeat top_char bar_width
            else String.make bar_width ' '
          in
          let styled_segment =
            if row <= bar_height && value > y_val_at_row then
              match color with Some c -> W.ansi c segment | None -> segment
            else segment
          in
          Buffer.add_string line_buf styled_segment)
        t.data ;
      lines := Buffer.contents line_buf :: !lines
    done ;

    (* X-axis labels *)
    let labels_line = Buffer.create t.width in
    List.iter
      (fun (label, _, _) ->
        let truncated =
          if String.length label > bar_width then String.sub label 0 bar_width
          else label
        in
        let padding = max 0 (bar_width - String.length truncated) / 2 in
        Buffer.add_string labels_line (String.make padding ' ') ;
        Buffer.add_string labels_line truncated ;
        Buffer.add_string
          labels_line
          (String.make (bar_width - String.length truncated - padding) ' '))
      t.data ;
    lines := Buffer.contents labels_line :: !lines ;

    (* Add values on top of bars *)
    if show_values then (
      let values_line = Buffer.create t.width in
      List.iter
        (fun (_, value, _) ->
          let s = Printf.sprintf "%.1f" value in
          let s =
            if String.length s > bar_width then String.sub s 0 bar_width else s
          in
          let padding = max 0 (bar_width - String.length s) / 2 in
          Buffer.add_string values_line (String.make padding ' ') ;
          Buffer.add_string values_line s ;
          Buffer.add_string
            values_line
            (String.make (bar_width - String.length s - padding) ' '))
        t.data ;
      lines := Buffer.contents values_line :: !lines) ;

    Helpers.concat_lines !lines
