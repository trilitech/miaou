(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(* Copyright (c) 2026 Mathias Bourgoin <mathias.bourgoin@atacama.tech>       *)
(*                                                                           *)
(*****************************************************************************)
[@@@warning "-32-34-37-69"]

module W = Widgets

type node = {label : string; children : node list}

type t = {root : node; cursor_path : int list; expanded : int list list}

let rec json_to_node j =
  match j with
  | `Assoc kvs ->
      let children =
        List.fold_left
          (fun acc (k, v) -> {label = k; children = [json_to_node v]} :: acc)
          []
          kvs
      in
      {label = "obj"; children = List.rev children}
  | `List lst -> {label = "list"; children = List.map json_to_node lst}
  | other -> {label = Yojson.Safe.to_string other; children = []}

let of_json j = json_to_node j

let path_compare = compare

let is_expanded path t = List.exists (fun p -> p = path) t.expanded

let add_expand path t =
  if is_expanded path t then t
  else {t with expanded = List.sort path_compare (path :: t.expanded)}

let remove_expand path t =
  {t with expanded = List.filter (fun p -> p <> path) t.expanded}

let open_root node = {root = node; cursor_path = [0]; expanded = []}

let rec node_at_offsets n offsets =
  match offsets with
  | [] -> Some n
  | i :: rest -> (
      match List.nth_opt n.children i with
      | None -> None
      | Some c -> node_at_offsets c rest)

let find_node t path =
  match path with 0 :: rest -> node_at_offsets t.root rest | _ -> None

let flatten_visible t =
  let rec walk node path depth acc =
    let acc = (node, path, depth) :: acc in
    if is_expanded path t then
      let _, acc =
        List.fold_left
          (fun (i, acc) child ->
            (i + 1, walk child (path @ [i]) (depth + 1) acc))
          (0, acc)
          node.children
      in
      acc
    else acc
  in
  List.rev (walk t.root [0] 0 [])

let cursor_index t =
  let visible = flatten_visible t in
  let rec idx i = function
    | [] -> 0
    | (_, p, _) :: rest -> if p = t.cursor_path then i else idx (i + 1) rest
  in
  idx 0 visible

let row_at_index visible i =
  let n = List.length visible in
  if n = 0 then None
  else
    let i = if i < 0 then 0 else if i >= n then n - 1 else i in
    List.nth_opt visible i

let parent_path = function
  | [] | [_] -> None
  | p ->
      let n = List.length p in
      Some (List.filteri (fun i _ -> i < n - 1) p)

let validate_cursor t =
  let visible = flatten_visible t in
  if List.exists (fun (_, p, _) -> p = t.cursor_path) visible then t
  else
    let rec walk_up p =
      match parent_path p with
      | None -> [0]
      | Some pp ->
          if List.exists (fun (_, p2, _) -> p2 = pp) visible then pp
          else walk_up pp
    in
    {t with cursor_path = walk_up t.cursor_path}

let move_cursor t delta =
  let visible = flatten_visible t in
  let i = cursor_index t in
  match row_at_index visible (i + delta) with
  | None -> t
  | Some (_, p, _) -> {t with cursor_path = p}

let go_first t =
  let visible = flatten_visible t in
  match visible with [] -> t | (_, p, _) :: _ -> {t with cursor_path = p}

let go_last t =
  let visible = flatten_visible t in
  match List.rev visible with
  | [] -> t
  | (_, p, _) :: _ -> {t with cursor_path = p}

let toggle_at t path =
  let t' =
    if is_expanded path t then remove_expand path t else add_expand path t
  in
  validate_cursor t'

let handle_right t =
  match find_node t t.cursor_path with
  | None -> t
  | Some n when n.children = [] -> t
  | Some _ ->
      if is_expanded t.cursor_path t then
        {t with cursor_path = t.cursor_path @ [0]}
      else add_expand t.cursor_path t

let handle_left t =
  if is_expanded t.cursor_path t then remove_expand t.cursor_path t
  else
    match parent_path t.cursor_path with
    | None -> t
    | Some pp -> {t with cursor_path = pp}

let handle_key t ~key =
  match key with
  | "Down" -> move_cursor t 1
  | "Up" -> move_cursor t (-1)
  | "Home" -> go_first t
  | "End" -> go_last t
  | "Right" -> handle_right t
  | "Left" -> handle_left t
  | "Enter" -> toggle_at t t.cursor_path
  | _ -> t

let all_internal_paths t =
  let rec walk n path acc =
    if n.children = [] then acc
    else
      let acc = path :: acc in
      let _, acc =
        List.fold_left
          (fun (i, acc) c -> (i + 1, walk c (path @ [i]) acc))
          (0, acc)
          n.children
      in
      acc
  in
  List.sort path_compare (walk t.root [0] [])

let expand_all t = {t with expanded = all_internal_paths t}

let collapse_all t = validate_cursor {t with expanded = []; cursor_path = [0]}

let render_node indent n =
  let buf = Buffer.create 64 in
  let rec render_into buf indent n =
    Buffer.add_string buf (String.make indent ' ') ;
    Buffer.add_string buf n.label ;
    match n.children with
    | [] -> ()
    | children ->
        Buffer.add_char buf '\n' ;
        List.iteri
          (fun idx child ->
            if idx > 0 then Buffer.add_char buf '\n' ;
            render_into buf (indent + 2) child)
          children
  in
  render_into buf indent n ;
  Buffer.contents buf

let marker_for ~ascii ~has_children ~expanded =
  if not has_children then "  "
  else if expanded then if ascii then "v " else "▾ "
  else if ascii then "> "
  else "▸ "

let render t ~focus:_ =
  let visible = flatten_visible t in
  let ascii = W.prefer_ascii () in
  let lines =
    List.map
      (fun (n, path, depth) ->
        let indent = String.make (depth * 2) ' ' in
        let mk =
          marker_for
            ~ascii
            ~has_children:(n.children <> [])
            ~expanded:(is_expanded path t)
        in
        let line = indent ^ mk ^ n.label in
        if path = t.cursor_path then W.themed_selection line else line)
      visible
  in
  String.concat "\n" lines

let () = Miaou_registry.register ~name:"tree" ~mli:[%blob "tree_widget.mli"] ()
