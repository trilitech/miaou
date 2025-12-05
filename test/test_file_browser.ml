open Alcotest

module FB = Miaou_widgets_layout.File_browser_widget

let stub_system =
  let open Miaou_interfaces in
  let run_command ~argv:_ ~cwd:_ = Ok System.{exit_code = 0; stdout = ""; stderr = ""} in
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
      list_dir = (fun _ -> Ok ["docs"; "file.txt"]);
      probe_writable = (fun ~path:_ -> Ok true);
      get_env_var = (fun _ -> None);
    }

let test_browsing_and_edit () =
  Miaou_interfaces.System.set stub_system ;
  let w = FB.open_centered ~path:"/tmp" ~dirs_only:false () in
  let w = FB.handle_key w ~key:"Down" in
  let w = FB.handle_key w ~key:"Tab" in
  (* Page navigation and cursor movement *)
  let w = FB.handle_key w ~key:"PageDown" in
  let w = FB.handle_key w ~key:"PageUp" in
  (* Enter editing mode and commit a file selection *)
  let tb = FB.textbox_create ~initial:"/tmp/file.txt" () in
  let w = {w with FB.mode = FB.EditingPath; textbox = Some tb} in
  let w = FB.handle_key w ~key:"Enter" in
  check bool "has selection" true (Option.is_some (FB.get_selection w)) ;
  let w = FB.handle_key w ~key:"Esc" in
  check bool "not cancelled" true (not (FB.is_cancelled w)) ;
  let w = FB.reset_cancelled w in
  check bool "reset" true (not (FB.is_cancelled w)) ;
  (* Error branch: missing path *)
  let stub_missing =
    {
      stub_system with
      Miaou_interfaces.System.file_exists = (fun _ -> false);
      probe_writable = (fun ~path:_ -> Error "no");
    }
  in
  Miaou_interfaces.System.set stub_missing ;
  let w2 = FB.open_centered ~path:"/tmp" ~dirs_only:false () in
  let tb2 = FB.textbox_create ~initial:"/tmp/missing" () in
  let w2 = {w2 with FB.mode = FB.EditingPath; textbox = Some tb2} in
  let w2 = FB.handle_key w2 ~key:"Enter" in
  check bool "path error set" true (Option.is_some w2.FB.path_error) ;
  let w2 = FB.handle_key w2 ~key:"Up" in
  ignore w2
  ;
  let stub_missing = {stub_system with Miaou_interfaces.System.file_exists = (fun _ -> false)} in
  Miaou_interfaces.System.set stub_missing ;
  let w2 = FB.open_centered ~path:"/tmp" ~dirs_only:false () in
  let tb2 = FB.textbox_create ~initial:"/tmp/missing" () in
  let w2 = {w2 with FB.mode = FB.EditingPath; textbox = Some tb2} in
  let w2 = FB.handle_key w2 ~key:"Enter" in
  check bool "path error set" true (Option.is_some w2.FB.path_error)

let suite = [test_case "browse/edit workflow" `Quick test_browsing_and_edit]

let () = run "file_browser" [("file_browser", suite)]
