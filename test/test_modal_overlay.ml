open Alcotest

let test_overlay_blanks_left () =
  let open Miaou_widgets_display.Widgets in
  let base_top = "Ready to get started?" in
  let base =
    String.concat
      "\n"
      [base_top; "Second line baseline"; "Third baseline"; "Fourth baseline"]
  in
  let content = String.concat "\n" ["┌────┐"; "│help│"; "└────┘"] in
  let rendered =
    overlay ~base ~content ~top:0 ~left:8 ~canvas_h:4 ~canvas_w:40
  in
  let first_line =
    match String.split_on_char '\n' rendered with [] -> "" | l :: _ -> l
  in
  let prefix =
    if String.length first_line >= 8 then String.sub first_line 0 8
    else first_line
  in
  check string "left area cleared" "        " prefix

let test_center_modal_respects_rows () =
  let open Miaou_widgets_display.Widgets in
  let base =
    String.concat "\n" ["Header"; "Line2"; "Line3"; "Line4"; "Line5"]
  in
  let content = String.concat "\n" ["hi"; "there"] in
  let rendered =
    center_modal
      ~cols:(Some 40)
      ~rows:24
      ~title:"test"
      ~dim_background:true
      ~content
      ~base
      ()
  in
  let lines = String.split_on_char '\n' rendered in
  let contains needle haystack =
    let needle_len = String.length needle in
    let hay_len = String.length haystack in
    let rec loop i =
      if i + needle_len > hay_len then false
      else if String.sub haystack i needle_len = needle then true
      else loop (i + 1)
    in
    loop 0
  in
  let first_box_row =
    let rec find i = function
      | [] -> -1
      | l :: tl -> if contains "┌" l then i else find (i + 1) tl
    in
    find 0 lines
  in
  check bool "box centered vertically" true (first_box_row >= 6)

let () =
  run
    "modal_overlay"
    [
      ( "overlay",
        [
          test_case "blank-left" `Quick (fun _ -> test_overlay_blanks_left ());
          test_case "centered-with-rows" `Quick (fun _ ->
              test_center_modal_respects_rows ());
        ] );
    ]
