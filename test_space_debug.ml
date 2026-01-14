(* Debug test to trace the exact flow *)
module FB = Miaou_widgets_layout.File_browser_widget

let stub_system =
  let open Miaou_interfaces in
  let run_command ~argv:_ ~cwd:_ =
    Ok System.{exit_code = 0; stdout = ""; stderr = ""}
  in
  System.
    {
      file_exists = (fun _ -> true);
      is_directory = (fun p -> String.ends_with ~suffix:"/" p || p = "/tmp" || p = "/src");
      read_file = (fun _ -> Ok "");
      write_file = (fun _ _ -> Ok ());
      mkdir = (fun _ -> Ok ());
      run_command;
      get_current_user_info = (fun () -> Ok ("user", "/home/user"));
      get_disk_usage = (fun ~path:_ -> Ok 0L);
      list_dir = (fun _ -> Ok ["src"; "file.txt"]);
      probe_writable = (fun ~path:_ -> Ok true);
      get_env_var = (fun _ -> None);
    }

let () =
  Miaou_interfaces.System.set stub_system ;
  
  (* Start in /tmp *)
  let w = FB.open_centered ~path:"/tmp" ~dirs_only:false () in
  Printf.printf "Step 1 - Initial state\n";
  Printf.printf "  mode: %s\n" (if FB.is_editing w then "EditingPath" else "Browsing");
  Printf.printf "  pending_selection: %s\n" 
    (match FB.get_pending_selection w with Some p -> p | None -> "None");
  
  (* Press Tab to enter edit mode *)
  Printf.printf "\nStep 2 - Press Tab\n";
  let w = FB.handle_key w ~key:"Tab" in
  Printf.printf "  mode: %s\n" (if FB.is_editing w then "EditingPath" else "Browsing");
  Printf.printf "  pending_selection: %s\n" 
    (match FB.get_pending_selection w with Some p -> p | None -> "None");
  Printf.printf "  textbox content: '%s'\n" (FB.current_input w);
  
  (* Type / *)
  Printf.printf "\nStep 3 - Type '/'\n";
  let w = FB.handle_key w ~key:"/" in
  Printf.printf "  mode: %s\n" (if FB.is_editing w then "EditingPath" else "Browsing");
  Printf.printf "  textbox content: '%s'\n" (FB.current_input w);
  
  (* Type t *)
  Printf.printf "\nStep 4 - Type 't'\n";
  let w = FB.handle_key w ~key:"t" in
  Printf.printf "  mode: %s\n" (if FB.is_editing w then "EditingPath" else "Browsing");
  Printf.printf "  textbox content: '%s'\n" (FB.current_input w);
  
  (* Press Space *)
  Printf.printf "\nStep 5 - Press Space (key = \" \")\n";
  let w = FB.handle_key w ~key:" " in
  Printf.printf "  mode: %s\n" (if FB.is_editing w then "EditingPath" else "Browsing");
  Printf.printf "  pending_selection: %s\n" 
    (match FB.get_pending_selection w with Some p -> p | None -> "None");
  Printf.printf "  textbox content: '%s'\n" (FB.current_input w);
  
  if FB.get_pending_selection w <> None then
    Printf.printf "\n❌ BUG: Space set pending_selection!\n"
  else
    Printf.printf "\n✓ OK: Space did not set pending_selection\n"
