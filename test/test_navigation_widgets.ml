open Alcotest
module Tabs = Miaou_widgets_navigation.Tabs_widget

let sample_tabs =
  [
    Tabs.tab ~id:"home" ~label:"Home";
    Tabs.tab ~id:"logs" ~label:"Logs";
    Tabs.tab ~id:"settings" ~label:"Settings";
  ]

let test_move_wraps () =
  let t = Tabs.make sample_tabs in
  let left_once = Tabs.move t `Left in
  check
    (option string)
    "wrap left"
    (Some "settings")
    (Tabs.current left_once |> Option.map Tabs.id) ;
  let right = Tabs.move left_once `Right in
  check
    (option string)
    "right moves forward"
    (Some "home")
    (Tabs.current right |> Option.map Tabs.id)

let test_handle_keys () =
  let t = Tabs.make sample_tabs in
  let end_sel = Tabs.handle_key t ~key:"End" in
  check
    (option string)
    "End selects last"
    (Some "settings")
    (Tabs.current end_sel
    |> Option.map (fun t -> Tabs.id t |> String.lowercase_ascii)) ;
  let home_sel = Tabs.handle_key end_sel ~key:"Home" in
  check
    (option string)
    "Home selects first"
    (Some "home")
    (Tabs.current home_sel |> Option.map Tabs.id)

let test_render_marks_selection () =
  let t = Tabs.make sample_tabs in
  let rendered = Tabs.render t ~focus:true in
  check bool "selected label present" true (String.contains rendered 'H') ;
  check bool "separator present" true (String.contains rendered '|')

let () =
  run
    "navigation_widgets"
    [
      ( "tabs",
        [
          test_case "wrap and move" `Quick test_move_wraps;
          test_case "handle keys" `Quick test_handle_keys;
          test_case
            "render highlights selection"
            `Quick
            test_render_marks_selection;
        ] );
    ]
