open Alcotest
module FB = Miaou_widgets_layout.File_browser_widget

let make_stub ~writable =
  let open Miaou_interfaces in
  let run_command ~argv:_ ~cwd:_ =
    Ok System.{exit_code = 0; stdout = ""; stderr = ""}
  in
  let files = ["dir1"; "dir2"; "file.txt"; "other.log"] in
  System.
    {
      file_exists = (fun _ -> true);
      is_directory = (fun p -> not (String.ends_with ~suffix:".txt" p));
      read_file = (fun _ -> Ok "");
      write_file = (fun _ _ -> Ok ());
      mkdir = (fun _ -> Ok ());
      run_command;
      get_current_user_info = (fun () -> Ok ("user", "/home/user"));
      get_disk_usage = (fun ~path:_ -> Ok 0L);
      list_dir = (fun _ -> Ok files);
      probe_writable = (fun ~path:_ -> if writable then Ok true else Error "no");
      get_env_var = (fun _ -> None);
    }

let test_autocomplete_and_history () =
  Miaou_interfaces.System.set (make_stub ~writable:true) ;
  let w = FB.open_centered ~path:"/tmp" ~dirs_only:false () in
  let w = FB.handle_key w ~key:"Tab" in
  (* autocomplete from current path *)
  let tb = FB.textbox_create ~initial:"/tmp/d" () in
  let w = {w with FB.mode = FB.EditingPath; textbox = Some tb} in
  let w = FB.handle_key w ~key:"Tab" in
  check bool "autocomplete" true (Option.is_some w.textbox) ;
  let w = FB.handle_key w ~key:"Shift-Tab" in
  check bool "shift tab" true (Option.is_some w.textbox) ;
  let w = FB.handle_key w ~key:"Enter" in
  check
    bool
    "selection maybe"
    true
    (Option.is_some (FB.get_selection w) || Option.is_none w.textbox) ;
  let w = FB.handle_key w ~key:"Up" |> FB.handle_key ~key:"Down" in
  let rendered =
    FB.render_with_size w ~focus:true ~size:{LTerm_geom.rows = 10; cols = 50}
  in
  check bool "rendered body" true (String.length rendered > 0) ;
  ignore w

let test_enter_enters_directory () =
  Miaou_interfaces.System.set (make_stub ~writable:true) ;
  let w = FB.open_centered ~path:"/root" ~dirs_only:false () in
  (* Cursor defaults to parent entry; ensure it appears and works. *)
  let first =
    FB.render_with_size w ~focus:true ~size:{LTerm_geom.rows = 6; cols = 40}
  in
  check bool "parent entry present" true (String.contains first '.') ;
  let w' = FB.handle_key w ~key:"Enter" in
  check string "navigated to parent" "/" w'.FB.current_path ;
  check int "cursor reset" 0 w'.FB.cursor ;
  let w_dir = {w with FB.cursor = 2} |> FB.handle_key ~key:"Enter" in
  check string "navigated into dir" "/root/dir1" w_dir.FB.current_path

let test_not_writable_error () =
  Miaou_interfaces.System.set (make_stub ~writable:false) ;
  let w = FB.open_centered ~path:"/tmp" ~dirs_only:false () in
  let tb = FB.textbox_create ~initial:"/tmp/dir1" () in
  let w = {w with FB.mode = FB.EditingPath; textbox = Some tb} in
  let w = FB.handle_key w ~key:"Enter" in
  check bool "path error set" true (Option.is_some w.FB.path_error)

let test_read_only_mode () =
  Miaou_interfaces.System.set (make_stub ~writable:false) ;
  let w =
    FB.open_centered ~path:"/tmp" ~dirs_only:false ~require_writable:false ()
  in
  let tb = FB.textbox_create ~initial:"/tmp/dir1" () in
  let w = {w with FB.mode = FB.EditingPath; textbox = Some tb} in
  let w = FB.handle_key w ~key:"Enter" in
  check bool "no error in read mode" true (Option.is_none w.FB.path_error)

let test_viewport_scrolls () =
  let open Miaou_interfaces in
  let has_sub s sub =
    try
      let _ = Str.search_forward (Str.regexp_string sub) s 0 in
      true
    with Not_found -> false
  in
  let entries =
    List.init 12 (fun i -> Printf.sprintf "dir%02d" i)
    @ ["file.txt"; "other.log"]
  in
  let sys =
    {
      (make_stub ~writable:true) with
      System.list_dir = (fun _ -> Ok entries);
      is_directory = (fun p -> not (String.ends_with ~suffix:".txt" p));
    }
  in
  System.set sys ;
  let w = FB.open_centered ~path:"/tmp" ~dirs_only:false () in
  (* Move cursor to the end to force scrolling. *)
  let w = {w with FB.cursor = 15} in
  let rendered =
    FB.render_with_size w ~focus:true ~size:{LTerm_geom.rows = 12; cols = 40}
  in
  check bool "shows last entry" true (has_sub rendered "other.log") ;
  (* With the cursor around the end of the first viewport, the first entries
     should already be scrolled away. *)
  let w = {w with FB.cursor = 10} in
  let rendered2 =
    FB.render_with_size w ~focus:true ~size:{LTerm_geom.rows = 12; cols = 40}
  in
  check bool "first entry scrolled" true (not (has_sub rendered2 "dir00"))

let test_selection_matches_cursor () =
  Miaou_interfaces.System.set (make_stub ~writable:true) ;
  let w =
    FB.open_centered ~path:"/root" ~dirs_only:false ~select_dirs:true ()
  in
  (* Parent entry index 0, dot entry index 1, first real entry index 2. *)
  let w = {w with FB.cursor = 2} in
  check
    string
    "cursor aligned with selection"
    "/root/dir1"
    (Option.value ~default:"" (FB.get_selection w)) ;
  (* Dot entry selects the current directory. *)
  let w_dot = {w with FB.cursor = 1} in
  check
    string
    "dot selects current"
    "/root"
    (Option.value ~default:"" (FB.get_selection w_dot)) ;
  (* Enter on dot should keep selection and not navigate. *)
  let w_dot_enter = FB.handle_key w_dot ~key:"Enter" in
  check
    string
    "dot enter selects current"
    "/root"
    (Option.value ~default:"" (FB.get_selection w_dot_enter)) ;
  check string "dot enter stays put" "/root" w_dot_enter.FB.current_path

let test_browse_dirs_when_not_selectable () =
  Miaou_interfaces.System.set (make_stub ~writable:true) ;
  let w =
    FB.open_centered ~path:"/root" ~dirs_only:false ~select_dirs:false ()
  in
  (* Move to dir1 (index 2 because of .. and .). *)
  let w_dir = {w with FB.cursor = 2} |> FB.handle_key ~key:"Enter" in
  check string "navigated into dir" "/root/dir1" w_dir.FB.current_path ;
  (* Selection on directories should be None when select_dirs=false. *)
  let sel_dir = FB.get_selection {w with FB.cursor = 2} in
  check bool "dir not selectable" true (Option.is_none sel_dir) ;
  (* Files remain selectable. *)
  let w_file = {w with FB.cursor = 5} in
  match FB.get_selected_entry w_file with
  | Some e ->
      check string "file entry is file.txt" "file.txt" e.FB.name ;
      check
        bool
        "file selectable"
        true
        (Option.is_some (FB.get_selection w_file))
  | None -> fail "expected a selected entry"

let () =
  run
    "file_browser_extra"
    [
      ( "file_browser_extra",
        [
          test_case "autocomplete/history" `Quick test_autocomplete_and_history;
          test_case "enter navigates dir" `Quick test_enter_enters_directory;
          test_case "not writable" `Quick test_not_writable_error;
          test_case "read only mode" `Quick test_read_only_mode;
          test_case "viewport scrolls to end" `Quick test_viewport_scrolls;
          test_case
            "selection matches cursor"
            `Quick
            test_selection_matches_cursor;
          test_case
            "browse dirs when not selectable"
            `Quick
            test_browse_dirs_when_not_selectable;
        ] );
    ]
