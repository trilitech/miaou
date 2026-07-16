(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Mathias Bourgoin <mathias.bourgoin@atacama.tech>        *)
(*                                                                            *)
(******************************************************************************)

type code =
  | E_BAD_REQUEST
  | E_UNSUPPORTED_COMMAND
  | E_TIMEOUT
  | E_READ_ONLY
  | E_INTERNAL

let code_to_string = function
  | E_BAD_REQUEST -> "E_BAD_REQUEST"
  | E_UNSUPPORTED_COMMAND -> "E_UNSUPPORTED_COMMAND"
  | E_TIMEOUT -> "E_TIMEOUT"
  | E_READ_ONLY -> "E_READ_ONLY"
  | E_INTERNAL -> "E_INTERNAL"

type t = {
  code : code option;
  step : string;
  message : string;
  attempt : int option;
  screen : string option;
}

let make ?code ?attempt ?screen ~step message =
  {code; step; message; attempt; screen}

let to_yojson ~schema_version {code; step; message; attempt; screen} =
  let base =
    [
      ("type", `String "error");
      ("schema_version", `String schema_version);
      ("step", `String step);
      ("message", `String message);
    ]
  in
  let with_code =
    match code with
    | Some c -> base @ [("code", `String (code_to_string c))]
    | None -> base
  in
  let with_attempt =
    match attempt with
    | Some a -> with_code @ [("attempt", `Int a)]
    | None -> with_code
  in
  let with_screen =
    match screen with
    | Some s -> with_attempt @ [("screen", `String s)]
    | None -> with_attempt
  in
  `Assoc with_screen
