(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

type direction = Row | Column

type align_items = Start | Center | End | Stretch

type justify = Start | Center | End | Space_between | Space_around

type spacing = {h : int; v : int}

type padding = {left : int; right : int; top : int; bottom : int}

type basis =
  | Auto
  | Px of int
  | Ratio of float
  | Percent of float
  | Fill

type size_hint = {width : int option; height : int option}

type child = {
  render : size:LTerm_geom.size -> string;
  basis : basis;
  cross : size_hint option;
}

type t

val create :
  ?direction:direction ->
  ?align_items:align_items ->
  ?justify:justify ->
  ?gap:spacing ->
  ?padding:padding ->
  child list ->
  t

val render : t -> size:LTerm_geom.size -> string
