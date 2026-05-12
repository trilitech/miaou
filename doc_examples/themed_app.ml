(******************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(******************************************************************************)

module W = Miaou_widgets_display.Widgets

(* docs:start:semantic-styles *)
type status = Ok | Warning | Error

let render_status status message =
  match status with
  | Ok -> W.themed_success message
  | Warning -> W.themed_warning message
  | Error -> W.themed_error message
(* docs:end:semantic-styles *)

let render_panel () =
  String.concat
    "\n"
    [
      W.themed_emphasis "Deployment status";
      render_status Ok "Node is running";
      W.themed_muted "Use semantic styles so themes can control colors.";
    ]
