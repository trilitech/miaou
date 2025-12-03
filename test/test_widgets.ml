let () =
  let module Sys_stub = struct
    let file_exists = Sys.file_exists

    let is_directory p =
      try (Unix.stat p).Unix.st_kind = Unix.S_DIR with _ -> false

    let read_file p =
      try Ok (In_channel.with_open_bin p In_channel.input_all)
      with e -> Error (Printexc.to_string e)

    let write_file p contents =
      try
        let oc = open_out p in
        output_string oc contents ;
        close_out oc ;
        Ok ()
      with e -> Error (Printexc.to_string e)

    let mkdir p =
      try
        Unix.mkdir p 0o755 ;
        Ok ()
      with e -> Error (Printexc.to_string e)

    let run_command ~argv:_ ~cwd:_ = Error "not implemented in tests"

    let get_current_user_info () = Ok (Unix.getlogin (), Sys.getenv "HOME")

    let get_disk_usage ~path:_ = try Ok 0L with _ -> Error "unavailable"

    let list_dir p =
      try Ok (Array.to_list (Sys.readdir p))
      with e -> Error (Printexc.to_string e)

    let probe_writable ~path =
      try
        let tmp =
          Filename.concat path (Printf.sprintf ".probe_%d" (Unix.getpid ()))
        in
        let oc = open_out tmp in
        output_string oc "" ;
        close_out oc ;
        Sys.remove tmp ;
        Ok true
      with _ -> Ok false

    let get_env_var v = Sys.getenv_opt v
  end in
  Miaou_interfaces.System.set
    {
      Miaou_interfaces.System.file_exists = Sys_stub.file_exists;
      is_directory = Sys_stub.is_directory;
      read_file = Sys_stub.read_file;
      write_file = Sys_stub.write_file;
      mkdir = Sys_stub.mkdir;
      run_command = Sys_stub.run_command;
      get_current_user_info = Sys_stub.get_current_user_info;
      get_disk_usage = Sys_stub.get_disk_usage;
      list_dir = Sys_stub.list_dir;
      probe_writable = Sys_stub.probe_writable;
      get_env_var = Sys_stub.get_env_var;
    } ;
  let open Alcotest in
  let test_split_lines () =
    let open Miaou_widgets_layout.Pane_layout in
    check (list string) "empty" [] (split_lines "") ;
    check (list string) "single" ["a"] (split_lines "a") ;
    check (list string) "multi" ["a"; "b"; "c"] (split_lines "a\nb\nc")
  in
  let test_table_render () =
    let open Miaou_widgets_display.Table_widget in
    let columns =
      [
        {Table.header = "A"; to_string = (fun (a, _b) -> a)};
        {Table.header = "B"; to_string = (fun (_a, b) -> b)};
      ]
    in
    let rows = [("one", "1"); ("two", "2")] in
    let t = Table.create ~columns ~rows () in
    let s = Table.render t in
    check bool "contains header" true (String.contains s 'A')
  in
  let test_pane_borders_visible_width () =
    let module P = Miaou_widgets_layout.Pane in
    let module W = Miaou_widgets_display.Widgets in
    let width = 20 in
    let s =
      P.split_vertical_with_left_width
        ~width
        ~left_pad:0
        ~right_pad:0
        ~border:true
        ~wrap:true
        ~sep:"|"
        ~left:"L"
        ~right:"R"
        ~left_width:8
    in
    let lines = String.split_on_char '\n' s in
    let top = List.hd lines and bot = List.nth lines (List.length lines - 1) in
    let vis = W.visible_chars_count in
    Alcotest.(check int) "top visible width" width (vis top) ;
    Alcotest.(check int) "bottom visible width" width (vis bot) ;
    let repeat str n = String.concat "" (List.init n (fun _ -> str)) in
    let expected_top =
      W.glyph_corner_tl ^ repeat W.glyph_hline (width - 2) ^ W.glyph_corner_tr
    in
    let expected_bot =
      W.glyph_corner_bl ^ repeat W.glyph_hline (width - 2) ^ W.glyph_corner_br
    in
    Alcotest.(check string) "top matches expected" expected_top top ;
    Alcotest.(check string) "bottom matches expected" expected_bot bot
  in
  run
    "widgets"
    [
      ( "file-browser-editing",
        [
          test_case "edit-path-to-tmp" `Quick (fun () ->
              let open Miaou_widgets_layout.File_browser_widget in
              let w0 = open_centered ~path:"/" () in
              let w1 = handle_key w0 ~key:"Tab" in
              let w2 = handle_key w1 ~key:"/" in
              let w3 = handle_key w2 ~key:"t" in
              let w4 = handle_key w3 ~key:"Tab" in
              let w5 = handle_key w4 ~key:"Enter" in
              Alcotest.(check bool) "not-cancelled" false (is_cancelled w5));
        ] );
      ("pane", [test_case "split_lines" `Quick test_split_lines]);
      ( "table",
        [
          test_case "render" `Quick test_table_render;
          test_case "layout_autofit" `Quick (fun () ->
              let open Miaou_widgets_display.Table_widget in
              let columns =
                [
                  {Table.header = "A"; to_string = (fun (a, _b) -> a)};
                  {Table.header = "B"; to_string = (fun (_a, b) -> b)};
                ]
              in
              let rows =
                [(String.make 30 'x', "v"); ("short", String.make 10 'y')]
              in
              let layout =
                [
                  {
                    Table.min_width = Some 5;
                    max_width = Some 10;
                    weight = Some 1;
                    pad_left = Some 1;
                    pad_right = Some 1;
                  };
                  {
                    Table.min_width = Some 3;
                    max_width = None;
                    weight = Some 3;
                    pad_left = Some 1;
                    pad_right = Some 1;
                  };
                ]
              in
              let t = Table.create ~cols:50 ~layout ~columns ~rows () in
              let rendered = Table.render t in
              let has_ellipsis =
                String.contains rendered '\226'
                || String.contains rendered '\133'
                || String.contains rendered '\166'
              in
              Alcotest.(check bool) "ellipsis present" true has_ellipsis);
        ] );
      ( "pane-borders",
        [test_case "visible-width" `Quick test_pane_borders_visible_width] );
    ]
