open Alcotest

module FB = Miaou_widgets_layout.File_browser_widget

let make_stub ~writable =
  let open Miaou_interfaces in
  let run_command ~argv:_ ~cwd:_ = Ok System.{exit_code = 0; stdout = ""; stderr = ""} in
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
  check bool "selection maybe" true (Option.is_some (FB.get_selection w) || Option.is_none w.textbox) ;
  let w = FB.handle_key w ~key:"Up" |> FB.handle_key ~key:"Down" in
  let rendered = FB.render_with_size w ~focus:true ~size:{LTerm_geom.rows = 10; cols = 50} in
  check bool "rendered body" true (String.length rendered > 0) ;
  ignore w

let test_not_writable_error () =
  Miaou_interfaces.System.set (make_stub ~writable:false) ;
  let w = FB.open_centered ~path:"/tmp" ~dirs_only:false () in
  let tb = FB.textbox_create ~initial:"/tmp/dir1" () in
  let w = {w with FB.mode = FB.EditingPath; textbox = Some tb} in
  let w = FB.handle_key w ~key:"Enter" in
  check bool "path error set" true (Option.is_some w.FB.path_error)

let () =
  run
    "file_browser_extra"
    [
      ( "file_browser_extra",
        [
          test_case "autocomplete/history" `Quick test_autocomplete_and_history;
          test_case "not writable" `Quick test_not_writable_error;
        ] );
    ]
