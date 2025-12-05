open Alcotest

module MR = Miaou_internals.Modal_renderer
module MS = Miaou_internals.Modal_snapshot

let test_overlay () =
  MS.set_provider (fun () ->
      [("Modal", Some 0, Some 10, true, (fun () -> "overlay"))]) ;
  let rendered = MR.render_overlay ~cols:(Some 20) ~rows:5 ~base:"base" () in
  match rendered with
  | None -> fail "expected overlay"
  | Some s -> check bool "non-empty" true (String.length s > 0)

let suite = [test_case "render overlay" `Quick test_overlay]

let () = run "modal_renderer" [("modal_renderer", suite)]
