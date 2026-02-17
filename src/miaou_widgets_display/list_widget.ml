(* ***************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(* *************************************************************************** *)

module W = Widgets

type item = {
  id : string option;
  label : string;
  children : item list;
  selectable : bool;
}

module String_set = Set.Make (String)

type t = {
  items : item list;
  cursor : int list;
  expanded : String_set.t;
  indent : int;
}

let item ?id ?(selectable = true) ?(children = []) label =
  {id; label; children; selectable}

let group ?id ?(selectable = false) label children =
  {id; label; children; selectable}

let path_key path = String.concat "." (List.map string_of_int path)

let rec collect_expand_all path acc items =
  List.fold_left
    (fun acc (idx, it) ->
      let p = path @ [idx] in
      let acc =
        if it.children = [] then acc else String_set.add (path_key p) acc
      in
      if it.children = [] then acc else collect_expand_all p acc it.children)
    acc
    (List.mapi (fun i it -> (i, it)) items)

let create ?(indent = 2) ?(expand_all = true) items =
  let expanded =
    if expand_all then collect_expand_all [] String_set.empty items
    else String_set.empty
  in
  {items; cursor = [0]; expanded; indent}

let set_items t items =
  let valid = collect_expand_all [] String_set.empty items in
  let expanded = String_set.inter t.expanded valid in
  {t with items; expanded}

type flat_item = {
  path : int list;
  depth : int;
  item : item;
  has_children : bool;
  is_expanded : bool;
}

let rec flatten_items ?(depth = 0) path expanded items =
  let rec loop acc = function
    | [] -> List.rev acc
    | (idx, it) :: rest ->
        let p = path @ [idx] in
        let has_children = it.children <> [] in
        let is_expanded =
          has_children && String_set.mem (path_key p) expanded
        in
        let acc =
          {path = p; depth; item = it; has_children; is_expanded} :: acc
        in
        let acc =
          if is_expanded then
            let children =
              flatten_items ~depth:(depth + 1) p expanded it.children
            in
            List.rev_append children acc
          else acc
        in
        loop acc rest
  in
  loop [] (List.mapi (fun i it -> (i, it)) items)

let current_flat t = flatten_items [] t.expanded t.items

let current_index t =
  let flat = current_flat t in
  let rec find idx = function
    | [] -> 0
    | x :: xs -> if x.path = t.cursor then idx else find (idx + 1) xs
  in
  find 0 flat

let visible_count t = List.length (current_flat t)

let cursor_index t = current_index t

let set_cursor_by_index t idx =
  let flat = current_flat t in
  match List.nth_opt flat idx with
  | Some f -> {t with cursor = f.path}
  | None -> t

let set_cursor_index t idx = set_cursor_by_index t idx

let selected t =
  let flat = current_flat t in
  List.find_opt (fun f -> f.path = t.cursor) flat
  |> Option.map (fun f -> f.item)

let selected_path t =
  let flat = current_flat t in
  if List.exists (fun f -> f.path = t.cursor) flat then Some t.cursor else None

let toggle t =
  let flat = current_flat t in
  match List.find_opt (fun f -> f.path = t.cursor) flat with
  | None -> t
  | Some f ->
      if not f.has_children then t
      else
        let key = path_key f.path in
        let expanded =
          if String_set.mem key t.expanded then String_set.remove key t.expanded
          else String_set.add key t.expanded
        in
        {t with expanded}

let expand_all t =
  let expanded = collect_expand_all [] String_set.empty t.items in
  {t with expanded}

let collapse_all t = {t with expanded = String_set.empty}

let render_line ~focus current f indent =
  let marker =
    if f.has_children then if f.is_expanded then "▾" else "▸" else " "
  in
  let marker =
    if Lazy.force W.use_ascii_borders then
      if f.has_children then if f.is_expanded then "v" else ">" else " "
    else marker
  in
  let pad = String.make (f.depth * indent) ' ' in
  let line = pad ^ marker ^ " " ^ f.item.label in
  if focus && current then W.themed_selection line else line

let render t ~focus =
  let flat = current_flat t in
  let current = t.cursor in
  flat
  |> List.map (fun f -> render_line ~focus (f.path = current) f t.indent)
  |> Miaou_helpers.Helpers.concat_lines

let move_cursor t delta =
  let flat = current_flat t in
  let total = List.length flat in
  if total = 0 then t
  else
    let idx = current_index t in
    let idx = max 0 (min (total - 1) (idx + delta)) in
    set_cursor_by_index t idx

let handle_key t ~key =
  match key with
  | "Down" | "j" -> move_cursor t 1
  | "Up" | "k" -> move_cursor t (-1)
  | "Right" | "l" ->
      let flat = current_flat t in
      let is_collapsed =
        List.find_opt (fun f -> f.path = t.cursor) flat
        |> Option.map (fun f -> f.has_children && not f.is_expanded)
        |> Option.value ~default:false
      in
      if is_collapsed then toggle t else move_cursor t 1
  | "Left" | "h" -> (
      let flat = current_flat t in
      let is_expanded =
        List.find_opt (fun f -> f.path = t.cursor) flat
        |> Option.map (fun f -> f.has_children && f.is_expanded)
        |> Option.value ~default:false
      in
      if is_expanded then toggle t
      else
        (* Move to parent if any *)
        let parent_path =
          match List.rev t.cursor with
          | _ :: parent_rev -> Some (List.rev parent_rev)
          | [] -> None
        in
        match parent_path with Some p -> {t with cursor = p} | None -> t)
  | "Enter" | " " -> toggle t
  | _ -> t
