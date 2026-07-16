(** H1 regression: the top-level catch-all in [Protocol_core.handle_cmd]
    converts any unanticipated exception into a well-formed [E_INTERNAL]
    response rather than letting it escape and crash the process.

    Kept in its own test executable/process: it needs
    [Lib_miaou_internal.Headless_driver.Stateful] to genuinely be
    uninitialized (which raises [Invalid_argument] from its internal
    [ensure ()] guard, a stand-in for "some unanticipated exception reaches
    handle_cmd") — every other protocol test in this suite calls
    [Protocol_core.init_session] at least once, and that state has no
    reset, so this assertion is only meaningful in a fresh process. *)

open Alcotest
module Protocol_core = Miaou_protocol.Protocol_core

let test_uninitialized_driver_yields_e_internal_not_a_crash () =
  Eio_main.run @@ fun _env ->
  (* Deliberately never call Protocol_core.init_session: HD.Stateful is
     uninitialized, so dispatching "key" reaches HD.Stateful.send_key's
     ensure () guard, which raises Invalid_argument — an unanticipated
     exception from Protocol_core's own perspective, exactly what the
     top-level catch-all exists to convert. *)
  let resp, cont =
    Protocol_core.handle_cmd [("cmd", `String "key"); ("key", `String "Down")]
  in
  check bool "keeps running, does not crash the process" true (cont = `Continue) ;
  match resp with
  | `Assoc fields ->
      check bool "type=error" true (List.assoc "type" fields = `String "error") ;
      check
        bool
        "code=E_INTERNAL"
        true
        (List.assoc "code" fields = `String "E_INTERNAL")
  | _ -> fail "expected a structured error response, not a crash"

let () =
  run
    "internal error catch-all"
    [
      ( "handle_cmd",
        [
          test_case
            "an unanticipated exception yields E_INTERNAL (H1)"
            `Quick
            test_uninitialized_driver_yields_e_internal_not_a_crash;
        ] );
    ]
