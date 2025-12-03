(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

val is_utf8_lead : char -> bool

val is_esc_start : string -> int -> bool

val skip_ansi_until_m : string -> int -> int

val visible_chars_count : string -> int

val visible_byte_index_of_pos : string -> int -> int

val has_trailing_reset : string -> bool

val insert_before_reset : string -> string -> string
