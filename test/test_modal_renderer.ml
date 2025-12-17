open Alcotest
module MR = Miaou_internals.Modal_renderer
module MS = Miaou_internals.Modal_snapshot

let test_overlay () =
  let seen = ref None in
  MS.set_provider (fun () ->
      [
        ( "Modal",
          Some 0,
          Some (MS.Fixed 10),
          true,
          fun size ->
            seen := Some size ;
            "overlay" );
      ]) ;
  let rendered = MR.render_overlay ~cols:(Some 20) ~rows:5 ~base:"base" () in
  match rendered with
  | None -> fail "expected overlay"
  | Some s -> (
      check bool "non-empty" true (String.length s > 0) ;
      match !seen with
      | None -> fail "expected modal view to be called"
      | Some size ->
          (* max_width=10 => content_width=6; rows=5 => max_height=5 => max_content_h=3 *)
          check int "content cols" 6 size.LTerm_geom.cols ;
          check int "content rows" 3 size.LTerm_geom.rows)

let test_dynamic_resize () =
  (* Test that Ratio spec produces different widths for different terminal sizes *)
  let sizes = ref [] in
  MS.set_provider (fun () ->
      [
        ( "DynamicModal",
          None, (* no left offset, centered *)
          Some (MS.Ratio 0.8), (* 80% of terminal width *)
          true,
          fun size ->
            sizes := size :: !sizes ;
            "content" );
      ]) ;
  (* First render at 100 cols *)
  let _ = MR.render_overlay ~cols:(Some 100) ~rows:20 ~base:"base" () in
  (* Second render at 200 cols *)
  let _ = MR.render_overlay ~cols:(Some 200) ~rows:20 ~base:"base" () in
  match !sizes with
  | [size200; size100] ->
      (* At 100 cols with 80% ratio: max_width=80, content_width=76 *)
      (* At 200 cols with 80% ratio: max_width=160, content_width=156 *)
      Printf.printf "size100: cols=%d rows=%d\n" size100.LTerm_geom.cols size100.LTerm_geom.rows ;
      Printf.printf "size200: cols=%d rows=%d\n" size200.LTerm_geom.cols size200.LTerm_geom.rows ;
      check bool "width increases with terminal size" true (size200.LTerm_geom.cols > size100.LTerm_geom.cols)
  | _ -> fail (Printf.sprintf "expected 2 sizes, got %d" (List.length !sizes))

let test_clamped_resize () =
  (* Test that Clamped spec respects min/max bounds *)
  let sizes = ref [] in
  MS.set_provider (fun () ->
      [
        ( "ClampedModal",
          None,
          Some (MS.Clamped {ratio = 0.8; min = 60; max = 140}),
          true,
          fun size ->
            sizes := size :: !sizes ;
            "content" );
      ]) ;
  (* At 50 cols: 80% = 40, but min=60, so clamped to 60 *)
  let _ = MR.render_overlay ~cols:(Some 50) ~rows:20 ~base:"base" () in
  (* At 100 cols: 80% = 80, within bounds *)
  let _ = MR.render_overlay ~cols:(Some 100) ~rows:20 ~base:"base" () in
  (* At 200 cols: 80% = 160, but max=140, so clamped to 140 *)
  let _ = MR.render_overlay ~cols:(Some 200) ~rows:20 ~base:"base" () in
  match !sizes with
  | [size200; size100; size50] ->
      Printf.printf "size50: cols=%d\n" size50.LTerm_geom.cols ;
      Printf.printf "size100: cols=%d\n" size100.LTerm_geom.cols ;
      Printf.printf "size200: cols=%d\n" size200.LTerm_geom.cols ;
      (* size50 should be limited by terminal width (50-4=46 usable), not the min *)
      (* size100 should be 80% = 80, content_width = 76 *)
      (* size200 should be clamped to 140, content_width = 136 *)
      check bool "medium size is larger than small" true (size100.LTerm_geom.cols > size50.LTerm_geom.cols) ;
      check bool "large size is larger than medium" true (size200.LTerm_geom.cols > size100.LTerm_geom.cols)
  | _ -> fail (Printf.sprintf "expected 3 sizes, got %d" (List.length !sizes))

let suite = [
  test_case "render overlay" `Quick test_overlay;
  test_case "dynamic resize" `Quick test_dynamic_resize;
  test_case "clamped resize" `Quick test_clamped_resize;
]

let () = run "modal_renderer" [("modal_renderer", suite)]
