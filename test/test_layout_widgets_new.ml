open Alcotest

let test_card_render () =
  let card =
    Miaou_widgets_layout.Card_widget.create
      ~title:"Card title"
      ~footer:"Footer"
      ~accent:81
      ~body:"Body"
      ()
  in
  let rendered = Miaou_widgets_layout.Card_widget.render card ~cols:40 in
  check bool "title present" true (String.contains rendered 'C') ;
  check bool "body present" true (String.contains rendered 'B') ;
  check bool "footer present" true (String.contains rendered 'F')

let contains_sub str sub =
  let sub_len = String.length sub in
  let rec loop i =
    if i + sub_len > String.length str then false
    else if String.sub str i sub_len = sub then true
    else loop (i + 1)
  in
  loop 0

let test_sidebar_toggle () =
  let layout =
    Miaou_widgets_layout.Sidebar_widget.create
      ~sidebar:"NAV"
      ~main:"MAIN"
      ~sidebar_open:true
      ()
  in
  let open_render = Miaou_widgets_layout.Sidebar_widget.render layout ~cols:80 in
  check bool "sidebar visible" true (contains_sub open_render "NAV") ;
  let closed =
    layout |> Miaou_widgets_layout.Sidebar_widget.toggle |> fun t ->
    Miaou_widgets_layout.Sidebar_widget.render t ~cols:80
  in
  check bool "sidebar hidden" false (contains_sub closed "NAV") ;
  check bool "main visible" true (contains_sub closed "MAIN")

let () =
  run
    "layout_widgets_new"
    [
      ( "layout_widgets_new",
        [ test_case "card render" `Quick test_card_render;
          test_case "sidebar toggle" `Quick test_sidebar_toggle ] );
    ]
