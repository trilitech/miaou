(*****************************************************************************
 *                                                                           *
 * SPDX-License-Identifier: MIT                                              *
 * Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *
 *                                                                           *
 *****************************************************************************)

(** Runtime version information for Miaou.

    This module is intentionally kept in sync with the package version declared
    in [dune-project] for each release. *)

(** Semantic version of the Miaou release. *)
val version : string

(** Major version component. *)
val major : int

(** Minor version component. *)
val minor : int

(** Patch version component. *)
val patch : int
