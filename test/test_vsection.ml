let () =
  let open Alcotest in
  let test_inner_rows_basic () =
    let size = {LTerm_geom.rows = 20; cols = 80} in
    let header = ["h1"; "h2"] in
    let footer = ["f1"] in
    let seen = ref 0 in
    let child (sz : LTerm_geom.size) =
      seen := sz.LTerm_geom.rows ;
      "child"
    in
    let _out =
      Miaou_widgets_layout.Vsection.render
        ~size
        ~header
        ~content_footer:footer
        ~child
    in
    check int "inner rows" 15 !seen
  in
  let test_inner_rows_clamp () =
    let size = {LTerm_geom.rows = 3; cols = 40} in
    let header = ["h1"; "h2"] in
    let footer = ["f1"] in
    let seen = ref 0 in
    let child (sz : LTerm_geom.size) =
      seen := sz.LTerm_geom.rows ;
      "child"
    in
    let _out =
      Miaou_widgets_layout.Vsection.render
        ~size
        ~header
        ~content_footer:footer
        ~child
    in
    check int "clamp to 1" 1 !seen
  in
  run
    "vsection"
    [
      ( "container",
        [
          test_case "inner" `Quick test_inner_rows_basic;
          test_case "clamp" `Quick test_inner_rows_clamp;
        ] );
    ]
