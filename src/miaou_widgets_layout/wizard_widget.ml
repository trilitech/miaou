(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

module W = Miaou_widgets_display.Widgets

type 'state step = {
  title : string;
  render : 'state -> focus:bool -> size:LTerm_geom.size -> string;
  validate : 'state -> (unit, string) result;
  on_key : 'state -> key:string -> 'state;
}

type 'state t = {
  steps : 'state step array;
  current : int;
  state : 'state;
  error : string option;
  cancelled : bool;
  finished : bool;
}

let create ~steps ~initial =
  if Array.length steps = 0 then
    invalid_arg "Wizard_widget.create: steps must be non-empty" ;
  {
    steps;
    current = 0;
    state = initial;
    error = None;
    cancelled = false;
    finished = false;
  }

let current_step t = t.steps.(t.current)

let state t = t.state

let set_state t state = {t with state}

let current_index t = t.current

let step_count t = Array.length t.steps

let current_title t = (current_step t).title

let is_finished t = t.finished

let is_cancelled t = t.cancelled

let current_error t = t.error

let advance t =
  if t.finished || t.cancelled then t
  else
    let step = current_step t in
    match step.validate t.state with
    | Error msg -> {t with error = Some msg}
    | Ok () ->
        if t.current = Array.length t.steps - 1 then
          {t with finished = true; error = None}
        else {t with current = t.current + 1; error = None}

let back t =
  if t.current = 0 then t else {t with current = t.current - 1; error = None}

let cancel t = {t with cancelled = true}

let handle_key t ~key =
  if t.finished || t.cancelled then t
  else
    match key with
    | "Enter" -> advance t
    | "Escape" | "Esc" -> cancel t
    | "C-Left" | "Shift-Tab" | "S-Tab" -> back t
    | _ ->
        let step = current_step t in
        {t with state = step.on_key t.state ~key; error = None}

let breadcrumbs t =
  let n = Array.length t.steps in
  let buf = Buffer.create 64 in
  for i = 0 to n - 1 do
    let title = t.steps.(i).title in
    let dot =
      if i = t.current then "●" else if i < t.current then "●" else "○"
    in
    let label = Printf.sprintf "%s %d. %s" dot (i + 1) title in
    let styled =
      if i = t.current then W.themed_emphasis label
      else if i < t.current then W.themed_muted label
      else W.themed_text label
    in
    Buffer.add_string buf styled ;
    if i < n - 1 then Buffer.add_string buf (W.themed_muted "  →  ")
  done ;
  Buffer.contents buf

let render t ~focus ~size =
  let step = current_step t in
  let header = breadcrumbs t in
  let body = step.render t.state ~focus ~size in
  let error_line =
    match t.error with
    | Some msg -> "\n" ^ W.themed_error ("✗ " ^ msg)
    | None -> ""
  in
  let nav_hint =
    let n = Array.length t.steps in
    let next_or_finish = if t.current = n - 1 then "Finish" else "Next" in
    let parts =
      [
        Some (W.themed_muted (Printf.sprintf "[Enter: %s]" next_or_finish));
        (if t.current > 0 then Some (W.themed_muted "[Shift+Tab: Back]")
         else None);
        Some (W.themed_muted "[Esc: Cancel]");
      ]
    in
    let parts = List.filter_map (fun x -> x) parts in
    String.concat "  " parts
  in
  let status =
    if t.finished then W.themed_success "✓ Wizard complete."
    else if t.cancelled then W.themed_warning "⊘ Wizard cancelled."
    else nav_hint
  in
  String.concat "\n" [header; ""; body; error_line; ""; status]

let () =
  Miaou_registry.register ~name:"wizard" ~mli:[%blob "wizard_widget.mli"] ()
