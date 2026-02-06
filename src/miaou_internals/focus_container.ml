(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

[@@@warning "-32-34-37-69"]

(** Widget operations for Focus_container.

    New API uses [on_key] with [Key_event.result].
    Legacy [handle_key] is still supported via adapters. *)
type 'a widget_ops = {
  render : 'a -> focus:bool -> string;
  on_key : 'a -> key:string -> 'a * Miaou_interfaces.Key_event.result;
}

(** @deprecated Legacy widget ops with polymorphic variant result. *)
type 'a widget_ops_legacy = {
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

(** New unified key handler returning Key_event.result *)
let on_key t ~key =
  let open Miaou_interfaces.Key_event in
  let ring', ring_result = Focus_ring.on_key t.ring ~key in
  match ring_result with
  | Handled -> ({t with ring = ring'}, Handled)
  | Bubble -> (
      match Focus_ring.current t.ring with
      | None -> (t, Bubble)
      | Some fid ->
          let status = ref Bubble in
          List.iter
            (fun (Slot s) ->
              if String.equal s.id fid then begin
                let state', st = s.ops.on_key s.state ~key in
                s.state <- state' ;
                status := st
              end)
            t.slots ;
          (t, !status))

(** @deprecated Use [on_key] instead. Returns polymorphic variant for compat. *)
let handle_key t ~key =
  let t', result = on_key t ~key in
  let status =
    match result with
    | Miaou_interfaces.Key_event.Handled -> `Handled
    | Miaou_interfaces.Key_event.Bubble -> `Bubble
  in
  (t', status)

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

(** Create widget_ops from render and on_key functions. *)
let ops ~render ~on_key = {render; on_key}

(** @deprecated Adapter: wrap simple handle_key that returns just state (bubbles). *)
let ops_simple ~render ~handle_key =
  {
    render;
    on_key =
      (fun st ~key -> (handle_key st ~key, Miaou_interfaces.Key_event.Bubble));
  }

(** @deprecated Adapter: wrap handle_key that returns (state, bool). *)
let ops_bool ~render ~handle_key =
  {
    render;
    on_key =
      (fun st ~key ->
        let st', fired = handle_key st ~key in
        ( st',
          if fired then Miaou_interfaces.Key_event.Handled
          else Miaou_interfaces.Key_event.Bubble ));
  }

(** Adapter: wrap legacy handle_key returning polymorphic variant. *)
let ops_of_legacy (legacy : 'a widget_ops_legacy) : 'a widget_ops =
  {
    render = legacy.render;
    on_key =
      (fun st ~key ->
        let st', status = legacy.handle_key st ~key in
        let result =
          match status with
          | `Handled -> Miaou_interfaces.Key_event.Handled
          | `Bubble -> Miaou_interfaces.Key_event.Bubble
        in
        (st', result));
  }
