let test_runtime_version () =
  Alcotest.(check string) "version" "0.5.1" Miaou_core.Version.version ;
  Alcotest.(check int) "major" 0 Miaou_core.Version.major ;
  Alcotest.(check int) "minor" 5 Miaou_core.Version.minor ;
  Alcotest.(check int) "patch" 1 Miaou_core.Version.patch

let test_runner_cli_uses_given_argv () =
  let opts =
    Miaou_runner_common.Runner_cli.parse
      ~argv:
        [|
          "miaou-runner-tui";
          "--page";
          "demo";
          "--cli-output";
          "--cols";
          "120";
          "--rows";
          "40";
          "--ticks";
          "3";
        |]
  in
  Alcotest.(check string) "page" "demo" opts.page_name ;
  Alcotest.(check bool) "cli output" true opts.cli_output ;
  Alcotest.(check int) "cols" 120 opts.cols ;
  Alcotest.(check int) "rows" 40 opts.rows ;
  Alcotest.(check int) "ticks" 3 opts.ticks

let () =
  Alcotest.run
    "version"
    [
      ( "runtime",
        [
          Alcotest.test_case "version constants" `Quick test_runtime_version;
          Alcotest.test_case
            "runner cli uses supplied argv"
            `Quick
            test_runner_cli_uses_given_argv;
        ] );
    ]
