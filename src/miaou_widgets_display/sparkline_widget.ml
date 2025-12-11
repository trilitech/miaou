(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

module W = Widgets

(* Unicode block characters for sparkline rendering *)
let blocks = [|" "; " "; "▂"; "▃"; "▄"; "▅"; "▆"; "▇"; "█"|]

type threshold = {value : float; color : string}

type render_mode = ASCII | Braille

type t = {
  width : int;
  max_points : int;
  min_value : float option;
  max_value : float option;
  data : float Queue.t;
}

let create ~width ~max_points ?min_value ?max_value () =
  {width; max_points; min_value; max_value; data = Queue.create ()}

let push t value =
  Queue.push value t.data ;
  (* Maintain circular buffer: drop oldest if exceeds max_points *)
  while Queue.length t.data > t.max_points do
    ignore (Queue.pop t.data)
  done

let stats t =
  if Queue.is_empty t.data then (0., 0., 0.)
  else
    let values = Queue.to_seq t.data |> List.of_seq in
    let min_val =
      match t.min_value with
      | Some v -> v
      | None -> List.fold_left min Float.infinity values
    in
    let max_val =
      match t.max_value with
      | Some v -> v
      | None -> List.fold_left max Float.neg_infinity values
    in
    let current = List.hd (List.rev values) in
    (min_val, max_val, current)

let normalize value min_val max_val =
  let range = max_val -. min_val in
  if range = 0. then 4 (* Middle block for flat line *)
  else
    let ratio = (value -. min_val) /. range in
    (* Map to blocks[1..8], not blocks[0..8] since blocks[0] is space *)
    let block_idx = 1 + int_of_float (ratio *. 7.) in
    min 8 (max 1 block_idx)

let get_color ~thresholds ~(default_color : string option) value =
  let sorted_thresholds =
    List.sort (fun a b -> Float.compare b.value a.value) thresholds
  in
  match List.find_opt (fun t -> value > t.value) sorted_thresholds with
  | Some t -> Some t.color
  | None -> default_color

let render t ~focus ~show_value ?color ?(thresholds = []) ?(mode = ASCII) () =
  if Queue.is_empty t.data then
    let empty = String.make t.width ' ' in
    if show_value then empty ^ " 0.0" else empty
  else
    match mode with
    | ASCII ->
        let values = Queue.to_seq t.data |> List.of_seq in
        let min_val, max_val, current = stats t in
        let buf = Buffer.create (t.width * 10) in
        (* Each Unicode char can be multiple bytes, plus ANSI codes *)

        let render_value value =
          let block_idx = normalize value min_val max_val in
          let block = blocks.(block_idx) in
          let c = get_color ~thresholds ~default_color:color value in
          match c with Some color -> W.ansi color block | None -> block
        in

        (* Render sparkline blocks *)
        let point_count = List.length values in
        (if point_count > t.width then
           (* Sample data to fit width *)
           let step = float_of_int point_count /. float_of_int t.width in
           for i = 0 to t.width - 1 do
             let idx = int_of_float (float_of_int i *. step) in
             let value = List.nth values idx in
             Buffer.add_string buf (render_value value)
           done
         else if point_count = t.width then
           (* Perfect fit: render all points *)
           List.iter
             (fun value -> Buffer.add_string buf (render_value value))
             values
         else
           (* Pad with spaces if fewer points than width *)
           let pad_left = (t.width - point_count) / 2 in
           Buffer.add_string buf (String.make pad_left ' ') ;
           List.iter
             (fun value -> Buffer.add_string buf (render_value value))
             values ;
           let pad_right = t.width - point_count - pad_left in
           Buffer.add_string buf (String.make pad_right ' ')) ;

        let sparkline = Buffer.contents buf in
        let sparkline = if focus then W.bold sparkline else sparkline in

        if show_value then Printf.sprintf "%s %.1f" sparkline current
        else sparkline
    | Braille ->
        let values = Queue.to_seq t.data |> List.of_seq in
        let min_val, max_val, current = stats t in
        (* Create braille canvas: 1 cell height (4 dots), t.width cells wide *)
        let canvas = Braille_canvas.create ~width:t.width ~height:1 in
        let width_cells, height_cells = Braille_canvas.get_dimensions canvas in
        let styles = Array.make_matrix height_cells width_cells None in
        let dot_width, dot_height = Braille_canvas.get_dot_dimensions canvas in

        (* Sample or interpolate points to match dot_width *)
        let point_count = List.length values in
        let samples =
          if point_count > dot_width then
            (* Sample data to fit width *)
            let step = float_of_int point_count /. float_of_int dot_width in
            List.init dot_width (fun i ->
                let idx = int_of_float (float_of_int i *. step) in
                List.nth values idx)
          else if point_count = dot_width then values
          else
            (* Interpolate/pad to fill width *)
            let pad_left = (dot_width - point_count) / 2 in
            let pad_right = dot_width - point_count - pad_left in
            List.init pad_left (fun _ -> min_val)
            @ values
            @ List.init pad_right (fun _ -> min_val)
        in

        (* Plot each value as a vertical line at its height *)
        List.iteri
          (fun x value ->
            let range = max_val -. min_val in
            let y =
              if range = 0. then dot_height / 2
              else
                let ratio = (value -. min_val) /. range in
                (* Invert Y because we want higher values at the top *)
                int_of_float (ratio *. float_of_int (dot_height - 1))
            in
            let y = dot_height - 1 - y in
            (* Set dot at position *)
            let color =
              get_color ~thresholds ~default_color:color value
            in
            let cell_x = x / 2 in
            let cell_y = y / 4 in
            if cell_y < height_cells && cell_x < width_cells then
              styles.(cell_y).(cell_x) <- color ;
            Braille_canvas.set_dot canvas ~x ~y)
          samples ;

        let sparkline =
          Braille_canvas.render_with canvas ~f:(fun ~x ~y ch ->
              match styles.(y).(x) with Some c -> W.ansi c ch | None -> ch)
        in
        let sparkline = if focus then W.bold sparkline else sparkline in

        if show_value then Printf.sprintf "%s %.1f" sparkline current
        else sparkline

let render_with_label t ~label ~focus ?color ?(thresholds = []) ?(mode = ASCII)
    () =
  let spark = render t ~focus ~show_value:false ?color ~thresholds ~mode () in
  let _, _, current = stats t in
  Printf.sprintf "%s: [%s] %.1f" label spark current

let clear t = Queue.clear t.data

(* Accessor functions for SDL rendering *)
let get_data t = Queue.to_seq t.data |> List.of_seq

let get_bounds t =
  if Queue.is_empty t.data then (0., 1., 0.)
  else
    let values = get_data t in
    let min_val =
      match t.min_value with
      | Some v -> v
      | None -> List.fold_left min Float.infinity values
    in
    let max_val =
      match t.max_value with
      | Some v -> v
      | None -> List.fold_left max Float.neg_infinity values
    in
    let current = List.hd (List.rev values) in
    (min_val, max_val, current)

let is_empty t = Queue.is_empty t.data
