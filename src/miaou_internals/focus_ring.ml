(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

type slot = {id : string; focusable : bool}

type t = {slots : slot array; active : int}

let create ids =
  let slots = Array.of_list (List.map (fun id -> {id; focusable = true}) ids) in
  {slots; active = 0}

let create_slots sl = {slots = Array.of_list sl; active = 0}

let total t = Array.length t.slots

let focusable_count t =
  Array.fold_left (fun acc s -> if s.focusable then acc + 1 else acc) 0 t.slots

let current t =
  let n = Array.length t.slots in
  if n = 0 then None
  else
    let s = t.slots.(t.active) in
    if s.focusable then Some s.id else None

let current_index t =
  let n = Array.length t.slots in
  if n = 0 then None
  else
    let s = t.slots.(t.active) in
    if s.focusable then Some t.active else None

let is_focused t id =
  match current t with Some cid -> String.equal cid id | None -> false

let find_next_focusable slots start dir =
  let n = Array.length slots in
  if n = 0 then None
  else
    let step = match dir with `Next -> 1 | `Prev -> n - 1 in
    let rec loop i count =
      if count >= n then None
      else
        let idx = (start + (i * step)) mod n in
        if slots.(idx).focusable then Some idx else loop (i + 1) (count + 1)
    in
    loop 1 0

let move t dir =
  match find_next_focusable t.slots t.active dir with
  | Some idx -> {t with active = idx}
  | None -> t

(** New unified key handler returning Key_event.result *)
let on_key t ~key =
  let open Miaou_interfaces.Key_event in
  match key with
  | "Tab" ->
      let t' = move t `Next in
      (t', Handled)
  | "S-Tab" | "Shift-Tab" | "BackTab" ->
      let t' = move t `Prev in
      (t', Handled)
  | _ -> (t, Bubble)

(** @deprecated Use [on_key] instead. Returns polymorphic variant for compat. *)
let handle_key t ~key =
  let t', result = on_key t ~key in
  let status =
    match result with
    | Miaou_interfaces.Key_event.Handled -> `Handled
    | Miaou_interfaces.Key_event.Bubble -> `Bubble
  in
  (t', status)

let focus t id =
  let n = Array.length t.slots in
  let rec find i =
    if i >= n then t
    else if String.equal t.slots.(i).id id then {t with active = i}
    else find (i + 1)
  in
  find 0

let set_focusable t id enabled =
  let slots = Array.copy t.slots in
  let n = Array.length slots in
  let changed = ref false in
  for i = 0 to n - 1 do
    if String.equal slots.(i).id id then begin
      slots.(i) <- {(slots.(i)) with focusable = enabled} ;
      changed := true
    end
  done ;
  if not !changed then t
  else
    let t' = {slots; active = t.active} in
    (* If we disabled the currently focused slot, move to next available *)
    if (not enabled) && t.active < n && String.equal t.slots.(t.active).id id
    then
      match find_next_focusable slots t.active `Next with
      | Some idx -> {t' with active = idx}
      | None -> t'
    else t'

type scope = {
  parent : t;
  children : (string * t) list;
  active_child : string option;
}

let scope ~parent ~children = {parent; children; active_child = None}

let active sc =
  match sc.active_child with
  | None -> sc.parent
  | Some id -> (
      match List.assoc_opt id sc.children with
      | Some ring -> ring
      | None -> sc.parent)

let in_child sc = Option.is_some sc.active_child

let active_child_id sc = sc.active_child

let enter sc =
  match sc.active_child with
  | Some _ -> sc (* already in a child *)
  | None -> (
      match current sc.parent with
      | None -> sc
      | Some id -> (
          match List.assoc_opt id sc.children with
          | Some _ -> {sc with active_child = Some id}
          | None -> sc))

let exit sc = {sc with active_child = None}

let update_child sc id ring =
  let children =
    List.map
      (fun (k, v) -> if String.equal k id then (k, ring) else (k, v))
      sc.children
  in
  {sc with children}

(** New unified scope key handler returning Key_event.result *)
let on_scope_key sc ~key =
  let open Miaou_interfaces.Key_event in
  match sc.active_child with
  | None -> (
      match key with
      | "Tab" | "S-Tab" | "Shift-Tab" | "BackTab" ->
          let parent, result = on_key sc.parent ~key in
          ({sc with parent}, result)
      | "Enter" ->
          let sc' = enter sc in
          if in_child sc' then (sc', Handled) else (sc, Bubble)
      | _ -> (sc, Bubble))
  | Some child_id -> (
      match key with
      | "Tab" | "S-Tab" | "Shift-Tab" | "BackTab" -> (
          match List.assoc_opt child_id sc.children with
          | Some ring ->
              let ring', result = on_key ring ~key in
              (update_child sc child_id ring', result)
          | None -> (sc, Bubble))
      | "Esc" | "Escape" -> ({sc with active_child = None}, Handled)
      | _ -> (sc, Bubble))

(** @deprecated Use [on_scope_key] instead. Returns polymorphic variant for compat. *)
let handle_scope_key sc ~key =
  let sc', result = on_scope_key sc ~key in
  let status =
    match result with
    | Miaou_interfaces.Key_event.Handled -> `Handled
    | Miaou_interfaces.Key_event.Bubble -> `Bubble
  in
  (sc', status)
