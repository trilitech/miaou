open Alcotest
module R = Miaou_widgets_layout.Responsive

let bps =
  [
    {R.max_width = 40; layout = "narrow"};
    {R.max_width = 80; layout = "medium"};
    {R.max_width = 120; layout = "wide"};
  ]

let test_narrow () =
  check
    string
    "width 30 picks narrow"
    "narrow"
    (R.pick bps ~default:"xl" ~width:30)

let test_medium () =
  check
    string
    "width 60 picks medium"
    "medium"
    (R.pick bps ~default:"xl" ~width:60)

let test_wide () =
  check
    string
    "width 100 picks wide"
    "wide"
    (R.pick bps ~default:"xl" ~width:100)

let test_overflow () =
  check
    string
    "width 200 falls through to default"
    "xl"
    (R.pick bps ~default:"xl" ~width:200)

let test_exact_boundary () =
  check
    string
    "width 40 hits narrow (inclusive)"
    "narrow"
    (R.pick bps ~default:"xl" ~width:40) ;
  check
    string
    "width 41 falls into medium"
    "medium"
    (R.pick bps ~default:"xl" ~width:41)

let test_empty () =
  check
    string
    "no breakpoints returns default"
    "xl"
    (R.pick [] ~default:"xl" ~width:100)

let () =
  run
    "responsive"
    [
      ( "pick",
        [
          test_case "narrow" `Quick test_narrow;
          test_case "medium" `Quick test_medium;
          test_case "wide" `Quick test_wide;
          test_case "overflow falls through" `Quick test_overflow;
          test_case "exact boundary inclusive" `Quick test_exact_boundary;
          test_case "empty list returns default" `Quick test_empty;
        ] );
    ]
