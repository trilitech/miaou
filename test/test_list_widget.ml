open Alcotest
module L = Miaou_widgets_display.List_widget

let items () =
  [
    L.group "Fruit" [L.item "Apple" ~id:"apple"; L.item "Banana" ~id:"banana"];
    L.item "Standalone" ~id:"standalone";
  ]

(* [create]'s default is [~expand_all:true]: everything starts open. *)
let sample () = L.create (items ())

let sample_collapsed () = L.create ~expand_all:false (items ())

let test_create_default_expands_all () =
  let t = sample () in
  check
    int
    "visible_count with the default expand_all:true"
    4
    (L.visible_count t)

let test_create_expand_all_false_starts_collapsed () =
  let t = sample_collapsed () in
  (* Top-level group + top-level item are visible; the group's children are
     collapsed. *)
  check int "visible_count with expand_all:false" 2 (L.visible_count t)

let test_expand_all_reveals_children () =
  let t = sample_collapsed () |> L.expand_all in
  check int "visible_count after expand_all" 4 (L.visible_count t)

let test_collapse_all_hides_children_again () =
  let t = sample () |> L.collapse_all in
  check int "visible_count after collapse_all" 2 (L.visible_count t)

let test_toggle_collapses_the_focused_group () =
  (* Cursor starts on the first item (the "Fruit" group, already expanded
     by the default create); toggling it collapses it back. *)
  let t = sample () in
  let t = L.toggle t in
  check
    int
    "toggling the expanded group at the cursor collapses it"
    2
    (L.visible_count t)

let test_cursor_navigation_and_selection () =
  let t = sample () in
  check int "cursor starts at 0" 0 (L.cursor_index t) ;
  let t = L.handle_key t ~key:"Down" in
  check int "Down advances the cursor" 1 (L.cursor_index t) ;
  let t = L.set_cursor_index t 2 in
  check int "set_cursor_index moves directly" 2 (L.cursor_index t) ;
  match L.selected t with
  | Some item -> check string "selected item label" "Banana" item.L.label
  | None -> fail "expected a selected item at cursor 2"

let test_selected_path_reflects_nesting () =
  let t = L.set_cursor_index (sample ()) 1 in
  match L.selected_path t with
  | Some path -> check bool "path has at least one segment" true (path <> [])
  | None -> fail "expected a selected path"

let test_set_items_replaces_content () =
  let t = sample () in
  let t = L.set_items t [L.item "Only" ~id:"only"] in
  check int "visible_count reflects the replaced items" 1 (L.visible_count t)

let test_render_contains_labels () =
  let t = sample () |> L.expand_all in
  let out = L.render t ~focus:true in
  check
    bool
    "render shows the group label"
    true
    (Test_helpers.contains_substring out "Fruit") ;
  check
    bool
    "render shows a child label once expanded"
    true
    (Test_helpers.contains_substring out "Apple") ;
  check
    bool
    "render shows the standalone item label"
    true
    (Test_helpers.contains_substring out "Standalone")

let () =
  run
    "list_widget"
    [
      ( "list_widget",
        [
          test_case
            "create defaults to expand_all:true"
            `Quick
            test_create_default_expands_all;
          test_case
            "create ~expand_all:false starts collapsed"
            `Quick
            test_create_expand_all_false_starts_collapsed;
          test_case
            "expand_all reveals children"
            `Quick
            test_expand_all_reveals_children;
          test_case
            "collapse_all hides children again"
            `Quick
            test_collapse_all_hides_children_again;
          test_case
            "toggle collapses the focused (expanded) group"
            `Quick
            test_toggle_collapses_the_focused_group;
          test_case
            "cursor navigation and selection"
            `Quick
            test_cursor_navigation_and_selection;
          test_case
            "selected_path reflects nesting"
            `Quick
            test_selected_path_reflects_nesting;
          test_case
            "set_items replaces content"
            `Quick
            test_set_items_replaces_content;
          test_case "render contains labels" `Quick test_render_contains_labels;
        ] );
    ]
