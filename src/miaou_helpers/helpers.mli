(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

val is_utf8_lead : char -> bool

val utf8_prev_boundary : string -> int -> int

val utf8_next_boundary : string -> int -> int

val utf8_clamp_boundary : string -> int -> int

val is_esc_start : string -> int -> bool

val is_osc_start : string -> int -> bool

val skip_ansi_until_m : string -> int -> int

val skip_osc_until_st : string -> int -> int

val sanitize_osc_payload : string -> string

val visible_chars_count : string -> int

val visible_byte_index_of_pos : string -> int -> int

val has_trailing_reset : string -> bool

val insert_before_reset : string -> string -> string

val pad_to_width : string -> int -> char -> string

(** Efficiently concatenate lines with newlines using Buffer *)
val concat_lines : string list -> string

(** Efficiently concatenate strings with separator using Buffer *)
val concat_with_sep : string -> string list -> string

(** Read the entire contents of the file at [path] as a string.

    The channel is always closed, including when [path] cannot be opened
    or reading raises partway through — [Error exn] carries whatever
    exception was raised (e.g. [Sys_error] for a missing file). *)
val read_file : string -> (string, exn) result
