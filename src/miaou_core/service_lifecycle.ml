(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)
(* (c) 2025 Nomadic Labs <contact@nomadic-labs.com> *)

[@@@warning "-32-34-37-69"]

[@@@warning "-32-34-37-69"]

type status = Running | Stopped | Failed of string

type t = {
  start : role:string -> service:string -> (unit, string) result;
  stop : role:string -> service:string -> (unit, string) result;
  restart : role:string -> service:string -> (unit, string) result;
  get_status : role:string -> service:string -> (status, string) result;
  install_unit :
    role:string ->
    app_bin_dir:string option ->
    user:string ->
    (unit, string) result;
  write_dropin_node :
    inst:string ->
    data_dir:string ->
    app_bin_dir:string option ->
    (unit, string) result;
  enable_start : role:string -> inst:string -> (unit, string) result;
  enable : role:string -> inst:string -> (unit, string) result;
  disable : role:string -> inst:string -> (unit, string) result;
  remove_instance_files :
    role:string -> inst:string -> remove_data:bool -> (unit, string) result;
}

module Capability = Miaou_interfaces.Capability
module Iface = Miaou_interfaces.Service_lifecycle

(* This module's [t] and the interface's [Iface.t] are NOT the same runtime
   representation: [Iface.status] is a polymorphic variant
   ([`Active | `Inactive | `Failed of string]) versus this module's regular
   variant ([Running | Stopped | Failed of string]), and
   [Iface.remove_instance_files] takes no [~role] while this module's does.
   The previous implementation shared one capability key across both types
   via [Obj.magic] and, on the interface fallback path, additionally
   [Obj.magic]-cast an [Iface.t] value directly into this module's [t] —
   an unsound coercion between records of differently-shaped closures:
   calling the miscast [remove_instance_files] or [get_status] with this
   module's arity/return-type expectations reads/calls through the wrong
   closure layout (arity mismatch — segfault-class, not merely a type
   error caught by the compiler).

   Fixed with an explicit, signature-preserving adapter: this module keeps
   its own independent capability key (so its public [key]/[set]/[get]/
   [require] signatures are unchanged for existing callers), and
   [of_interface] below builds a proper [t] value from an [Iface.t] by
   translating each field explicitly instead of reinterpreting bytes. *)
let key : t Capability.key = Capability.create ~name:"service_lifecycle"

let set v = Capability.set key v

let status_of_interface : Iface.service_status -> status = function
  | `Active -> Running
  | `Inactive -> Stopped
  | `Failed msg -> Failed msg

(* Adapt an interface-level implementation into this module's [t] shape.
   [remove_instance_files] has no [~role] on the interface side; the role
   passed here is accepted (to match this module's signature) and simply
   not forwarded, matching the interface's role-agnostic semantics. *)
let of_interface (iv : Iface.t) : t =
  {
    start = (fun ~role ~service -> Iface.start iv ~role ~service);
    stop = (fun ~role ~service -> Iface.stop iv ~role ~service);
    restart = (fun ~role ~service -> Iface.restart iv ~role ~service);
    get_status =
      (fun ~role ~service ->
        match Iface.get_status iv ~role ~service with
        | Ok s -> Ok (status_of_interface s)
        | Error e -> Error e);
    install_unit =
      (fun ~role ~app_bin_dir ~user ->
        Iface.install_unit iv ~role ~app_bin_dir ~user);
    write_dropin_node =
      (fun ~inst ~data_dir ~app_bin_dir ->
        Iface.write_dropin_node iv ~inst ~data_dir ~app_bin_dir);
    enable_start = (fun ~role ~inst -> Iface.enable_start iv ~role ~inst);
    enable = (fun ~role ~inst -> Iface.enable iv ~role ~inst);
    disable = (fun ~role ~inst -> Iface.disable iv ~role ~inst);
    remove_instance_files =
      (fun ~role:_ ~inst ~remove_data ->
        Iface.remove_instance_files iv ~inst ~remove_data);
  }

let get () =
  match Capability.get key with
  | Some v -> Some v
  | None -> (
      (* If another module registered only the interface-level capability
         (e.g. a Systemd-backed implementation registering via
         [Iface.register]), adapt it into this module's [t] rather than
         reinterpreting its bytes. This covers registration-ordering races
         where the interface registration may be visible via the interface
         module but not via this module's local key instance. *)
      match Iface.get () with
      | Some iv -> Some (of_interface iv)
      | None -> None)

let require () =
  match get () with
  | Some v -> v
  | None ->
      (* Register a fallback stub that returns Errors. *)
      let start ~role:_ ~service:_ = Error "service lifecycle not available" in
      let stop ~role:_ ~service:_ = Error "service lifecycle not available" in
      let restart ~role:_ ~service:_ =
        Error "service lifecycle not available"
      in
      let get_status ~role:_ ~service:_ =
        Error "service lifecycle not available"
      in
      let install_unit ~role:_ ~app_bin_dir:_ ~user:_ =
        Error "service lifecycle not available"
      in
      let write_dropin_node ~inst:_ ~data_dir:_ ~app_bin_dir:_ =
        Error "service lifecycle not available"
      in
      let enable_start ~role:_ ~inst:_ =
        Error "service lifecycle not available"
      in
      let enable ~role:_ ~inst:_ = Error "service lifecycle not available" in
      let disable ~role:_ ~inst:_ = Error "service lifecycle not available" in
      let remove_instance_files ~role:_ ~inst:_ ~remove_data:_ =
        Error "service lifecycle not available"
      in
      let stub =
        {
          start;
          stop;
          restart;
          get_status;
          install_unit;
          write_dropin_node;
          enable_start;
          enable;
          disable;
          remove_instance_files;
        }
      in
      (* Do NOT persistently register the stub; return it transiently so a
         later real registration (e.g., Systemd_service_lifecycle.register)
         can still override and be observed via the interface key. *)
      stub

let install_unit v ~role ~app_bin_dir ~user =
  v.install_unit ~role ~app_bin_dir ~user

let write_dropin_node v ~inst ~data_dir ~app_bin_dir =
  v.write_dropin_node ~inst ~data_dir ~app_bin_dir

let enable_start v ~role ~inst = v.enable_start ~role ~inst

let enable v ~role ~inst = v.enable ~role ~inst

let disable v ~role ~inst = v.disable ~role ~inst

let start v ~role ~service = v.start ~role ~service

let stop v ~role ~service = v.stop ~role ~service

let restart v ~role ~service = v.restart ~role ~service

let get_status v ~role ~service = v.get_status ~role ~service

let remove_instance_files v ~role ~inst ~remove_data =
  v.remove_instance_files ~role ~inst ~remove_data
