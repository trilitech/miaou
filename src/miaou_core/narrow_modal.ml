(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

open Tui_page

module Page : PAGE_SIG = struct
  type state = string

  type msg = unit

  let handle_modal_key s _ ~size:_ = s

  let handle_key s _ ~size:_ = s

  let update s _ = s

  let move s _ = s

  let refresh s = s

  let enter s = s

  let service_select s _ = s

  let service_cycle s _ = s

  let back s = s

  let next_page _ = None

  let has_modal _ = false

  let init () =
    "Your terminal is narrow (< 80 cols). For best experience, widen it. Press any key to dismiss."

  let view s ~focus:_ ~size:_ = s

  let keymap (_ : state) = []
end
