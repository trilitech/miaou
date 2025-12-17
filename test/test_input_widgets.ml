open Alcotest
module Checkbox = Miaou_widgets_input.Checkbox_widget
module Radio = Miaou_widgets_input.Radio_button_widget
module Switch = Miaou_widgets_input.Switch_widget
module Button = Miaou_widgets_input.Button_widget
module Checkbox_demo = Demo_lib.Checkbox_demo_page
module Tutorial_modal = Demo_shared.Tutorial_modal

let demo_size : LTerm_geom.size = {rows = 24; cols = 80}

let contains_substring s sub =
  let len = String.length s in
  let sub_len = String.length sub in
  let rec aux i =
    if i + sub_len > len then false
    else if String.sub s i sub_len = sub then true
    else aux (i + 1)
  in
  if sub_len = 0 then true else aux 0

let strip_ansi s =
  let len = String.length s in
  let buf = Buffer.create len in
  let rec loop i =
    if i >= len then Buffer.contents buf
    else
      match s.[i] with
      | '\027' ->
          let j = ref (i + 1) in
          if !j < len && s.[!j] = '[' then (
            incr j ;
            while !j < len && s.[!j] <> 'm' do
              incr j
            done ;
            if !j < len then loop (!j + 1) else Buffer.contents buf)
          else loop (i + 1)
      | c ->
          Buffer.add_char buf c ;
          loop (i + 1)
  in
  loop 0

let first_checkbox_marker state =
  let rendered =
    strip_ansi (Checkbox_demo.view state ~focus:true ~size:demo_size)
  in
  let line =
    match String.split_on_char '\n' rendered with
    | _title :: checkbox_line :: _ -> checkbox_line
    | _ -> ""
  in
  let idx = try String.index line '[' with Not_found -> 0 in
  if String.length line >= idx + 3 then String.sub line idx 3 else ""

let test_checkbox_disabled () =
  let cb = Checkbox.create ~checked_:false ~disabled:true () in
  let cb' = Checkbox.handle_key cb ~key:"Space" in
  check bool "unchanged when disabled" false (Checkbox.is_checked cb')

let test_checkbox_demo_enter () =
  let s0 = Checkbox_demo.init () in
  check string "initial unchecked" "[ ]" (first_checkbox_marker s0) ;
  let s1 = Checkbox_demo.enter s0 in
  check string "enter toggles on" "[X]" (first_checkbox_marker s1) ;
  let s2 = Checkbox_demo.enter s1 in
  check string "enter toggles off" "[ ]" (first_checkbox_marker s2)

let test_checkbox_demo_space () =
  let s0 = Checkbox_demo.init () in
  let s1 = Checkbox_demo.handle_key s0 " " ~size:demo_size in
  check string "space toggles on" "[X]" (first_checkbox_marker s1) ;
  let s2 = Checkbox_demo.handle_key s1 "Space" ~size:demo_size in
  check string "Space toggles off" "[ ]" (first_checkbox_marker s2)

let long_tutorial_markdown () =
  let numbered = List.init 80 (fun i -> Printf.sprintf "Line %02d" (i + 1)) in
  String.concat
    "\n"
    (("# Long tutorial\n" :: numbered)
    @ [
        "Use ↑/↓ to scroll the rest of this tutorial if your terminal height \
         is limited.";
      ])

let test_checkbox_tutorial_scroll () =
  let size = {LTerm_geom.rows = 24; cols = 80} in
  let markdown = long_tutorial_markdown () in
  Tutorial_modal.set_payload ~title:"Checkbox tutorial" ~markdown ;
  let module TM = Tutorial_modal.Page in
  let rec scroll state n =
    if n <= 0 then state else scroll (TM.handle_key state "Down" ~size) (n - 1)
  in
  let content = TM.view (scroll (TM.init ()) 200) ~focus:true ~size in
  let has_footer =
    String.split_on_char '\n' content
    |> List.exists (fun line ->
        contains_substring line "Use ↑/↓ to scroll the rest")
  in
  check bool "tutorial bottom reachable" true has_footer

let test_checkbox_tutorial_resize_scroll () =
  let markdown = long_tutorial_markdown () in
  Tutorial_modal.set_payload ~title:"Checkbox tutorial" ~markdown ;
  let module TM = Tutorial_modal.Page in
  let big = {LTerm_geom.rows = 49; cols = 80} in
  let small = {LTerm_geom.rows = 24; cols = 80} in
  let state0 = TM.init () in
  ignore (TM.view state0 ~focus:true ~size:big) ;
  let state1 = TM.handle_key state0 "G" ~size:big in
  ignore (TM.view state1 ~focus:true ~size:small) ;
  let state2 = TM.handle_key state1 "G" ~size:small in
  let content = TM.view state2 ~focus:true ~size:small in
  check
    bool
    "tutorial bottom reachable after resize"
    true
    (String.split_on_char '\n' content
    |> List.exists (fun line ->
        contains_substring line "Use ↑/↓ to scroll the rest of this tutorial"))

let test_radio_disabled () =
  let r = Radio.create ~selected:false ~disabled:true () in
  let r' = Radio.handle_key r ~key:"Enter" in
  check bool "no select when disabled" false (Radio.is_selected r')

let test_switch_disabled () =
  let sw = Switch.create ~on:false ~disabled:true () in
  let sw' = Switch.handle_key sw ~key:"Enter" in
  check bool "no toggle when disabled" false (Switch.is_on sw')

let test_button_disabled () =
  let fired = ref 0 in
  let b, pressed =
    Button.create
      ~disabled:true
      ~label:"Save"
      ~on_click:(fun () -> incr fired)
      ()
    |> fun b -> Button.handle_key b ~key:"Enter"
  in
  check bool "no fire when disabled" false pressed ;
  check int "callback untouched" 0 !fired ;
  (* ensure render still works with focus and returns dimmed string *)
  ignore (Button.render b ~focus:true)

let () =
  run
    "input_widgets"
    [
      ( "disabled",
        [
          test_case "checkbox disabled" `Quick test_checkbox_disabled;
          test_case "checkbox demo enter" `Quick test_checkbox_demo_enter;
          test_case "checkbox demo space" `Quick test_checkbox_demo_space;
          test_case
            "checkbox tutorial scroll"
            `Quick
            test_checkbox_tutorial_scroll;
          test_case
            "checkbox tutorial resize scroll"
            `Quick
            test_checkbox_tutorial_resize_scroll;
          test_case "radio disabled" `Quick test_radio_disabled;
          test_case "switch disabled" `Quick test_switch_disabled;
          test_case "button disabled" `Quick test_button_disabled;
        ] );
    ]
