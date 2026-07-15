open Alcotest
module QR = Miaou_widgets_display.Qr_code_widget

let test_create_succeeds_for_simple_data () =
  match QR.create ~data:"hello" () with
  | Ok qr -> check string "get_data roundtrips" "hello" (QR.get_data qr)
  | Error msg -> fail (Printf.sprintf "expected Ok, got Error %s" msg)

let test_dimensions_are_positive_and_square () =
  match QR.create ~data:"https://example.com" () with
  | Ok qr ->
      let w, h = QR.get_dimensions qr in
      check bool "width is positive" true (w > 0) ;
      check bool "QR modules form a square grid" true (w = h)
  | Error msg -> fail msg

let test_get_module_out_of_bounds_raises () =
  match QR.create ~data:"x" () with
  | Ok qr ->
      let w, _ = QR.get_dimensions qr in
      check
        bool
        "out-of-bounds get_module raises Invalid_argument"
        true
        (try
           ignore (QR.get_module qr ~x:(w + 100) ~y:0) ;
           false
         with Invalid_argument _ -> true)
  | Error msg -> fail msg

let test_update_data_changes_content () =
  match QR.create ~data:"first" () with
  | Ok qr -> (
      match QR.update_data qr ~data:"second" with
      | Ok qr' ->
          check
            string
            "update_data replaces the encoded data"
            "second"
            (QR.get_data qr')
      | Error msg -> fail msg)
  | Error msg -> fail msg

let test_render_produces_nonempty_multiline_output () =
  match QR.create ~data:"render me" () with
  | Ok qr ->
      let out = QR.render qr ~focus:false in
      check bool "render is non-empty" true (String.length out > 0) ;
      check
        bool
        "render spans multiple lines"
        true
        (Test_helpers.contains_substring out "\n")
  | Error msg -> fail msg

let test_scale_increases_rendered_size () =
  match
    ( QR.create ~data:"scale test" ~scale:1 (),
      QR.create ~data:"scale test" ~scale:2 () )
  with
  | Ok qr1, Ok qr2 ->
      let out1 = QR.render qr1 ~focus:false in
      let out2 = QR.render qr2 ~focus:false in
      check
        bool
        "scale:2 output is larger than scale:1"
        true
        (String.length out2 > String.length out1)
  | Error m, _ | _, Error m -> fail m

let () =
  run
    "qr_code_widget"
    [
      ( "qr_code_widget",
        [
          test_case
            "create succeeds for simple data"
            `Quick
            test_create_succeeds_for_simple_data;
          test_case
            "dimensions are positive and square"
            `Quick
            test_dimensions_are_positive_and_square;
          test_case
            "get_module out of bounds raises"
            `Quick
            test_get_module_out_of_bounds_raises;
          test_case
            "update_data changes content"
            `Quick
            test_update_data_changes_content;
          test_case
            "render produces non-empty multiline output"
            `Quick
            test_render_produces_nonempty_multiline_output;
          test_case
            "scale increases rendered size"
            `Quick
            test_scale_increases_rendered_size;
        ] );
    ]
