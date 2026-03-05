(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(* Copyright (c) 2026 Mathias Bourgoin <mathias.bourgoin@atacama.tech>       *)
(*                                                                           *)
(*****************************************************************************)

module Helpers = Miaou_helpers.Helpers
module W = Widgets

type bar = string * float * string option

type threshold = {value : float; color : string}

type render_mode = ASCII | Braille | Octant

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

let render_octant t ~show_values ~thresholds =
  (* Octant bars: same 2×4 resolution as Braille but with per-bar fg color *)
  let min_val, max_val = calculate_bounds t in
  let range = max_val -. min_val in
  let inv_range = if range = 0. then 0. else 1. /. range in
  let num_bars = List.length t.data in
  let bar_width_cells = max 1 (t.width / num_bars) in
  let canvas = Octant_canvas.create ~width:t.width ~height:t.height in
  let dot_width, dot_height = Octant_canvas.get_dot_dimensions canvas in
  let bar_width_dots = max 1 (dot_width / num_bars) in

  List.iteri
    (fun idx (_label, value, bar_color) ->
      let color =
        get_color ~thresholds ~default_color:t.color (value, bar_color)
      in
      let bar_height_dots =
        if range = 0. then dot_height
        else
          int_of_float
            ((value -. min_val) *. inv_range *. float_of_int dot_height)
      in
      let x_start = idx * bar_width_dots in
      let x_end = min dot_width ((idx + 1) * bar_width_dots) in
      for x = x_start to x_end - 1 do
        for dot_from_top = 0 to bar_height_dots - 1 do
          let y = dot_height - 1 - dot_from_top in
          Octant_canvas.set_dot canvas ~x ~y ~color
        done
      done)
    t.data ;

  let lines = ref [] in
  (match t.title with
  | Some title -> lines := W.themed_emphasis title :: !lines
  | None -> ()) ;
  lines := Octant_canvas.render canvas :: !lines ;
  let labels_line = Buffer.create t.width in
  List.iter
    (fun (label, _, _) ->
      let truncated =
        if String.length label > bar_width_cells then
          String.sub label 0 bar_width_cells
        else label
      in
      let padding = max 0 (bar_width_cells - String.length truncated) / 2 in
      Buffer.add_string labels_line (String.make padding ' ') ;
      Buffer.add_string labels_line truncated ;
      Buffer.add_string
        labels_line
        (String.make (bar_width_cells - String.length truncated - padding) ' '))
    t.data ;
  lines := Buffer.contents labels_line :: !lines ;
  if show_values then (
    let values_line = Buffer.create t.width in
    List.iter
      (fun (_, value, _) ->
        let s = Printf.sprintf "%.1f" value in
        let s =
          if String.length s > bar_width_cells then
            String.sub s 0 bar_width_cells
          else s
        in
        let padding = max 0 (bar_width_cells - String.length s) / 2 in
        Buffer.add_string values_line (String.make padding ' ') ;
        Buffer.add_string values_line s ;
        Buffer.add_string
          values_line
          (String.make (bar_width_cells - String.length s - padding) ' '))
      t.data ;
    lines := Buffer.contents values_line :: !lines) ;
  Miaou_helpers.Helpers.concat_lines !lines

let render t ~show_values ?(thresholds = []) ?(mode = ASCII) () =
  if t.data = [] then ""
  else
    match mode with
    | Octant -> render_octant t ~show_values ~thresholds
    | ASCII ->
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
        | Some title -> lines := W.themed_emphasis title :: !lines
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
                  int_of_float
                    ((value -. min_val) /. range *. float_of_int t.height)
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
                  match color with
                  | Some c -> W.ansi c segment
                  | None -> segment
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
              if String.length label > bar_width then
                String.sub label 0 bar_width
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
                if String.length s > bar_width then String.sub s 0 bar_width
                else s
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
    | Braille ->
        (* Use braille canvas for higher resolution bars *)
        let min_val, max_val = calculate_bounds t in
        let range = max_val -. min_val in
        let inv_range = if range = 0. then 0. else 1. /. range in
        let num_bars = List.length t.data in
        let bar_width_cells = max 1 (t.width / num_bars) in

        let canvas = Braille_canvas.create ~width:t.width ~height:t.height in
        let width_cells, height_cells = Braille_canvas.get_dimensions canvas in
        let styles = Array.make_matrix height_cells width_cells None in
        let dot_width, dot_height = Braille_canvas.get_dot_dimensions canvas in
        let bar_width_dots = max 1 (dot_width / num_bars) in

        let mask_left = [|0; 0x40; 0x44; 0x46; 0x47|] in
        let mask_right = [|0; 0x80; 0xA0; 0xB0; 0xB8|] in

        (* Draw each bar *)
        List.iteri
          (fun idx (_label, value, bar_color) ->
            let color =
              get_color ~thresholds ~default_color:t.color (value, bar_color)
            in
            let bar_height_dots =
              if range = 0. then dot_height
              else
                int_of_float
                  ((value -. min_val) *. inv_range *. float_of_int dot_height)
            in
            let x_start = idx * bar_width_dots in
            let x_end = min dot_width ((idx + 1) * bar_width_dots) in
            let max_cell_y = height_cells - 1 in
            (* Fill bar column-by-column using precomputed masks *)
            for x = x_start to x_end - 1 do
              let col = x land 1 in
              let cell_x = x lsr 1 in
              let rec fill cell_y remaining =
                if remaining <= 0 || cell_y < 0 then ()
                else
                  let dots_in_cell = min 4 remaining in
                  let mask =
                    if col = 0 then mask_left.(dots_in_cell)
                    else mask_right.(dots_in_cell)
                  in
                  styles.(cell_y).(cell_x) <- color ;
                  Braille_canvas.add_cell_bits canvas ~cell_x ~cell_y mask ;
                  fill (cell_y - 1) (remaining - 4)
              in
              fill max_cell_y bar_height_dots
            done)
          t.data ;

        let lines = ref [] in

        (* Title *)
        (match t.title with
        | Some title -> lines := W.themed_emphasis title :: !lines
        | None -> ()) ;

        (* Chart *)
        lines := Chart_utils.render_braille_with_colors canvas styles :: !lines ;

        (* X-axis labels *)
        let labels_line = Buffer.create t.width in
        List.iter
          (fun (label, _, _) ->
            let truncated =
              if String.length label > bar_width_cells then
                String.sub label 0 bar_width_cells
              else label
            in
            let padding =
              max 0 (bar_width_cells - String.length truncated) / 2
            in
            Buffer.add_string labels_line (String.make padding ' ') ;
            Buffer.add_string labels_line truncated ;
            Buffer.add_string
              labels_line
              (String.make
                 (bar_width_cells - String.length truncated - padding)
                 ' '))
          t.data ;
        lines := Buffer.contents labels_line :: !lines ;

        (* Add values *)
        if show_values then (
          let values_line = Buffer.create t.width in
          List.iter
            (fun (_, value, _) ->
              let s = Printf.sprintf "%.1f" value in
              let s =
                if String.length s > bar_width_cells then
                  String.sub s 0 bar_width_cells
                else s
              in
              let padding = max 0 (bar_width_cells - String.length s) / 2 in
              Buffer.add_string values_line (String.make padding ' ') ;
              Buffer.add_string values_line s ;
              Buffer.add_string
                values_line
                (String.make (bar_width_cells - String.length s - padding) ' '))
            t.data ;
          lines := Buffer.contents values_line :: !lines) ;

        Helpers.concat_lines !lines

let () =
  Miaou_registry.register
    ~name:"bar_chart"
    ~mli:[%blob "bar_chart_widget.mli"]
    ()
