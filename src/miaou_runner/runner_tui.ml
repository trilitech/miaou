let run ?(enable_mouse = true) page =
  let term_backend =
    {
      Miaou_runner_common.Tui_driver_common.available =
        Miaou_driver_term.Lambda_term_driver.available;
      run = Miaou_driver_term.Lambda_term_driver.run;
    }
  in
  let sdl_backend =
    {
      Miaou_runner_common.Tui_driver_common.available = false;
      run = (fun _ -> `Quit);
    }
  in
  let matrix_config =
    if enable_mouse then None
    else
      Some
        (Miaou_driver_matrix.Matrix_config.load ()
        |> Miaou_driver_matrix.Matrix_config.with_mouse_disabled)
  in
  let matrix_backend =
    {
      Miaou_runner_common.Tui_driver_common.available =
        Miaou_driver_matrix.Matrix_driver.available;
      run = Miaou_driver_matrix.Matrix_driver.run ~config:matrix_config;
    }
  in
  Miaou_runner_common.Tui_driver_common.run
    ~term_backend
    ~sdl_backend
    ~matrix_backend
    page
