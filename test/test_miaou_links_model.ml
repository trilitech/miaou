open Alcotest
module Model = Miaou_links_demo.Model

let with_temp_state f =
  let path = Filename.temp_file "miaou_state" "" in
  Sys.remove path ;
  Unix.mkdir path 0o700 ;
  let old = Sys.getenv_opt "XDG_STATE_HOME" in
  Unix.putenv "XDG_STATE_HOME" path ;
  Fun.protect f ~finally:(fun () ->
      match old with
      | Some v -> Unix.putenv "XDG_STATE_HOME" v
      | None -> Unix.putenv "XDG_STATE_HOME" "")

let test_spent_coins_are_persisted () =
  with_temp_state (fun () ->
      let s = Model.init () in
      check int "starts with no coins" 0 s.coins ;
      Model.add_coins s 10 ;
      check bool "spend succeeds" true (Model.spend_coins s 4) ;
      check int "in-memory balance" 6 s.coins ;
      let reloaded = Model.init () in
      check int "reloaded balance includes spend" 6 reloaded.coins)

let () =
  run
    "miaou_links_model"
    [
      ( "coins",
        [test_case "spent coins persist" `Quick test_spent_coins_are_persisted]
      );
    ]
