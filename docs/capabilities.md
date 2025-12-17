# MIAOU Capabilities Guide

Capabilities are MIAOU's dependency injection system. They allow you to decouple your application logic from concrete implementations, making code testable and modular.

## Overview

A **capability** is a typed service that can be registered at runtime and accessed globally. This pattern enables:

- **Testability** - Swap real implementations for mocks in tests
- **Modularity** - Different parts of your app can provide different implementations
- **Configuration** - Change behavior without modifying code

## Basic Usage

### Defining a Capability

```ocaml
(* my_service.ml *)
module Capability = Miaou.Core.Capability

(* Define the interface *)
type t = {
  do_something : string -> int;
  get_status : unit -> string;
}

(* Create a unique key for this capability *)
let key : t Capability.key = Capability.create ~name:"MyService"

(* Convenience functions *)
let set v = Capability.set key v
let get () = Capability.get key
let require () = Capability.require key
```

### Registering an Implementation

```ocaml
(* In your application startup *)
let real_service = {
  My_service.do_something = (fun s -> String.length s);
  get_status = (fun () -> "running");
}

My_service.set real_service
```

### Using a Capability

```ocaml
(* Option 1: Safe access (returns option) *)
match My_service.get () with
| Some svc -> svc.do_something "hello"
| None -> (* handle missing capability *)

(* Option 2: Required access (raises if missing) *)
let svc = My_service.require () in
svc.do_something "hello"
```

## Built-in Capabilities

MIAOU provides several built-in capabilities:

### System (`Miaou_interfaces.System`)

File system and process operations:

```ocaml
type t = {
  file_exists : string -> bool;
  is_directory : string -> bool;
  read_file : string -> (string, string) result;
  write_file : string -> string -> (unit, string) result;
  mkdir : string -> (unit, string) result;
  run_command : argv:string list -> cwd:string option -> (run_result, string) result;
  get_current_user_info : unit -> (string * string, string) result;
  get_disk_usage : path:string -> (int64, string) result;
  list_dir : string -> (string list, string) result;
  probe_writable : path:string -> (bool, string) result;
  get_env_var : string -> string option;
}
```

**Usage:**
```ocaml
let sys = Miaou_interfaces.System.require () in
match sys.read_file "/etc/hosts" with
| Ok contents -> (* use contents *)
| Error msg -> (* handle error *)
```

### Logger (`Miaou_interfaces.Logger_capability`)

Application logging:

```ocaml
type level = Debug | Info | Warning | Error

type t = {
  logf : level -> string -> unit;
  set_enabled : bool -> unit;
  set_logfile : string option -> (unit, string) result;
}
```

**Usage:**
```ocaml
match Miaou_interfaces.Logger_capability.get () with
| Some logger ->
    logger.logf Info "Application started";
    logger.logf Error "Something went wrong"
| None -> ()
```

### Service Lifecycle (`Miaou_interfaces.Service_lifecycle`)

Background service management:

```ocaml
type status = Stopped | Starting | Running | Stopping | Failed of string

type t = {
  start : string -> (unit, string) result;
  stop : string -> (unit, string) result;
  status : string -> status;
  list_services : unit -> string list;
}
```

**Usage:**
```ocaml
let lifecycle = Miaou_interfaces.Service_lifecycle.require () in
match lifecycle.status "my-service" with
| Running -> (* service is running *)
| Stopped -> lifecycle.start "my-service" |> ignore
| Failed msg -> (* handle failure *)
| _ -> ()
```

## Creating Mock Implementations

For testing, create mock implementations that simulate behavior:

```ocaml
(* mock_my_service.ml *)
let call_count = ref 0

let mock_impl = {
  My_service.do_something = (fun s ->
    incr call_count;
    String.length s
  );
  get_status = (fun () -> "mock");
}

let register () =
  call_count := 0;  (* Reset between tests *)
  My_service.set mock_impl

let get_call_count () = !call_count
```

See `example/shared/mock_*.ml` for complete examples:

- `mock_system.ml` - File system mock with in-memory storage
- `mock_service_lifecycle.ml` - Service lifecycle mock
- `mock_logger.ml` - Logger mock

## Checking Capabilities

### Check if Registered

```ocaml
if Capability.mem My_service.key then
  (* capability is available *)
```

### List All Capabilities

```ocaml
let caps = Capability.list () in
List.iter (fun (name, registered) ->
  Printf.printf "%s: %s\n" name (if registered then "yes" else "no")
) caps
```

### Check Multiple at Once

```ocaml
let missing = Capability.check_all [
  Capability.any My_service.key;
  Capability.any Other_service.key;
] in
match missing with
| [] -> (* all present *)
| names -> (* some missing *)
    failwith ("Missing capabilities: " ^ String.concat ", " names)
```

## Best Practices

### 1. Define Capabilities in Interface Modules

Keep capability definitions in dedicated interface modules:

```
src/
  my_app_interfaces/
    my_service.ml      (* Type + key + get/set/require *)
  my_app_impl/
    my_service_impl.ml (* Real implementation *)
  my_app_test/
    mock_my_service.ml (* Mock implementation *)
```

### 2. Register Early

Register capabilities during application startup, before any code that might use them:

```ocaml
let () =
  Eio_main.run @@ fun env ->
  Eio.Switch.run @@ fun sw ->

  (* Initialize runtime first *)
  Miaou_helpers.Fiber_runtime.init ~env ~sw;

  (* Register capabilities *)
  My_service.set real_implementation;
  Other_service.set other_implementation;

  (* Now run the application *)
  let page = (module Main_page : PAGE_SIG) in
  ignore (Runner.run page)
```

### 3. Use `require` for Critical Dependencies

Use `require` when the capability is essential:

```ocaml
(* This will fail fast with a clear error if System is not registered *)
let sys = Miaou_interfaces.System.require () in
```

### 4. Use `get` for Optional Features

Use `get` when the feature is optional:

```ocaml
(* Logging is nice but not critical *)
match Logger_capability.get () with
| Some logger -> logger.logf Info msg
| None -> () (* silently skip *)
```

### 5. Clear State in Tests

Reset capability state between tests:

```ocaml
let setup_test () =
  Capability.clear ();  (* Remove all capabilities *)
  Mock_system.register ();
  Mock_logger.register ()
```

### 6. Use Records for Rich Interfaces

Capabilities work best as records of functions:

```ocaml
(* Good: Record of functions *)
type t = {
  operation_a : int -> string;
  operation_b : string -> bool;
}

(* Avoid: Single function *)
type t = int -> string  (* Less extensible *)
```

## Advanced Patterns

### Composition

Combine capabilities into higher-level services:

```ocaml
type app_context = {
  sys : Miaou_interfaces.System.t;
  logger : Miaou_interfaces.Logger_capability.t option;
}

let make_context () = {
  sys = Miaou_interfaces.System.require ();
  logger = Miaou_interfaces.Logger_capability.get ();
}
```

### Lazy Initialization

For expensive capabilities, initialize lazily:

```ocaml
let expensive_service = lazy (
  (* Only computed once, on first access *)
  let data = load_large_dataset () in
  { process = (fun x -> transform data x) }
)

let get_expensive () =
  Lazy.force expensive_service
```

### Environment-based Configuration

Use environment variables to select implementations:

```ocaml
let register_logger () =
  let impl = match Sys.getenv_opt "LOG_BACKEND" with
    | Some "file" -> File_logger.create ()
    | Some "syslog" -> Syslog_logger.create ()
    | _ -> Console_logger.create ()
  in
  Logger_capability.set impl
```

## See Also

- [Architecture Overview](architecture.md) - How capabilities fit into MIAOU
- [Getting Started](getting-started.md) - Using capabilities in your app
- [Example Mocks](../example/shared/) - Mock implementations
