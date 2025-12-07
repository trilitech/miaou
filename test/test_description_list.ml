open Alcotest
module DL = Miaou_widgets_display.Description_list

let test_wrap () =
  let widget =
    DL.create
      ~items:[("Name", "Alice Wonderland Wonderland"); ("Role", "Engineer")]
      ()
  in
  let rendered = DL.render ~cols:20 ~wrap:true widget ~focus:false in
  let lines = String.split_on_char '\n' rendered in
  check bool "wrapped line present"
    true
    (List.exists (fun l -> String.trim l = "Wonderland") lines)

let () = run "description_list" [("wrap", [test_case "wrap" `Quick test_wrap])]
