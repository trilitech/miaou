(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

type style = None_ | Single | Double | Rounded | Ascii | Heavy

let style_to_yojson = function
  | None_ -> `String "None"
  | Single -> `String "Single"
  | Double -> `String "Double"
  | Rounded -> `String "Rounded"
  | Ascii -> `String "Ascii"
  | Heavy -> `String "Heavy"

let style_of_yojson = function
  | `String s -> (
      match String.lowercase_ascii s with
      | "none" | "none_" -> Ok None_
      | "single" -> Ok Single
      | "double" -> Ok Double
      | "rounded" -> Ok Rounded
      | "ascii" -> Ok Ascii
      | "heavy" -> Ok Heavy
      | _ -> Error "Border.style")
  | `List [`String "None"] -> Ok None_
  | `List [`String "Single"] -> Ok Single
  | `List [`String "Double"] -> Ok Double
  | `List [`String "Rounded"] -> Ok Rounded
  | `List [`String "Ascii"] -> Ok Ascii
  | `List [`String "Heavy"] -> Ok Heavy
  | `Assoc [("None", _)] -> Ok None_
  | `Assoc [("Single", _)] -> Ok Single
  | `Assoc [("Double", _)] -> Ok Double
  | `Assoc [("Rounded", _)] -> Ok Rounded
  | `Assoc [("Ascii", _)] -> Ok Ascii
  | `Assoc [("Heavy", _)] -> Ok Heavy
  | _ -> Error "Border.style"

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
