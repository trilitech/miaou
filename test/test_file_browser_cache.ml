(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Mathias Bourgoin <mathias.bourgoin@atacama.tech>        *)
(*                                                                            *)
(******************************************************************************)

(* Regression tests for crash-ub-fixes slice S3:
   - two [File_browser_widget.t] instances browsing different paths must not
     contaminate each other's cached directory listing;
   - entry-name truncation must stay valid UTF-8 (byte-safe cut) instead of
     slicing a multi-byte codepoint in half. *)

open Alcotest
module FB = Miaou_widgets_layout.File_browser_widget

let make_stub ~listing =
  let open Miaou_interfaces in
  let run_command ~argv:_ ~cwd:_ =
    Ok System.{exit_code = 0; stdout = ""; stderr = ""}
  in
  System.
    {
      file_exists = (fun _ -> true);
      is_directory = (fun _ -> true);
      read_file = (fun _ -> Ok "");
      write_file = (fun _ _ -> Ok ());
      mkdir = (fun _ -> Ok ());
      run_command;
      get_current_user_info = (fun () -> Ok ("user", "/home/user"));
      get_disk_usage = (fun ~path:_ -> Ok 0L);
      list_dir = (fun path -> Ok (listing path));
      probe_writable = (fun ~path:_ -> Ok true);
      get_env_var = (fun _ -> None);
    }

(* A minimal UTF-8 validity check: no continuation byte (0x80-0xBF) may
   appear without a preceding, still-open lead byte. *)
let is_valid_utf8 s =
  let len = String.length s in
  let rec loop i =
    if i >= len then true
    else
      let c = Char.code s.[i] in
      if c < 0x80 then loop (i + 1)
      else
        let n_cont =
          if c land 0xE0 = 0xC0 then 1
          else if c land 0xF0 = 0xE0 then 2
          else if c land 0xF8 = 0xF0 then 3
          else -1
        in
        if n_cont < 0 || i + n_cont >= len then false
        else
          let rec check_cont k =
            k > n_cont
            ||
            let cc = Char.code s.[i + k] in
            cc land 0xC0 = 0x80 && check_cont (k + 1)
          in
          check_cont 1 && loop (i + n_cont + 1)
  in
  loop 0

let test_two_instances_no_cross_contamination () =
  let listing path =
    if path = "/alpha" then ["alpha_one"; "alpha_two"]
    else if path = "/beta" then ["beta_one"; "beta_two"]
    else []
  in
  Miaou_interfaces.System.set (make_stub ~listing) ;
  let a = FB.open_centered ~path:"/alpha" ~dirs_only:false () in
  let b = FB.open_centered ~path:"/beta" ~dirs_only:false () in
  let size = {LTerm_geom.rows = 20; cols = 40} in
  (* Render b first so its listing is cached, then render a: a must still
     see its own entries, not b's. *)
  let out_b = FB.render_with_size b ~focus:true ~size in
  let out_a = FB.render_with_size a ~focus:true ~size in
  check bool "alpha sees its own entry" true (String.length out_a > 0) ;
  check
    bool
    "alpha listing contains alpha_one"
    true
    (Astring.String.is_infix ~affix:"alpha_one" out_a) ;
  check
    bool
    "alpha listing does not contain beta entries"
    false
    (Astring.String.is_infix ~affix:"beta_one" out_a) ;
  check
    bool
    "beta listing contains beta_one"
    true
    (Astring.String.is_infix ~affix:"beta_one" out_b) ;
  check
    bool
    "beta listing does not contain alpha entries"
    false
    (Astring.String.is_infix ~affix:"alpha_one" out_b)

let test_invalidate_cache_refreshes_all_instances () =
  let call_count = ref 0 in
  let listing _path =
    incr call_count ;
    if !call_count <= 1 then ["before"] else ["after"]
  in
  Miaou_interfaces.System.set (make_stub ~listing) ;
  let w = FB.open_centered ~path:"/gamma" ~dirs_only:false () in
  let size = {LTerm_geom.rows = 20; cols = 40} in
  let out1 = FB.render_with_size w ~focus:true ~size in
  check
    bool
    "sees initial listing"
    true
    (Astring.String.is_infix ~affix:"before" out1) ;
  FB.invalidate_cache () ;
  let out2 = FB.render_with_size w ~focus:true ~size in
  check
    bool
    "sees refreshed listing after invalidate_cache"
    true
    (Astring.String.is_infix ~affix:"after" out2)

let test_same_path_different_dirs_only_no_contamination () =
  (* The pre-fix cache keyed only on (path, show_hidden): a [dirs_only:true]
     browser and a [dirs_only:false] browser at the *same* path would
     silently share (and corrupt) each other's cached listing since
     [dirs_only] filtering happens before caching. *)
  let is_directory p = String.length p > 0 && p.[String.length p - 1] <> 't' in
  Miaou_interfaces.System.set
    {(make_stub ~listing:(fun _ -> ["a_dir"; "b_file.txt"])) with is_directory} ;
  let dirs_only_w = FB.open_centered ~path:"/mixed" ~dirs_only:true () in
  let all_w = FB.open_centered ~path:"/mixed" ~dirs_only:false () in
  let size = {LTerm_geom.rows = 20; cols = 40} in
  let out_dirs_only = FB.render_with_size dirs_only_w ~focus:true ~size in
  let out_all = FB.render_with_size all_w ~focus:true ~size in
  check
    bool
    "dirs_only listing excludes the file"
    false
    (Astring.String.is_infix ~affix:"b_file.txt" out_dirs_only) ;
  check
    bool
    "unfiltered listing includes the file"
    true
    (Astring.String.is_infix ~affix:"b_file.txt" out_all)

let test_multibyte_name_truncation_stays_valid_utf8 () =
  (* Each CJK codepoint below is 3 bytes in UTF-8 and renders as width 2
     (wide char), so a narrow column width forces a mid-name cut. *)
  let long_name = String.concat "" (List.init 30 (fun _ -> "\xe6\x97\xa5")) in
  (* "日" repeated *)
  Miaou_interfaces.System.set (make_stub ~listing:(fun _ -> [long_name])) ;
  let w = FB.open_centered ~path:"/utf8" ~dirs_only:false () in
  let size = {LTerm_geom.rows = 20; cols = 15} in
  let out = FB.render_with_size w ~focus:true ~size in
  check
    bool
    "render does not raise and is non-empty"
    true
    (String.length out > 0) ;
  check bool "output stays valid UTF-8" true (is_valid_utf8 out)

let () =
  run
    "file_browser_cache"
    [
      ( "file_browser_cache",
        [
          test_case
            "two instances no cross-contamination"
            `Quick
            test_two_instances_no_cross_contamination;
          test_case
            "invalidate_cache refreshes all instances"
            `Quick
            test_invalidate_cache_refreshes_all_instances;
          test_case
            "same path, different dirs_only, no contamination"
            `Quick
            test_same_path_different_dirs_only_no_contamination;
          test_case
            "multibyte name truncation stays valid UTF-8"
            `Quick
            test_multibyte_name_truncation_stays_valid_utf8;
        ] );
    ]
