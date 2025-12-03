(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)
type page = (module Tui_page.PAGE_SIG)

let table : (string, page) Hashtbl.t = Hashtbl.create 8

let lazy_table : (string, unit -> page) Hashtbl.t = Hashtbl.create 8

let register name (p : page) = Hashtbl.replace table name p

let register_once name (p : page) : bool =
  if Hashtbl.mem table name then false
  else (
    Hashtbl.add table name p ;
    true)

let list () =
  let items = Hashtbl.fold (fun k v acc -> (k, v) :: acc) table [] in
  List.sort (fun (a, _) (b, _) -> compare a b) items

let exists name = Hashtbl.mem table name

let unregister name = Hashtbl.remove table name

let list_names () =
  Hashtbl.fold (fun k _ acc -> k :: acc) table [] |> List.sort compare

let register_lazy name thunk = Hashtbl.replace lazy_table name thunk

let override name p = Hashtbl.replace table name p

(* Resolve lazily on demand: if not in table, try lazy_table and populate table *)
let find name =
  match Hashtbl.find_opt table name with
  | Some p -> Some p
  | None -> (
      match Hashtbl.find_opt lazy_table name with
      | None -> None
      | Some f ->
          let p = f () in
          Hashtbl.replace table name p ;
          Some p)

(* Application-specific helpers (moved out).

	Note: functions to store a last selected instance are application-specific
	and were intentionally removed from this core Registry. Consumers that need
	such functionality should implement it in their application-specific modules
	(see `src/app_specific/registry.ml`). *)
