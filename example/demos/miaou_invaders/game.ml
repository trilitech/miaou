(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

(** Miaou Invaders mini-game demo.

    Showcases Canvas, Canvas_widget, Animation, Clock, and Timer
    capabilities working together. *)

module Inner = struct
  let tutorial_title = "Miaou Invaders"

  let tutorial_markdown = [%blob "README.md"]

  include Model
  include Logic
  include Render
  include Control
end

include Demo_shared.Demo_page.MakeSimple (Inner)
