(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Mathias Bourgoin <mathias.bourgoin@atacama.tech>        *)
(*                                                                            *)
(******************************************************************************)

(* Regression test for crash-ub-fixes slice S9: [Miaou_core.Service_lifecycle]
   used to share its capability key with [Miaou_interfaces.Service_lifecycle]
   via [Obj.magic], and on the interface-fallback path additionally
   [Obj.magic]-cast an interface value straight into the core module's [t] —
   despite the two [t]s having different closure shapes (different status
   variant representation, and [remove_instance_files] with vs. without
   [~role]). This registers an implementation only via the interface module
   (as an external "Systemd_service_lifecycle"-style adapter would), fetches
   it through core's [require], and exercises every method to prove the
   explicit adapter round-trips correctly instead of reinterpreting bytes. *)

open Alcotest
module Iface = Miaou_interfaces.Service_lifecycle
module Core = Miaou_core.Service_lifecycle

let make_mock_iface () =
  let calls = ref [] in
  let record name = calls := name :: !calls in
  let iv =
    Iface.create
      ~start:(fun ~role ~service ->
        record (Printf.sprintf "start:%s:%s" role service) ;
        Ok ())
      ~stop:(fun ~role ~service ->
        record (Printf.sprintf "stop:%s:%s" role service) ;
        Ok ())
      ~restart:(fun ~role ~service ->
        record (Printf.sprintf "restart:%s:%s" role service) ;
        Ok ())
      ~status:(fun ~role ~service ->
        record (Printf.sprintf "status:%s:%s" role service) ;
        if service = "failing" then Ok (`Failed "boom")
        else if service = "down" then Ok `Inactive
        else Ok `Active)
      ~install_unit:(fun ~role ~app_bin_dir:_ ~user ->
        record (Printf.sprintf "install_unit:%s:%s" role user) ;
        Ok ())
      ~write_dropin_node:(fun ~inst ~data_dir ~app_bin_dir:_ ->
        record (Printf.sprintf "write_dropin_node:%s:%s" inst data_dir) ;
        Ok ())
      ~enable_start:(fun ~role ~inst ->
        record (Printf.sprintf "enable_start:%s:%s" role inst) ;
        Ok ())
      ~enable:(fun ~role ~inst ->
        record (Printf.sprintf "enable:%s:%s" role inst) ;
        Ok ())
      ~disable:(fun ~role ~inst ->
        record (Printf.sprintf "disable:%s:%s" role inst) ;
        Ok ())
      ~remove_instance_files:(fun ~inst ~remove_data ->
        (* Deliberately no [~role] here: the interface is role-agnostic. *)
        record (Printf.sprintf "remove_instance_files:%s:%b" inst remove_data) ;
        Ok ())
  in
  (iv, calls)

let with_clean_capability f =
  Miaou_interfaces.Capability.clear () ;
  Fun.protect ~finally:Miaou_interfaces.Capability.clear f

let test_adapter_roundtrips_all_methods () =
  with_clean_capability (fun () ->
      let iv, calls = make_mock_iface () in
      Iface.register iv ;
      let v = Core.require () in
      check
        (result unit string)
        "start"
        (Ok ())
        (Core.start v ~role:"node" ~service:"svc") ;
      check
        (result unit string)
        "stop"
        (Ok ())
        (Core.stop v ~role:"node" ~service:"svc") ;
      check
        (result unit string)
        "restart"
        (Ok ())
        (Core.restart v ~role:"node" ~service:"svc") ;
      check
        (result unit string)
        "install_unit"
        (Ok ())
        (Core.install_unit v ~role:"node" ~app_bin_dir:None ~user:"u") ;
      check
        (result unit string)
        "write_dropin_node"
        (Ok ())
        (Core.write_dropin_node v ~inst:"i1" ~data_dir:"/d" ~app_bin_dir:None) ;
      check
        (result unit string)
        "enable_start"
        (Ok ())
        (Core.enable_start v ~role:"node" ~inst:"i1") ;
      check
        (result unit string)
        "enable"
        (Ok ())
        (Core.enable v ~role:"node" ~inst:"i1") ;
      check
        (result unit string)
        "disable"
        (Ok ())
        (Core.disable v ~role:"node" ~inst:"i1") ;
      (* remove_instance_files: core's signature carries ~role, the
         interface's does not — the adapter must drop it, not corrupt the
         call (the pre-fix Obj.magic cast would call through the wrong
         closure arity here). *)
      check
        (result unit string)
        "remove_instance_files"
        (Ok ())
        (Core.remove_instance_files v ~role:"node" ~inst:"i1" ~remove_data:true) ;
      check
        bool
        "remove_instance_files call reached the mock with the right args (role \
         dropped)"
        true
        (List.mem "remove_instance_files:i1:true" !calls))

let test_status_variant_translation () =
  with_clean_capability (fun () ->
      let iv, _calls = make_mock_iface () in
      Iface.register iv ;
      let v = Core.require () in
      check
        (result
           (of_pp (fun fmt -> function
             | Core.Running -> Format.fprintf fmt "Running"
             | Core.Stopped -> Format.fprintf fmt "Stopped"
             | Core.Failed m -> Format.fprintf fmt "Failed %s" m))
           string)
        "Active -> Running"
        (Ok Core.Running)
        (Core.get_status v ~role:"node" ~service:"up") ;
      check
        (result
           (of_pp (fun fmt -> function
             | Core.Running -> Format.fprintf fmt "Running"
             | Core.Stopped -> Format.fprintf fmt "Stopped"
             | Core.Failed m -> Format.fprintf fmt "Failed %s" m))
           string)
        "Inactive -> Stopped"
        (Ok Core.Stopped)
        (Core.get_status v ~role:"node" ~service:"down") ;
      match Core.get_status v ~role:"node" ~service:"failing" with
      | Ok (Core.Failed msg) ->
          check string "Failed message preserved" "boom" msg
      | Ok _ -> fail "expected Failed"
      | Error _ -> fail "expected Ok (Failed _)")

let test_fallback_stub_when_nothing_registered () =
  with_clean_capability (fun () ->
      let v = Core.require () in
      match Core.start v ~role:"r" ~service:"s" with
      | Error _ -> ()
      | Ok () -> fail "expected fallback stub to report unavailability")

let () =
  run
    "service_lifecycle_adapter"
    [
      ( "service_lifecycle_adapter",
        [
          test_case
            "adapter roundtrips all methods"
            `Quick
            test_adapter_roundtrips_all_methods;
          test_case
            "status variant translation"
            `Quick
            test_status_variant_translation;
          test_case
            "fallback stub when nothing registered"
            `Quick
            test_fallback_stub_when_nothing_registered;
        ] );
    ]
