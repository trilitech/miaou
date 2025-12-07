open Alcotest
module Tabs = Miaou_widgets_navigation.Tabs_widget
module Breadcrumbs = Miaou_widgets_navigation.Breadcrumbs_widget
module Link = Miaou_widgets_navigation.Link_widget
module W = Miaou_widgets_display.Widgets

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

let test_tabs_snapshot () =
  let t = Tabs.make sample_tabs in
  let rendered = Tabs.render t ~focus:true in
  let expected =
    let pad s = " " ^ s ^ " " in
    String.concat (W.dim "|")
      [
        W.bold (pad "Home");
        W.dim (pad "Logs");
        W.dim (pad "Settings");
      ]
  in
  check string "tabs render with bold+dim separators" expected rendered

let test_breadcrumbs_move_and_enter () =
  let fired = ref [] in
  let mk id label =
    Breadcrumbs.crumb ~id ~label ~on_enter:(fun () -> fired := id :: !fired) ()
  in
  let crumbs = [mk "root" "Root"; mk "services" "Services"; mk "node" "Node"] in
  let b = Breadcrumbs.make crumbs in
  let b = Breadcrumbs.move b `Last in
  let _b, handled = Breadcrumbs.handle_key b ~key:"Enter" in
  check bool "handled enter" true (handled = `Handled) ;
  check (list string) "callback fired" ["node"] !fired ;
  let rendered = Breadcrumbs.render b ~focus:true in
  check bool "renders separator" true (String.contains rendered '>') ;
  check bool "highlights selection" true (String.contains rendered '\027')

let test_breadcrumbs_snapshot () =
  let mk id label = Breadcrumbs.crumb ~id ~label () in
  let crumbs = [mk "root" "Root"; mk "services" "Services"; mk "node" "Node"] in
  let b = Breadcrumbs.move (Breadcrumbs.make crumbs) `Right in
  let rendered = Breadcrumbs.render b ~focus:true in
  let expected =
    let sep = W.dim " > " in
    String.concat sep
      [
        W.dim "Root";
        W.title_highlight (W.bold "Services");
        W.dim "Node";
      ]
  in
  check string "breadcrumbs highlight focused crumb" expected rendered

let test_link_render_and_key () =
  let target = Link.Internal "home" in
  let fired = ref [] in
  let l =
    Link.create ~label:"Go" ~target ~on_navigate:(fun t -> fired := t :: !fired)
  in
  let focused = Link.render l ~focus:true in
  let unfocused = Link.render l ~focus:false in
  check bool "focused bold" true (String.contains focused '1') ;
  check bool "unfocused not bold" false (String.contains unfocused '1') ;
  let _, handled = Link.handle_key l ~key:"Enter" in
  check bool "enter handled" true handled ;
  check int "callback fired" 1 (List.length !fired)

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
          test_case "render snapshot" `Quick test_tabs_snapshot;
        ] );
      ( "breadcrumbs",
        [
          test_case "move and enter" `Quick test_breadcrumbs_move_and_enter;
          test_case "render snapshot" `Quick test_breadcrumbs_snapshot;
        ] );
      ("link", [test_case "render + key" `Quick test_link_render_and_key]);
    ]
