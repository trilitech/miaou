let () =
  let open Miaou_widgets_input.Textbox_widget in
  let w0 = open_centered ~initial:"hello" () in
  let w1 = handle_key w0 ~key:"Left" in
  let w2 = handle_key w1 ~key:"Left" in
  let w3 = handle_key w2 ~key:"X" in
  let w4 = handle_key w3 ~key:"End" in
  let w5 = handle_key w4 ~key:"Delete" in
  let w6 = handle_key w5 ~key:"Esc" in
  if not (is_cancelled w6) then (
    Printf.eprintf "Expected cancelled\n" ;
    exit 2) ;
  let s = get_text w6 in
  if s <> "helXlo" then (
    Printf.eprintf "Unexpected content: %S\n" s ;
    exit 3) ;
  print_endline "OK"
