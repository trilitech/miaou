(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(* Demo entrypoint for terminal-only (lambda-term) rendering.                *)
(*                                                                           *)
(*****************************************************************************)

let bench_target = ref None

let bench_count = ref 10

let usage = "demo_tui [--bench=name|all] [--count=N]"

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
  Demo_lib.register_all () ;
  Demo_lib.ensure_system_capability () ;
  Demo_lib.register_page () ;
  match !bench_target with
  | Some target ->
      Demo_lib.run_bench ~target ~count:!bench_count ;
      exit 0
  | None ->
      let page_name = Demo_lib.launcher_page_name in
      let page =
        match Miaou_core.Registry.find page_name with
        | Some p -> p
        | None -> failwith ("Demo page not registered: " ^ page_name)
      in
      ignore (Miaou_runner_tui.Runner_tui.run page)
