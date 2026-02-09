(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

open Miaou_core.Tui_page
module Navigation = Miaou_core.Navigation

type 'r handler = {
  on_quit : unit -> 'r;
  on_back : unit -> 'r;
  on_same_page : unit -> 'r;
  on_new_page :
    'new_s.
    (module PAGE_SIG with type state = 'new_s) -> 'new_s Navigation.t -> 'r;
}

(** [handle_next_page page_module ps handler] checks if the current page requests
    a transition and invokes the appropriate callback:
    - Calls [handler.on_quit ()] if the page requests [Quit] or an unknown page
    - Calls [handler.on_back ()] if the page requests [Back]
    - Calls [handler.on_same_page ()] if no transition requested
    - Calls [handler.on_new_page next_module next_pstate] if transitioning to a valid page

    The [on_new_page] field uses a universal quantifier to handle pages with any state type.

    This eliminates duplication in page transition lookup logic across drivers.
    Drivers can perform any custom transition effects in the [on_new_page] callback. *)
val handle_next_page :
  (module PAGE_SIG with type state = 's) -> 's Navigation.t -> 'r handler -> 'r
