open Alcotest
module Tree = Miaou_widgets_display.Tree_widget

(* Sample tree built directly for predictable paths.

   root [0]
   ├─ a   [0;0]
   │  └─ a1 [0;0;0]
   ├─ b   [0;1]
   │  └─ b1 [0;1;0]
   └─ c   [0;2] (leaf)
*)
let sample : Tree.node =
  {
    Tree.label = "root";
    children =
      [
        {label = "a"; children = [{label = "a1"; children = []}]};
        {label = "b"; children = [{label = "b1"; children = []}]};
        {label = "c"; children = []};
      ];
  }

let path_t = list int

let visible_paths t = Tree.flatten_visible t |> List.map (fun (_, p, _) -> p)

let key t k = Tree.handle_key t ~key:k

let test_initial_visible () =
  let t = Tree.open_root sample in
  check
    (list path_t)
    "only root visible after open_root"
    [[0]]
    (visible_paths t)

let test_enter_reveals_children () =
  let t = Tree.open_root sample in
  let t = key t "Enter" in
  let paths = visible_paths t in
  check
    (list path_t)
    "root expanded reveals direct children, not grandchildren"
    [[0]; [0; 0]; [0; 1]; [0; 2]]
    paths

let test_down_moves_to_first_child () =
  let t = Tree.open_root sample |> fun t -> key t "Enter" in
  let t = key t "Down" in
  check path_t "cursor on first child after Down" [0; 0] t.cursor_path

let test_up_returns_to_root () =
  let t = Tree.open_root sample in
  let t = key t "Enter" in
  let t = key t "Down" in
  let t = key t "Up" in
  check path_t "cursor back on root after Up" [0] t.cursor_path

let test_left_collapses_expanded () =
  let t = Tree.open_root sample in
  let t = key t "Enter" in
  let t = key t "Down" in
  let t = key t "Enter" in
  (* expand a *)
  check bool "a is expanded" true (Tree.is_expanded [0; 0] t) ;
  let t = key t "Left" in
  check bool "a is collapsed after Left" false (Tree.is_expanded [0; 0] t) ;
  check path_t "cursor stays on a" [0; 0] t.cursor_path

let test_right_expands_collapsed () =
  let t = Tree.open_root sample in
  let t = key t "Enter" in
  let t = key t "Down" in
  (* cursor on a, collapsed *)
  let t = key t "Right" in
  check bool "Right expands collapsed a" true (Tree.is_expanded [0; 0] t) ;
  check
    (list path_t)
    "a1 visible after expand"
    [[0]; [0; 0]; [0; 0; 0]; [0; 1]; [0; 2]]
    (visible_paths t)

let test_home_end () =
  let t = Tree.open_root sample in
  let t = key t "Enter" in
  let t = key t "End" in
  check path_t "End jumps to last visible" [0; 2] t.cursor_path ;
  let t = key t "Home" in
  check path_t "Home returns to first" [0] t.cursor_path

let test_collapse_falls_back_to_ancestor () =
  (* Manually expand root + a, place cursor on a1, then collapse a. *)
  let t = Tree.open_root sample in
  let t = key t "Enter" in
  (* expand root *)
  let t = key t "Down" in
  (* cursor on a *)
  let t = key t "Right" in
  (* expand a -> cursor still on a *)
  let t = key t "Down" in
  (* cursor on a1 [0;0;0] *)
  check path_t "cursor on a1 before collapse" [0; 0; 0] t.cursor_path ;
  let t = key t "Left" in
  (* a is not expanded (cursor is on a1, not a). Left moves cursor to parent. *)
  check path_t "Left from leaf goes to parent" [0; 0] t.cursor_path

let () =
  run
    "tree_widget"
    [
      ( "navigation",
        [
          test_case "initial visible rows" `Quick test_initial_visible;
          test_case "Enter reveals children" `Quick test_enter_reveals_children;
          test_case "Down moves to child" `Quick test_down_moves_to_first_child;
          test_case "Up returns to root" `Quick test_up_returns_to_root;
          test_case
            "Left collapses expanded"
            `Quick
            test_left_collapses_expanded;
          test_case
            "Right expands collapsed"
            `Quick
            test_right_expands_collapsed;
          test_case "Home/End jump" `Quick test_home_end;
          test_case
            "leaf Left walks up"
            `Quick
            test_collapse_falls_back_to_ancestor;
        ] );
    ]
