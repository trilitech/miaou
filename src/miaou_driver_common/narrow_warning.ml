(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

module Modal_manager = Miaou_core.Modal_manager
module Narrow_modal = Miaou_core.Narrow_modal
module Logger_capability = Miaou_interfaces.Logger_capability
module Fibers = Miaou_helpers.Fiber_runtime
module Widgets = Miaou_widgets_display.Widgets

type t = {mutable narrow_warned : bool; mutable last_cols : int option}

let create () = {narrow_warned = false; last_cols = None}

let narrow_modal_title = "Narrow terminal"

let header_lines ~cols =
  if cols < 80 then
    [
      Widgets.warning_banner
        ~cols
        (Printf.sprintf
           "Narrow terminal: %d cols (< 80). Some UI may be truncated."
           cols);
    ]
  else []

let push_modal () =
  Modal_manager.push
    (module Narrow_modal.Page)
    ~init:(Narrow_modal.Page.init ())
    ~ui:
      {
        Modal_manager.title = narrow_modal_title;
        left = Some 2;
        max_width = None;
        dim_background = true;
      }
    ~commit_on:[]
    ~cancel_on:[]
    ~on_close:(fun _ _ -> ()) ;
  (* Mark the next key as consumed so Enter/Esc won't propagate. *)
  Modal_manager.set_consume_next_key () ;
  (* Auto-dismiss after 5s. We only close the modal if it's still the same
     top modal title to avoid racing with other modals. *)
  Fibers.spawn (fun env ->
      Eio.Time.sleep env#clock 5.0 ;
      match Modal_manager.top_title_opt () with
      | Some title when title = narrow_modal_title ->
          Modal_manager.close_top `Cancel
      | _ -> ())

let maybe_warn t ~cols =
  let prev_cols = Option.value ~default:cols t.last_cols in
  t.last_cols <- Some cols ;
  if cols < 80 && not t.narrow_warned then (
    (match Logger_capability.get () with
    | Some logger ->
        logger.logf
          Warning
          (Printf.sprintf
             "WIDTH_CROSSING: prev=%d new=%d (showing narrow modal)"
             prev_cols
             cols)
    | None -> ()) ;
    t.narrow_warned <- true ;
    push_modal ())
