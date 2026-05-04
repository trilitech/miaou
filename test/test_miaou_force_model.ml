open Alcotest
module Model = Miaou_force_demo.Model

let force_state_name = function
  | Model.Force_front -> "front"
  | Force_back -> "back"
  | Force_detached _ -> "detached"

let force_state_testable = testable Fmt.string String.equal

let check_force msg expected actual =
  check force_state_testable msg expected (force_state_name actual)

let test_flip_force_attached () =
  let s = Model.init () in
  check_force "starts front-docked" "front" s.player.force ;
  Model.flip_force s ;
  check_force "flips to back" "back" s.player.force ;
  Model.flip_force s ;
  check_force "flips back to front" "front" s.player.force

let test_flip_force_detached_noop () =
  let s = Model.init () in
  Model.toggle_force s ;
  check_force "detached after toggle" "detached" s.player.force ;
  Model.flip_force s ;
  check_force "detached remains detached" "detached" s.player.force

let () =
  run
    "miaou_force_model"
    [
      ( "force",
        [
          test_case "flip attached force" `Quick test_flip_force_attached;
          test_case
            "flip detached force is no-op"
            `Quick
            test_flip_force_detached_noop;
        ] );
    ]
