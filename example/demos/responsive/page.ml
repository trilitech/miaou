(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

module Inner = struct
  let tutorial_title = "Responsive Layout"

  let tutorial_markdown = [%blob "README.md"]

  module Responsive = Miaou_widgets_layout.Responsive
  module W = Miaou_widgets_display.Widgets

  type state = {next_page : string option}

  type msg = unit

  let init () = {next_page = None}

  let update s _ = s

  (* A tile is rendered as a labelled coloured box of [w] x [h] cells. *)
  type tile = {label : string; bg_color : int; fg_color : int}

  let tiles =
    [
      {label = "Users"; bg_color = 24; fg_color = 231};
      {label = "Orders"; bg_color = 28; fg_color = 231};
      {label = "Revenue"; bg_color = 94; fg_color = 231};
      {label = "Errors"; bg_color = 88; fg_color = 231};
    ]

  let pad_to w s =
    let len = String.length s in
    if len >= w then String.sub s 0 w else s ^ String.make (w - len) ' '

  let render_tile tile ~w ~h =
    (* Centre the label vertically in [h] rows, each [w] wide, all bg-filled. *)
    let h = max 3 h in
    let w = max 8 w in
    let blank = pad_to w "" in
    let label_line =
      let inner = " " ^ tile.label ^ " " in
      let inner =
        if String.length inner > w then String.sub inner 0 w else inner
      in
      let pad_total = w - String.length inner in
      let left = pad_total / 2 in
      let right = pad_total - left in
      String.make left ' ' ^ inner ^ String.make right ' '
    in
    let mid = h / 2 in
    let lines =
      List.init h (fun i ->
          let s = if i = mid then label_line else blank in
          W.fg tile.fg_color (W.bg tile.bg_color s))
    in
    String.concat "\n" lines

  (* Concatenate two multi-line blocks side by side with a single-cell gap. *)
  let hcat ~gap a b =
    let split = String.split_on_char '\n' in
    let la = split a in
    let lb = split b in
    let n = max (List.length la) (List.length lb) in
    let pad lst =
      let len = List.length lst in
      if len >= n then lst else lst @ List.init (n - len) (fun _ -> "")
    in
    let la = pad la and lb = pad lb in
    let sep = String.make gap ' ' in
    List.map2 (fun x y -> x ^ sep ^ y) la lb |> String.concat "\n"

  let vcat ~gap a b =
    let g =
      if gap <= 0 then "\n" else "\n" ^ String.make (gap - 1) '\n' ^ "\n"
    in
    a ^ g ^ b

  (* Build the three layouts as functions that render to a string given the
     terminal size. *)
  type layout = size:LTerm_geom.size -> string

  let wide_layout : layout =
   fun ~size ->
    let cols = size.LTerm_geom.cols in
    let n = List.length tiles in
    let gaps = (n - 1) * 2 in
    let w = max 10 ((cols - gaps - 4) / n) in
    let h = max 5 (min 9 (size.LTerm_geom.rows / 3)) in
    let blocks = List.map (fun t -> render_tile t ~w ~h) tiles in
    match blocks with
    | [] -> ""
    | first :: rest -> List.fold_left (hcat ~gap:2) first rest

  let medium_layout : layout =
   fun ~size ->
    let cols = size.LTerm_geom.cols in
    let w = max 14 ((cols - 4 - 2) / 2) in
    let h = max 4 (min 7 (size.LTerm_geom.rows / 4)) in
    match tiles with
    | [a; b; c; d] ->
        let row1 = hcat ~gap:2 (render_tile a ~w ~h) (render_tile b ~w ~h) in
        let row2 = hcat ~gap:2 (render_tile c ~w ~h) (render_tile d ~w ~h) in
        vcat ~gap:1 row1 row2
    | _ -> ""

  let narrow_layout : layout =
   fun ~size ->
    let w = max 10 (size.LTerm_geom.cols - 2) in
    let h = 3 in
    let blocks = List.map (fun t -> render_tile t ~w ~h) tiles in
    String.concat "\n" blocks

  let view _ ~focus:_ ~size =
    let cols = size.LTerm_geom.cols in
    let label, layout =
      Responsive.pick
        ~width:cols
        ~default:("WIDE (>= 120 cols)", wide_layout)
        [
          {
            Responsive.max_width = 59;
            layout = ("NARROW (< 60 cols)", narrow_layout);
          };
          {
            Responsive.max_width = 119;
            layout = ("MEDIUM (60-119 cols)", medium_layout);
          };
        ]
    in
    let header = W.titleize "Responsive Dashboard" in
    let bp =
      W.themed_emphasis (Printf.sprintf "Breakpoint: %s [%d cols]" label cols)
    in
    let hint =
      W.themed_muted
        "Resize the terminal to switch layouts. Esc returns, t opens tutorial."
    in
    let body = layout ~size in
    String.concat "\n" [header; bp; hint; ""; body]

  let go_back = {next_page = Some Demo_shared.Demo_config.launcher_page_name}

  let handle_key s key_str ~size:_ =
    match Miaou.Core.Keys.of_string key_str with
    | Some Miaou.Core.Keys.Escape -> go_back
    | _ -> s

  let move s _ = s

  let refresh s = s

  let enter s = s

  let service_select s _ = s

  let service_cycle s _ = s

  let handle_modal_key s _ ~size:_ = s

  let next_page s = s.next_page

  let keymap (_ : state) = []

  let handled_keys () = []

  let back _ = go_back

  let has_modal _ = false
end

include Demo_shared.Demo_page.MakeSimple (Inner)
