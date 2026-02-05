(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

[@@@warning "-32-34-37-69"]

type 'a widget_ops = {
  render : 'a -> focus:bool -> string;
  handle_key : 'a -> key:string -> 'a * [`Handled | `Bubble];
}

(* Type equality witness via extensible GADT — no Obj.magic needed.
   Same approach as Hmap / Univ_map. *)

type (_, _) teq = Teq : ('a, 'a) teq

type _ witness_key = ..

type 'a witness = {
  key : 'a witness_key;
  cast : 'b. 'b witness_key -> ('a, 'b) teq option;
}

let witness (type a) () : a witness =
  let module M = struct
    type _ witness_key += K : a witness_key
  end in
  {
    key = M.K;
    cast =
      (fun (type b) (k : b witness_key) : (a, b) teq option ->
        match k with M.K -> Some Teq | _ -> None);
  }

type packed_slot =
  | Slot : {
      id : string;
      ops : 'a widget_ops;
      mutable state : 'a;
      wkey : 'a witness_key option;
    }
      -> packed_slot

let slot id ops state = Slot {id; ops; state; wkey = None}

let slot_w id ops state (w : _ witness) =
  Slot {id; ops; state; wkey = Some w.key}

type t = {ring : Focus_ring.t; slots : packed_slot list}

let create slots =
  let ids = List.map (fun (Slot s) -> s.id) slots in
  let ring = Focus_ring.create ids in
  {ring; slots}

let count t = List.length t.slots

let focused_id t = Focus_ring.current t.ring

let ring t = t.ring

let set_ring t r = {t with ring = r}

let focus t id = {t with ring = Focus_ring.focus t.ring id}

let render_all t =
  let focused = Focus_ring.current t.ring in
  List.map
    (fun (Slot s) ->
      let is_focused =
        match focused with Some fid -> String.equal s.id fid | None -> false
      in
      (s.id, is_focused, s.ops.render s.state ~focus:is_focused))
    t.slots

let render_focused t =
  match Focus_ring.current t.ring with
  | None -> None
  | Some fid -> (
      match List.find_opt (fun (Slot s) -> String.equal s.id fid) t.slots with
      | None -> None
      | Some (Slot s) -> Some (s.id, s.ops.render s.state ~focus:true))

let handle_key t ~key =
  let ring', ring_status = Focus_ring.handle_key t.ring ~key in
  match ring_status with
  | `Handled -> ({t with ring = ring'}, `Handled)
  | `Bubble -> (
      match Focus_ring.current t.ring with
      | None -> (t, `Bubble)
      | Some fid ->
          let status = ref `Bubble in
          List.iter
            (fun (Slot s) ->
              if String.equal s.id fid then begin
                let state', st = s.ops.handle_key s.state ~key in
                s.state <- state' ;
                status := st
              end)
            t.slots ;
          (t, !status))

(* Type-safe extraction via extensible GADT witness *)

let get : type a. t -> string -> a witness -> a option =
 fun t id w ->
  match List.find_opt (fun (Slot s) -> String.equal s.id id) t.slots with
  | None -> None
  | Some (Slot s) -> (
      match s.wkey with
      | None -> None
      | Some k -> (
          match w.cast k with Some Teq -> Some s.state | None -> None))

let set : type a. t -> string -> a witness -> a -> t =
 fun t id w v ->
  List.iter
    (fun (Slot s) ->
      if String.equal s.id id then
        match s.wkey with
        | None -> ()
        | Some k -> (
            match w.cast k with Some Teq -> s.state <- v | None -> ()))
    t.slots ;
  t

(* Adapter constructors *)
let ops_simple ~render ~handle_key =
  {render; handle_key = (fun st ~key -> (handle_key st ~key, `Bubble))}

let ops_bool ~render ~handle_key =
  {
    render;
    handle_key =
      (fun st ~key ->
        let st', fired = handle_key st ~key in
        (st', if fired then `Handled else `Bubble));
  }
