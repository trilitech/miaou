(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(* Demo entrypoint that prefers SDL (if present) and falls back to TUI.      *)
(* Reuses the page registration from [demo.ml].                              *)
(*                                                                           *)
(*****************************************************************************)

let bench_target = ref None

let bench_count = ref 10

let usage = "demo_sdl [--bench=name|all] [--count=N]"

let args =
  [
    ("--bench", Arg.String (fun s -> bench_target := Some s), "Run a benchmark");
    ("--count", Arg.Int (fun n -> bench_count := n), "Iterations per bench");
    ( "--list-benches",
      Arg.Unit
        (fun () ->
          Demo_lib.bench_names () |> String.concat ", " |> print_endline ;
          exit 0),
      "List bench names" );
  ]

let () =
  Eio_main.run @@ fun env ->
  Eio.Switch.run @@ fun sw ->
  Miaou_helpers.Fiber_runtime.init ~env ~sw ;
  Arg.parse args (fun _ -> ()) usage ;
  (* Ensure the demo capabilities/pages are registered. *)
  Demo_lib.register_all () ;
  Demo_lib.ensure_system_capability () ;
  Demo_lib.register_page () ;
  match !bench_target with
  | Some target ->
      Demo_lib.run_bench ~target ~count:!bench_count ;
      exit 0
  | None -> (
      let page_name = Demo_lib.launcher_page_name in
      let page =
        match Miaou_core.Registry.find page_name with
        | Some p -> p
        | None -> failwith ("Demo page not registered: " ^ page_name)
      in
      match Miaou_runner_native.Runner_native.run page with
      | `Quit | `SwitchTo _ -> ())
