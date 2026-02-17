(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

type style = None_ | Single | Double | Rounded | Ascii | Heavy
[@@deriving yojson]

type chars = {
  tl : string;
  tr : string;
  bl : string;
  br : string;
  h : string;
  v : string;
  t_down : string;
  t_up : string;
  t_right : string;
  t_left : string;
  cross : string;
}

let single_chars =
  {
    tl = "┌";
    tr = "┐";
    bl = "└";
    br = "┘";
    h = "─";
    v = "│";
    t_down = "┬";
    t_up = "┴";
    t_right = "├";
    t_left = "┤";
    cross = "┼";
  }

let double_chars =
  {
    tl = "╔";
    tr = "╗";
    bl = "╚";
    br = "╝";
    h = "═";
    v = "║";
    t_down = "╦";
    t_up = "╩";
    t_right = "╠";
    t_left = "╣";
    cross = "╬";
  }

let rounded_chars =
  {
    tl = "╭";
    tr = "╮";
    bl = "╰";
    br = "╯";
    h = "─";
    v = "│";
    t_down = "┬";
    t_up = "┴";
    t_right = "├";
    t_left = "┤";
    cross = "┼";
  }

let ascii_chars =
  {
    tl = "+";
    tr = "+";
    bl = "+";
    br = "+";
    h = "-";
    v = "|";
    t_down = "+";
    t_up = "+";
    t_right = "+";
    t_left = "+";
    cross = "+";
  }

let heavy_chars =
  {
    tl = "┏";
    tr = "┓";
    bl = "┗";
    br = "┛";
    h = "━";
    v = "┃";
    t_down = "┳";
    t_up = "┻";
    t_right = "┣";
    t_left = "┫";
    cross = "╋";
  }

let none_chars =
  {
    tl = " ";
    tr = " ";
    bl = " ";
    br = " ";
    h = " ";
    v = " ";
    t_down = " ";
    t_up = " ";
    t_right = " ";
    t_left = " ";
    cross = " ";
  }

let chars_of_style = function
  | None_ -> none_chars
  | Single -> single_chars
  | Double -> double_chars
  | Rounded -> rounded_chars
  | Ascii -> ascii_chars
  | Heavy -> heavy_chars

let default_style = Single
