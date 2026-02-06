(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

(** Named-slot focus ring with nested scope support.

    A [Focus_ring.t] manages a flat ring of named slots with Tab/Shift+Tab
    cycling, named lookup, and per-slot enable/disable.

    A [Focus_ring.scope] adds parent/child nesting: Tab stays within the
    active scope, Enter drills into a child scope, and Esc exits back to the
    parent.

    {[
    (* Flat ring *)
    let ring = Focus_ring.create ["search"; "filter"; "tree"] in
    let focused = Focus_ring.is_focused ring "search" in
    let ring, _ = Focus_ring.on_key ring ~key:"Tab" in
    ...

    (* Nested scopes *)
    let parent = Focus_ring.create ["sidebar"; "main"] in
    let sidebar = Focus_ring.create ["search"; "filter"] in
    let main = Focus_ring.create ["editor"; "preview"] in
    let sc = Focus_ring.scope ~parent
      ~children:[("sidebar", sidebar); ("main", main)] in
    let sc, _ = Focus_ring.on_scope_key sc ~key:"Enter" in
    (* Now inside the sidebar child ring *)
    ]} *)

type t

(** A single focusable slot. *)
type slot = {
  id : string;  (** Unique name within the ring. *)
  focusable : bool;  (** Whether this slot participates in Tab cycling. *)
}

(** Create a focus ring from a list of slot IDs (all focusable by default). *)
val create : string list -> t

(** Create from explicit slot definitions. *)
val create_slots : slot list -> t

(** Current focused slot ID ([None] if empty or all disabled). *)
val current : t -> string option

(** Current focused index ([None] if empty or all disabled). *)
val current_index : t -> int option

(** Is the given slot ID currently focused? Useful in [view] functions. *)
val is_focused : t -> string -> bool

(** Move focus forward or backward among focusable slots. Wraps around. *)
val move : t -> [`Next | `Prev] -> t

(** Handle Tab/Shift+Tab. Returns [Key_event.Handled] if consumed,
    [Key_event.Bubble] if the key should propagate. *)
val on_key : t -> key:string -> t * Miaou_interfaces.Key_event.result

(** @deprecated Use [on_key] instead. Returns polymorphic variant for compat. *)
val handle_key : t -> key:string -> t * [`Handled | `Bubble]

(** Focus a specific slot by ID. No-op if ID not found. *)
val focus : t -> string -> t

(** Enable or disable a slot for Tab cycling. When disabling the currently
    focused slot, focus moves to the next available slot. *)
val set_focusable : t -> string -> bool -> t

(** Total number of slots. *)
val total : t -> int

(** Number of currently focusable slots. *)
val focusable_count : t -> int

(** {1 Nested scopes}

    A scope tracks a parent ring and a map of child rings. Enter a child scope
    with {!enter}, exit back with {!exit}. Tab cycles within the active scope;
    Esc exits the child scope. *)

type scope

(** Create a scope from a parent ring and named child rings. Each child ring
    is associated with a parent slot by ID. *)
val scope : parent:t -> children:(string * t) list -> scope

(** The ring currently active in the scope (parent or child). *)
val active : scope -> t

(** Is the scope currently inside a child ring? *)
val in_child : scope -> bool

(** Name of the active child ring, if in a child scope. *)
val active_child_id : scope -> string option

(** Enter the child ring associated with the currently focused parent slot.
    No-op if the focused slot has no child ring. *)
val enter : scope -> scope

(** Exit the child ring, returning focus to the parent. No-op if already
    at the parent level. *)
val exit : scope -> scope

(** Update a child ring inside a scope. No-op if the child ID is not found. *)
val update_child : scope -> string -> t -> scope

(** Handle keys within the scope:
    - Tab/Shift+Tab cycle within the active ring
    - Enter enters a child scope (if available)
    - Esc exits a child scope back to the parent
    - Other keys bubble. *)
val on_scope_key :
  scope -> key:string -> scope * Miaou_interfaces.Key_event.result

(** @deprecated Use [on_scope_key] instead. Returns polymorphic variant for compat. *)
val handle_scope_key : scope -> key:string -> scope * [`Handled | `Bubble]
