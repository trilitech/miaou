open Alcotest
module Flex = Miaou_widgets_layout.Flex_layout

let size cols rows = {LTerm_geom.cols; rows}

let render_child label =
  {Flex.render = (fun ~size:_ -> label); basis = Flex.Auto; cross = None}

let leading_spaces s =
  let rec aux i =
    if i >= String.length s then i else if s.[i] = ' ' then aux (i + 1) else i
  in
  aux 0

let trailing_spaces s =
  let rec aux i =
    if i < 0 then String.length s
    else if s.[i] = ' ' then aux (i - 1)
    else String.length s - i - 1
  in
  aux (String.length s - 1)

let count_char s ch =
  String.fold_left (fun acc c -> if Char.equal c ch then acc + 1 else acc) 0 s

let test_row_layout () =
  let flex =
    Flex.create
      ~direction:Flex.Row
      ~gap:{h = 1; v = 0}
      ~padding:{left = 1; right = 1; top = 0; bottom = 0}
      [render_child "A"; render_child "BB"; render_child "CCC"]
  in
  let out = Flex.render flex ~size:(size 20 1) in
  (* Expect padding + children separated by single space gap. *)
  check bool "has padding" true (String.get out 0 = ' ') ;
  check
    bool
    "contains sequence"
    true
    (String.contains out 'A' && String.contains out 'B'
   && String.contains out 'C')

let test_column_layout () =
  let flex =
    Flex.create
      ~direction:Flex.Column
      ~gap:{h = 0; v = 1}
      ~padding:{left = 0; right = 0; top = 0; bottom = 0}
      [render_child "X"; render_child "Y"; render_child "Z"]
  in
  let out = Flex.render flex ~size:(size 5 5) in
  let lines = String.split_on_char '\n' out in
  check int "line count" 5 (List.length lines)

let test_justify_center () =
  let flex =
    Flex.create
      ~direction:Flex.Row
      ~justify:Flex.Center
      ~gap:{h = 1; v = 0}
      ~padding:{left = 0; right = 0; top = 0; bottom = 0}
      [
        {render = (fun ~size:_ -> "A"); basis = Flex.Px 1; cross = None};
        {render = (fun ~size:_ -> "B"); basis = Flex.Px 1; cross = None};
      ]
  in
  let out = Flex.render flex ~size:(size 10 1) in
  let lead = leading_spaces out in
  let trail = trailing_spaces out in
  check bool "balanced margins" true (abs (lead - trail) <= 1)

let test_align_center_column () =
  let flex =
    Flex.create
      ~direction:Flex.Column
      ~align_items:Flex.Center
      [render_child "X"; render_child "Y"]
  in
  let out = Flex.render flex ~size:(size 6 4) in
  let lines = String.split_on_char '\n' out in
  lines
  |> List.filter (fun l -> String.exists (fun c -> c = 'X' || c = 'Y') l)
  |> List.iter (fun line ->
      let lead = leading_spaces line in
      let trail = trailing_spaces line in
      check bool "centered" true (abs (lead - trail) <= 1))

let test_percent_ratio_allocation () =
  let make_child ch basis =
    {
      Flex.render = (fun ~size -> String.make size.LTerm_geom.cols ch);
      basis;
      cross = None;
    }
  in
  let flex =
    Flex.create
      ~direction:Flex.Row
      ~gap:{h = 1; v = 0}
      [
        make_child 'A' (Flex.Px 4);
        make_child 'B' (Flex.Percent 50.);
        make_child 'C' (Flex.Ratio 1.);
      ]
  in
  let out = Flex.render flex ~size:(size 30 1) in
  check int "total length" 30 (String.length out) ;
  check int "px child" 4 (count_char out 'A') ;
  check int "percent child" 14 (count_char out 'B') ;
  check int "ratio child" 10 (count_char out 'C')

let test_min_constraint () =
  let make_child ch basis =
    {
      Flex.render = (fun ~size -> String.make size.LTerm_geom.cols ch);
      basis;
      cross = None;
    }
  in
  let flex =
    Flex.create
      ~direction:Flex.Row
      ~constraints:[{Flex.index = 0; min_size = Some 8; max_size = None}]
      [make_child 'A' (Flex.Px 3); make_child 'B' Flex.Fill]
  in
  let out = Flex.render flex ~size:(size 20 1) in
  check bool "min constraint applied" true (count_char out 'A' >= 8)

let test_max_constraint () =
  let make_child ch basis =
    {
      Flex.render = (fun ~size -> String.make size.LTerm_geom.cols ch);
      basis;
      cross = None;
    }
  in
  let flex =
    Flex.create
      ~direction:Flex.Row
      ~constraints:[{Flex.index = 0; min_size = None; max_size = Some 5}]
      [make_child 'A' Flex.Fill; make_child 'B' Flex.Fill]
  in
  let out = Flex.render flex ~size:(size 20 1) in
  check bool "max constraint applied" true (count_char out 'A' <= 5)

let test_no_constraints_unchanged () =
  let make_child ch basis =
    {
      Flex.render = (fun ~size -> String.make size.LTerm_geom.cols ch);
      basis;
      cross = None;
    }
  in
  let flex =
    Flex.create
      ~direction:Flex.Row
      [make_child 'A' Flex.Fill; make_child 'B' Flex.Fill]
  in
  let out = Flex.render flex ~size:(size 20 1) in
  check int "A fills half" 10 (count_char out 'A') ;
  check int "B fills half" 10 (count_char out 'B')

let () =
  run
    "flex_layout"
    [
      ( "flex_layout",
        [
          test_case "row layout" `Quick test_row_layout;
          test_case "column layout" `Quick test_column_layout;
          test_case "justify center" `Quick test_justify_center;
          test_case "align center column" `Quick test_align_center_column;
          test_case "percent + ratio alloc" `Quick test_percent_ratio_allocation;
          test_case "min constraint" `Quick test_min_constraint;
          test_case "max constraint" `Quick test_max_constraint;
          test_case
            "no constraints unchanged"
            `Quick
            test_no_constraints_unchanged;
        ] );
    ]
