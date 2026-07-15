(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

let contains_substring s sub =
  let slen = String.length s in
  let sublen = String.length sub in
  if sublen = 0 then true
  else
    let rec aux i =
      if i + sublen > slen then false
      else if String.sub s i sublen = sub then true
      else aux (i + 1)
    in
    aux 0

let strip_ansi s =
  let len = String.length s in
  let buf = Buffer.create len in
  let i = ref 0 in
  while !i < len do
    if s.[!i] = '\027' && !i + 1 < len && s.[!i + 1] = '[' then (
      let j = ref (!i + 2) in
      while !j < len && s.[!j] <> 'm' do
        incr j
      done ;
      i := !j + 1)
    else begin
      Buffer.add_char buf s.[!i] ;
      incr i
    end
  done ;
  Buffer.contents buf

module type STATE = sig
  type state

  type pstate = state Miaou_core.Navigation.t
end

module Stub_page_defaults (S : STATE) = struct
  let move (ps : S.pstate) (_ : int) = ps

  let refresh (ps : S.pstate) = ps

  let service_select (ps : S.pstate) (_ : int) = ps

  let service_cycle (ps : S.pstate) (_ : int) = ps

  let back (ps : S.pstate) = ps

  let has_modal (_ : S.pstate) = false

  let key_hints (_ : S.pstate) : Miaou_core.Tui_page.key_hint list = []

  let handle_modal_key (ps : S.pstate) (_ : string) ~size:_ = ps

  let on_modal_key (ps : S.pstate) (_ : Miaou_core.Keys.t) ~size:_ =
    (ps, Miaou_interfaces.Key_event.Bubble)
end
