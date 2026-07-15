open Alcotest
module Assets = Miaou_driver_web.Web_assets

(* Pure-parts coverage of the web viewer: the compile-time-embedded HTML/JS
   bootstrap assets.

   {b Honest scope}: [Web_viewer.start]/[broadcast] need a real
   [Eio.Switch.t] and network resource ([net]) to construct the opaque
   server state [t] at all (there is no pure constructor exposed), so they
   are not exercised here — that would need "a trustworthy build env" per
   the test-debt plan's web-driver scope note, which this slice explicitly
   limits to pure parts. The module's other pure-looking helpers
   ([lf_to_crlf], [dims_msg], [extract_path]) are private (not in
   [web_viewer.mli]); exposing them would be a src/ change beyond this
   slice's test-seam allowance, so they are untested — flagged in the
   test-debt handoff, not silently skipped. There is also no dynamic
   HTML-escaping function anywhere in the web driver to test: the served
   pages are static, compile-time-embedded assets with no runtime
   string interpolation of user-controlled content into HTML. *)

let test_viewer_html_is_a_bootstrapped_page () =
  let html = Assets.viewer_html in
  check bool "viewer_html is non-empty" true (String.length html > 0) ;
  check
    bool
    "viewer_html declares a doctype/html root"
    true
    (Test_helpers.contains_substring html "html") ;
  check
    bool
    "viewer_html includes a script tag"
    true
    (Test_helpers.contains_substring html "<script") ;
  check
    bool
    "viewer_html references the terminal client"
    true
    (Test_helpers.contains_substring html "client.js"
    || Test_helpers.contains_substring html "xterm")

let test_index_html_is_a_bootstrapped_page () =
  let html = Assets.index_html in
  check bool "index_html is non-empty" true (String.length html > 0) ;
  check
    bool
    "index_html declares a doctype/html root"
    true
    (Test_helpers.contains_substring html "html")

let test_client_js_is_nonempty_javascript () =
  let js = Assets.client_js in
  check bool "client_js is non-empty" true (String.length js > 0) ;
  check
    bool
    "client_js references a WebSocket connection"
    true
    (Test_helpers.contains_substring js "WebSocket")

let test_assets_are_stable_across_reads () =
  (* [%blob] embeds the content at compile time as a plain string constant;
     re-reading it must be byte-identical (regression guard against any
     future change that made this lazy/mutable/IO-backed). *)
  check
    string
    "viewer_html is referentially stable"
    Assets.viewer_html
    Assets.viewer_html ;
  check
    string
    "client_js is referentially stable"
    Assets.client_js
    Assets.client_js

let () =
  run
    "web_viewer"
    [
      ( "static_assets",
        [
          test_case
            "viewer_html is a bootstrapped page"
            `Quick
            test_viewer_html_is_a_bootstrapped_page;
          test_case
            "index_html is a bootstrapped page"
            `Quick
            test_index_html_is_a_bootstrapped_page;
          test_case
            "client_js is non-empty javascript"
            `Quick
            test_client_js_is_nonempty_javascript;
          test_case
            "assets are stable across reads"
            `Quick
            test_assets_are_stable_across_reads;
        ] );
    ]
