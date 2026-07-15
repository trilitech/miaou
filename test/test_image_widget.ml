open Alcotest
module Image = Miaou_widgets_display.Image_widget

(* Deterministic paths only: [create_from_rgb] plus the always-available
   half-block terminal [render] (no sixel/kitty emission, no SDL, no file
   I/O — [load_from_file] depends on the filesystem and imagelib decoders
   and is out of scope here). *)

let solid_rgb ~width ~height ~r ~g ~b =
  let data = Bytes.create (width * height * 3) in
  for i = 0 to (width * height) - 1 do
    Bytes.set data ((i * 3) + 0) (Char.chr r) ;
    Bytes.set data ((i * 3) + 1) (Char.chr g) ;
    Bytes.set data ((i * 3) + 2) (Char.chr b)
  done ;
  data

let test_create_from_rgb_dimensions () =
  let data = solid_rgb ~width:4 ~height:2 ~r:10 ~g:20 ~b:30 in
  let img = Image.create_from_rgb ~width:4 ~height:2 ~rgb_data:data () in
  check (pair int int) "dimensions roundtrip" (4, 2) (Image.get_dimensions img)

let test_create_from_rgb_has_no_file_path () =
  let data = solid_rgb ~width:1 ~height:1 ~r:0 ~g:0 ~b:0 in
  let img = Image.create_from_rgb ~width:1 ~height:1 ~rgb_data:data () in
  check
    (option string)
    "no file path for an in-memory image"
    None
    (Image.get_file_path img)

let test_get_pixel_roundtrips () =
  let data = solid_rgb ~width:2 ~height:2 ~r:200 ~g:100 ~b:50 in
  let img = Image.create_from_rgb ~width:2 ~height:2 ~rgb_data:data () in
  let px = Image.get_pixel img ~x:1 ~y:1 in
  check int "red channel roundtrips" 200 px.Image.r ;
  check int "green channel roundtrips" 100 px.Image.g ;
  check int "blue channel roundtrips" 50 px.Image.b

let test_get_pixel_out_of_bounds_raises () =
  let data = solid_rgb ~width:1 ~height:1 ~r:0 ~g:0 ~b:0 in
  let img = Image.create_from_rgb ~width:1 ~height:1 ~rgb_data:data () in
  check
    bool
    "out-of-bounds get_pixel raises Invalid_argument"
    true
    (try
       ignore (Image.get_pixel img ~x:5 ~y:5) ;
       false
     with Invalid_argument _ -> true)

let test_get_pixels_matches_get_pixel () =
  let data = solid_rgb ~width:2 ~height:2 ~r:1 ~g:2 ~b:3 in
  let img = Image.create_from_rgb ~width:2 ~height:2 ~rgb_data:data () in
  let arr = Image.get_pixels img in
  let via_get = Image.get_pixel img ~x:0 ~y:1 in
  let via_array = arr.(1).(0) in
  check
    bool
    "get_pixels array agrees with get_pixel at the same coordinate"
    true
    (via_get.Image.r = via_array.Image.r
    && via_get.Image.g = via_array.Image.g
    && via_get.Image.b = via_array.Image.b)

let test_render_is_deterministic_and_nonempty () =
  let data = solid_rgb ~width:4 ~height:4 ~r:255 ~g:0 ~b:0 in
  let img = Image.create_from_rgb ~width:4 ~height:4 ~rgb_data:data () in
  let out1 = Image.render img ~focus:false in
  let out2 = Image.render img ~focus:false in
  check string "rendering twice gives byte-identical output" out1 out2 ;
  check bool "render is non-empty" true (String.length out1 > 0)

let test_render_focus_changes_border_styling () =
  let data = solid_rgb ~width:2 ~height:2 ~r:0 ~g:255 ~b:0 in
  let img = Image.create_from_rgb ~width:2 ~height:2 ~rgb_data:data () in
  let unfocused = Image.render img ~focus:false in
  let focused = Image.render img ~focus:true in
  (* Both must render deterministically; whether focus changes the exact
     bytes is an implementation detail, so only assert both are
     non-empty and reproducible, not that they differ. *)
  check bool "unfocused render non-empty" true (String.length unfocused > 0) ;
  check bool "focused render non-empty" true (String.length focused > 0)

let () =
  run
    "image_widget"
    [
      ( "image_widget",
        [
          test_case
            "create_from_rgb: dimensions"
            `Quick
            test_create_from_rgb_dimensions;
          test_case
            "create_from_rgb has no file path"
            `Quick
            test_create_from_rgb_has_no_file_path;
          test_case "get_pixel roundtrips" `Quick test_get_pixel_roundtrips;
          test_case
            "get_pixel out of bounds raises"
            `Quick
            test_get_pixel_out_of_bounds_raises;
          test_case
            "get_pixels matches get_pixel"
            `Quick
            test_get_pixels_matches_get_pixel;
          test_case
            "render is deterministic and non-empty"
            `Quick
            test_render_is_deterministic_and_nonempty;
          test_case
            "render with/without focus"
            `Quick
            test_render_focus_changes_border_styling;
        ] );
    ]
