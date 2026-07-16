(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Mathias Bourgoin <mathias.bourgoin@atacama.tech>        *)
(*                                                                            *)
(******************************************************************************)

module HD = Lib_miaou_internal.Headless_driver
module Tui_page = Miaou_core.Tui_page
module Tui_capture = Miaou_core.Tui_capture
module Modal_manager = Miaou_core.Modal_manager

(* ── ANSI strip ─────────────────────────────────────────────────────────── *)

let ansi_strip s =
  let buf = Buffer.create (String.length s) in
  let n = String.length s in
  let i = ref 0 in
  while !i < n do
    if s.[!i] = '\x1b' then (
      incr i ;
      if !i < n && s.[!i] = '[' then (
        (* CSI sequence: ESC [ ... <final byte 0x40-0x7e> *)
        incr i ;
        while !i < n && (s.[!i] < '@' || s.[!i] > '~') do
          incr i
        done ;
        if !i < n then incr i (* consume final byte *))
      else if !i < n then incr i (* skip single char after ESC (Fe sequence) *))
    else (
      Buffer.add_char buf s.[!i] ;
      incr i)
  done ;
  Buffer.contents buf

(* ── on_frame callback ──────────────────────────────────────────────────── *)

let on_frame_fn : (rows:int -> cols:int -> string -> unit) option ref = ref None

let set_on_frame f = on_frame_fn := f

(* ── Session lifecycle ──────────────────────────────────────────────────── *)

let init_session ?(no_record = false) (page : (module Tui_page.PAGE_SIG)) =
  if no_record then Tui_capture.disable () else Tui_capture.force_enable () ;
  let module P = (val page : Tui_page.PAGE_SIG) in
  HD.Stateful.init (module P)

(* ── Response builders ──────────────────────────────────────────────────── *)

let schema_version = Protocol_version.current

let current_frame () =
  let size = HD.get_size () in
  let raw = HD.Screen.get () in
  (match !on_frame_fn with
  | Some f -> f ~rows:size.LTerm_geom.rows ~cols:size.LTerm_geom.cols raw
  | None -> ()) ;
  let text = ansi_strip raw in
  `Assoc
    [
      ("type", `String "frame");
      ("schema_version", `String schema_version);
      ("text", `String text);
      ("rows", `Int size.LTerm_geom.rows);
      ("cols", `Int size.LTerm_geom.cols);
    ]

let nav_response action =
  `Assoc
    [
      ("type", `String "nav");
      ("schema_version", `String schema_version);
      ("action", `String action);
    ]

let error_response ?code ?attempt ?screen ~step message =
  Protocol_errors.to_yojson
    ~schema_version
    (Protocol_errors.make ?code ?attempt ?screen ~step message)

let assert_result ~step ~screen ok =
  if ok then
    `Assoc
      [
        ("type", `String "assert_result");
        ("schema_version", `String schema_version);
        ("ok", `Bool true);
      ]
  else
    `Assoc
      [
        ("type", `String "assert_result");
        ("schema_version", `String schema_version);
        ("ok", `Bool false);
        ( "error",
          error_response ~screen ~step "predicate did not match current screen"
        );
      ]

(* ── wait_for conditions (TEXT-FIRST v1: no semantic tree, no locators) ──── *)

type wait_condition =
  | Cond_modal of bool
  | Cond_text_contains of string
  | Cond_text_matches of string
  | Cond_page of string

let parse_condition (fields : (string * Yojson.Safe.t) list) :
    (wait_condition, string) result =
  match
    ( List.assoc_opt "modal" fields,
      List.assoc_opt "text_contains" fields,
      List.assoc_opt "text_matches" fields,
      List.assoc_opt "page" fields )
  with
  | Some (`Bool b), None, None, None -> Ok (Cond_modal b)
  | None, Some (`String s), None, None -> Ok (Cond_text_contains s)
  | None, None, Some (`String s), None -> (
      (* H1 fix: Str.regexp raises Failure (not Not_found) on a malformed
         pattern. Validate at parse time so a bad pattern is a normal
         E_BAD_REQUEST response, not an exception that could otherwise
         propagate out of handle_cmd and crash the transport loop. *)
      try
        ignore (Str.regexp s) ;
        Ok (Cond_text_matches s)
      with Failure msg ->
        Error (Printf.sprintf "invalid 'text_matches' regex: %s" msg))
  | None, None, None, Some (`String s) -> Ok (Cond_page s)
  | _ ->
      Error
        "wait_for 'condition' must have exactly one of: modal (bool), \
         text_contains (string), text_matches (string), page (string)"

(* wait_for's condition is checked against the ANSI-stripped current screen
   text (TEXT-FIRST v1: no semantic snapshot tree, see docs/agent-protocol.md).
   [Cond_text_matches]'s pattern was already validated to compile in
   [parse_condition], so [Str.regexp] here cannot raise. *)
let condition_holds = function
  | Cond_modal expected -> Modal_manager.has_active () = expected
  | Cond_text_contains needle -> (
      let text = ansi_strip (HD.Screen.get ()) in
      try
        ignore (Str.search_forward (Str.regexp_string needle) text 0) ;
        true
      with Not_found -> false)
  | Cond_text_matches pattern -> (
      let text = ansi_strip (HD.Screen.get ()) in
      try
        ignore (Str.search_forward (Str.regexp pattern) text 0) ;
        true
      with Not_found -> false)
  | Cond_page name -> !HD.Stateful.current_page_name = Some name

(* Defaults mirror Workflow.await_modal's (max_iters = 50, sleep = 0.01),
   i.e. a 500ms timeout polled every 10ms. *)
let default_timeout_ms = 500

let default_poll_interval_ms = 10

(* wait_for is a single blocking server-side call (FR-041): the client issues
   one request/response pair; polling happens entirely inside this loop.

   Must run on the *main* fiber via [Eio_unix.sleep] between polls, not
   [Eio_unix.run_in_systhread]: [HD.Stateful.idle_wait]'s [Fibers.switch_opt]
   branch calls [Eio.Fiber.yield], which has no effect handler installed in a
   systhread and crashes; a systhread would also race the viewer daemon
   fiber's concurrent reads of [HD.Screen]/[HD.get_size]. Documentation note
   (spec risk table, Slice 4): each poll calls [idle_wait], which ticks
   clocks/timers and refreshes the page — so wait_for is not a passive
   observer even though it never sends a key; this is accepted for
   TEXT-FIRST v1's read-only classification (FR-081) since it never calls
   [send_key]/[switch_to_page]. *)
let wait_for_loop condition ~timeout_ms ~poll_interval_ms =
  let deadline = Unix.gettimeofday () +. (float_of_int timeout_ms /. 1000.0) in
  let poll_interval = float_of_int poll_interval_ms /. 1000.0 in
  (* Check first (mirrors Workflow.poll's [if ready () then ()] before any
     sleep/refresh): an already-true condition is observed immediately,
     without ticking clocks/timers or advancing the page even once. *)
  let rec go attempt =
    if condition_holds condition then current_frame ()
    else if Unix.gettimeofday () >= deadline then
      let screen = ansi_strip (HD.Screen.get ()) in
      error_response
        ~code:Protocol_errors.E_TIMEOUT
        ~attempt
        ~screen
        ~step:"wait_for"
        "condition not met before timeout"
    else (
      ignore (HD.Stateful.idle_wait ~iterations:1 ~sleep:0.0 ()) ;
      Eio_unix.sleep poll_interval ;
      go (attempt + 1))
  in
  go 0

(* ── Canonical command list (M1: MCP-classification exhaustiveness) ─────── *)

(* Every string literal [handle_cmd_inner] matches on [cmd]'s "cmd" field.
   Kept as an explicit list (rather than derived from the match, which
   OCaml can't introspect) so a shared conformance test can assert every
   dispatchable command is accounted for in the MCP tool classification
   (Mcp_tools.classification) — catching, at test time, a new command added
   to the match below without updating that classification. *)
let dispatchable_commands =
  [
    "render";
    "key";
    "click";
    "tick";
    "resize";
    "quit";
    "wait_for";
    "assert_screen";
  ]

(* Dispatchable commands that are deliberately NOT exposed as MCP tools.
   "click" is TEXT-FIRST v1's pre-existing row/col-ignoring stub (spatial
   click is deferred, see docs/agent-protocol.md); it stays reachable over
   JSON-over-stdio for backward compatibility (FR-100) but is intentionally
   absent from Mcp_tools.classification. *)
let deferred_commands = ["click"]

(* ── Command dispatch ────────────────────────────────────────────────────── *)

let handle_cmd_inner (cmd : (string * Yojson.Safe.t) list) :
    Yojson.Safe.t * [`Continue | `Stop] =
  let get_string key =
    match List.assoc_opt key cmd with Some (`String s) -> Some s | _ -> None
  in
  let get_int key =
    match List.assoc_opt key cmd with Some (`Int n) -> Some n | _ -> None
  in
  match get_string "cmd" with
  | None ->
      ( error_response
          ~code:Protocol_errors.E_BAD_REQUEST
          ~step:"dispatch"
          "Missing 'cmd' field",
        `Continue )
  | Some "render" -> (current_frame (), `Continue)
  | Some "key" -> (
      match get_string "key" with
      | None ->
          ( error_response
              ~code:Protocol_errors.E_BAD_REQUEST
              ~step:"key"
              "Missing 'key' field",
            `Continue )
      | Some k -> (
          let outcome = HD.Stateful.send_key k in
          let outcome =
            match outcome with
            | `Continue -> HD.Stateful.idle_wait ~iterations:3 ()
            | other -> other
          in
          match outcome with
          | `Quit -> (nav_response "quit", `Stop)
          | `Back -> (nav_response "back", `Stop)
          | `SwitchTo name -> (nav_response ("switch:" ^ name), `Continue)
          | `Continue -> (current_frame (), `Continue)))
  | Some "click" ->
      (* Spatial click is DEFERRED (TEXT-FIRST v1 scope decision): row/col
         are accepted but ignored; the frame is simply re-rendered. *)
      ignore (get_int "row") ;
      ignore (get_int "col") ;
      (current_frame (), `Continue)
  | Some "tick" -> (
      let n = Option.value ~default:1 (get_int "n") in
      let outcome = HD.Stateful.idle_wait ~iterations:n () in
      let resp =
        match outcome with
        | `Quit -> nav_response "quit"
        | `Back -> nav_response "back"
        | `SwitchTo name -> nav_response ("switch:" ^ name)
        | `Continue -> current_frame ()
      in
      (resp, match outcome with `Quit | `Back -> `Stop | _ -> `Continue))
  | Some "resize" -> (
      match (get_int "rows", get_int "cols") with
      | Some rows, Some cols ->
          HD.set_size rows cols ;
          (current_frame (), `Continue)
      | _ ->
          ( error_response
              ~code:Protocol_errors.E_BAD_REQUEST
              ~step:"resize"
              "Missing 'rows' or 'cols'",
            `Continue ))
  | Some "quit" -> (nav_response "quit", `Stop)
  | Some "wait_for" -> (
      match List.assoc_opt "condition" cmd with
      | Some (`Assoc fields) -> (
          match parse_condition fields with
          | Error msg ->
              ( error_response
                  ~code:Protocol_errors.E_BAD_REQUEST
                  ~step:"wait_for"
                  msg,
                `Continue )
          | Ok condition ->
              let timeout_ms =
                Option.value ~default:default_timeout_ms (get_int "timeout_ms")
              in
              let poll_interval_ms =
                Option.value
                  ~default:default_poll_interval_ms
                  (get_int "poll_interval_ms")
              in
              (wait_for_loop condition ~timeout_ms ~poll_interval_ms, `Continue)
          )
      | _ ->
          ( error_response
              ~code:Protocol_errors.E_BAD_REQUEST
              ~step:"wait_for"
              "Missing 'condition' field",
            `Continue ))
  | Some "assert_screen" -> (
      let text = ansi_strip (HD.Screen.get ()) in
      match (get_string "contains", get_string "matches") with
      | Some needle, None ->
          let ok =
            try
              ignore (Str.search_forward (Str.regexp_string needle) text 0) ;
              true
            with Not_found -> false
          in
          (assert_result ~step:"assert_screen" ~screen:text ok, `Continue)
      | None, Some pattern -> (
          (* H1 fix: Str.regexp raises Failure (not Not_found) on a
             malformed pattern (e.g. "["); compiling it separately from the
             search lets a bad pattern become E_BAD_REQUEST instead of an
             uncaught exception. *)
          match try Ok (Str.regexp pattern) with Failure msg -> Error msg with
          | Error msg ->
              ( error_response
                  ~code:Protocol_errors.E_BAD_REQUEST
                  ~step:"assert_screen"
                  (Printf.sprintf "invalid 'matches' regex: %s" msg),
                `Continue )
          | Ok re ->
              let ok =
                try
                  ignore (Str.search_forward re text 0) ;
                  true
                with Not_found -> false
              in
              (assert_result ~step:"assert_screen" ~screen:text ok, `Continue))
      | _ ->
          ( error_response
              ~code:Protocol_errors.E_BAD_REQUEST
              ~step:"assert_screen"
              "Expected exactly one of 'contains'/'matches'",
            `Continue ))
  | Some other ->
      ( error_response
          ~code:Protocol_errors.E_UNSUPPORTED_COMMAND
          ~step:"dispatch"
          (Printf.sprintf "Unknown command: %s" other),
        `Continue )

let handle_cmd_dispatch (cmd : (string * Yojson.Safe.t) list) :
    Yojson.Safe.t * [`Continue | `Stop] =
  match List.assoc_opt "protocol_version" cmd with
  | Some (`String v) when not (Protocol_version.is_supported v) ->
      ( error_response
          ~code:Protocol_errors.E_BAD_REQUEST
          ~step:"protocol_version"
          (Printf.sprintf "Unsupported protocol_version: %s" v),
        `Continue )
  | _ -> handle_cmd_inner cmd

(* H1 fix: a top-level catch-all. Every *known* failure mode (malformed
   regex, missing fields, unknown commands) is already mapped to a
   structured error above without raising; this is a defense-in-depth net
   so that any *unanticipated* exception reaching here — a bug, not a
   validated-input case — still yields a well-formed E_INTERNAL response
   instead of an uncaught exception propagating into the transport loop and
   crashing the whole runner/server process (both callers, the stdio shim
   and miaou-mcp's tool handlers, have no try around this call). Eio's
   structured-concurrency cancellation must not be swallowed here — it is
   re-raised unchanged so a cancelled switch still unwinds correctly. *)
let handle_cmd (cmd : (string * Yojson.Safe.t) list) :
    Yojson.Safe.t * [`Continue | `Stop] =
  match handle_cmd_dispatch cmd with
  | result -> result
  | exception (Eio.Cancel.Cancelled _ as exn) -> raise exn
  | exception exn ->
      ( error_response
          ~code:Protocol_errors.E_INTERNAL
          ~step:"dispatch"
          (Printf.sprintf
             "unexpected internal failure: %s"
             (Printexc.to_string exn)),
        `Continue )
