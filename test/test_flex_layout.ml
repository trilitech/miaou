open Alcotest

module Flex = Miaou_widgets_layout.Flex_layout

let size cols rows = {LTerm_geom.cols; rows}

let render_child label =
  {Flex.render = (fun ~size:_ -> label); basis = Flex.Auto; cross = None}

let test_row_layout () =
  let flex =
    Flex.create ~direction:Flex.Row
      ~gap:{h = 1; v = 0}
      ~padding:{left = 1; right = 1; top = 0; bottom = 0}
      [render_child "A"; render_child "BB"; render_child "CCC"]
  in
  let out = Flex.render flex ~size:(size 20 1) in
  (* Expect padding + children separated by single space gap. *)
  check bool "has padding" true (String.get out 0 = ' ') ;
  check bool "contains sequence"
    true
    (String.contains out 'A' && String.contains out 'B' && String.contains out 'C')

let test_column_layout () =
  let flex =
    Flex.create ~direction:Flex.Column
      ~gap:{h = 0; v = 1}
      ~padding:{left = 0; right = 0; top = 0; bottom = 0}
      [render_child "X"; render_child "Y"; render_child "Z"]
  in
  let out = Flex.render flex ~size:(size 5 5) in
  let lines = String.split_on_char '\n' out in
  check int "line count" 3 (List.length (List.filter (fun l -> l <> "") lines))

let () =
  run
    "flex_layout"
    [
      ( "flex_layout",
        [ test_case "row layout" `Quick test_row_layout;
          test_case "column layout" `Quick test_column_layout ] );
    ]
