open Alcotest
module FI = Miaou_widgets_layout.File_icons

let test_dir_icon () =
  let icon = FI.icon_for ~name:"src" ~is_dir:true in
  check bool "dir icon non-empty" true (String.length icon > 0)

let test_parent_icon_distinct () =
  let parent = FI.icon_for ~name:".." ~is_dir:true in
  let normal = FI.icon_for ~name:"foo" ~is_dir:true in
  check bool "parent icon differs from regular dir" true (parent <> normal)

let test_known_extension_has_color () =
  match FI.color_for ~name:"main.ml" ~is_dir:false with
  | Some _ -> ()
  | None -> fail "expected a colour for .ml"

let test_unknown_extension_no_color () =
  check
    (option int)
    "unknown extension has no color"
    None
    (FI.color_for ~name:"weird.xyzzy" ~is_dir:false)

let test_directory_color () =
  match FI.color_for ~name:"src" ~is_dir:true with
  | Some _ -> ()
  | None -> fail "directories should be coloured"

let test_extension_case_insensitive () =
  let a = FI.color_for ~name:"main.ML" ~is_dir:false in
  let b = FI.color_for ~name:"main.ml" ~is_dir:false in
  check (option int) "case-insensitive lookup" b a

let test_decorate_includes_icon_and_label () =
  let s = FI.decorate ~name:"main.ml" ~is_dir:false "main.ml" in
  check
    bool
    "decorated string contains label"
    true
    (let len = String.length s in
     len > 0 && Astring.String.is_infix ~affix:"main.ml" s)

let with_env name value f =
  let old = Sys.getenv_opt name in
  (match value with
  | Some v -> Unix.putenv name v
  | None -> Unix.putenv name "") ;
  Fun.protect f ~finally:(fun () ->
      match old with
      | Some v -> Unix.putenv name v
      | None -> Unix.putenv name "")

let test_nerd_font_icons_non_empty () =
  with_env "MIAOU_NERD_FONT" (Some "1") (fun () ->
      let dir = FI.icon_for ~name:"src" ~is_dir:true in
      let file = FI.icon_for ~name:"unknown.xyzzy" ~is_dir:false in
      check bool "nerd dir icon non-empty" true (String.trim dir <> "") ;
      check bool "nerd file icon non-empty" true (String.trim file <> ""))

let () =
  run
    "file_icons"
    [
      ( "lookup",
        [
          test_case "directory icon" `Quick test_dir_icon;
          test_case "parent icon distinct" `Quick test_parent_icon_distinct;
          test_case
            "known extension has colour"
            `Quick
            test_known_extension_has_color;
          test_case
            "unknown extension has no colour"
            `Quick
            test_unknown_extension_no_color;
          test_case "directory has colour" `Quick test_directory_color;
          test_case
            "case-insensitive extension lookup"
            `Quick
            test_extension_case_insensitive;
          test_case
            "decorate includes icon and label"
            `Quick
            test_decorate_includes_icon_and_label;
          test_case
            "nerd font mode keeps icons non-empty"
            `Quick
            test_nerd_font_icons_non_empty;
        ] );
    ]
