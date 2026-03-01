(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Mathias Bourgoin <mathias.bourgoin@atacama.tech>        *)
(*                                                                            *)
(******************************************************************************)

type entry = {name : string; mli : string}

let mutex = Mutex.create ()

let table : (string, entry) Hashtbl.t = Hashtbl.create 32

let register ~name ~mli () =
  Mutex.lock mutex ;
  Hashtbl.replace table name {name; mli} ;
  Mutex.unlock mutex

let list () =
  Mutex.lock mutex ;
  let entries =
    Hashtbl.fold (fun _ e acc -> e :: acc) table []
    |> List.sort (fun a b -> String.compare a.name b.name)
  in
  Mutex.unlock mutex ;
  entries

let find ~name =
  Mutex.lock mutex ;
  let result = Hashtbl.find_opt table name in
  Mutex.unlock mutex ;
  result

let search ~query =
  let q = String.lowercase_ascii query in
  Mutex.lock mutex ;
  let results =
    Hashtbl.fold
      (fun _ e acc ->
        let haystack = String.lowercase_ascii (e.name ^ " " ^ e.mli) in
        if
          let len_h = String.length haystack and len_q = String.length q in
          let rec loop i =
            if i + len_q > len_h then false
            else if String.sub haystack i len_q = q then true
            else loop (i + 1)
          in
          loop 0
        then e :: acc
        else acc)
      table
      []
    |> List.sort (fun a b -> String.compare a.name b.name)
  in
  Mutex.unlock mutex ;
  results
