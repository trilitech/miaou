(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

module Img = Miaou_widgets_display.Image_widget

type display_mode = Logo | Gradient

module Inner = struct
  let tutorial_title = "Image Widget"

  let tutorial_markdown = [%blob "README.md"]

  type state = {
    mode : display_mode;
    next_page : string option;
    logo_image : (Img.t, string) result option;
    mutable logo_widget : Miaou_widgets_display.Image_widget.t option;
    mutable gradient_widget : Miaou_widgets_display.Image_widget.t option;
  }

  type msg = KeyPressed of string

  let init () =
    let logo_result =
      let module W = Miaou_widgets_display.Widgets in
      let img_width, img_height, logo_path =
        match W.get_backend () with
        | `Terminal -> (50, 25, "example/miaou_logo_small.png")
        | `Sdl -> (600, 450, "example/miaou_logo_small.png")
      in
      Img.load_from_file
        logo_path
        ~max_width:img_width
        ~max_height:img_height
        ()
    in
    {
      mode = Logo;
      next_page = None;
      logo_image = Some logo_result;
      logo_widget = None;
      gradient_widget = None;
    }

  let update s = function
    | KeyPressed ("escape" | "Esc") ->
        {s with next_page = Some Demo_shared.Demo_config.launcher_page_name}
    | KeyPressed _ -> s

  let create_gradient_image width height =
    let rgb_data = Bytes.create (width * height * 3) in
    for y = 0 to height - 1 do
      for x = 0 to width - 1 do
        let offset = ((y * width) + x) * 3 in
        let r = x * 255 / width in
        let g = y * 255 / height in
        let b = (x + y) * 255 / (width + height) in
        Bytes.set rgb_data offset (Char.chr r) ;
        Bytes.set rgb_data (offset + 1) (Char.chr g) ;
        Bytes.set rgb_data (offset + 2) (Char.chr b)
      done
    done ;
    Img.create_from_rgb ~width ~height ~rgb_data ()

  let view s ~focus:_ ~size:_ =
    let module W = Miaou_widgets_display.Widgets in
    let header = W.titleize "Image Widget Demo" in
    let img_width, img_height =
      match W.get_backend () with `Terminal -> (50, 25) | `Sdl -> (600, 450)
    in
    let img_display, img_info =
      match s.mode with
      | Logo ->
          let sdl_context =
            Miaou_widgets_display.Sdl_chart_context.get_context ()
          in
          let in_transition = W.get_backend () = `Sdl && sdl_context = None in
          if in_transition then ("", "Loading...")
          else
            let widget =
              match s.logo_widget with
              | Some w -> w
              | None -> (
                  let img_result =
                    match s.logo_image with
                    | Some result -> result
                    | None -> Error "Image not loaded at init"
                  in
                  match img_result with
                  | Ok img ->
                      s.logo_widget <- Some img ;
                      img
                  | Error _ ->
                      let img = create_gradient_image img_width img_height in
                      s.logo_widget <- Some img ;
                      img)
            in
            let w, h = Img.get_dimensions widget in
            let backend_info =
              match W.get_backend () with
              | `Terminal ->
                  "TUI (cropped)\nUnicode half-blocks\nANSI 256-color"
              | `Sdl -> "SDL (full image)\nDirect pixel rendering"
            in
            ( Img.render widget ~focus:true,
              Printf.sprintf
                "MIAOU Logo\nDisplayed: %d×%d\n\n%s"
                w
                h
                backend_info )
      | Gradient ->
          let widget =
            match s.gradient_widget with
            | Some w -> w
            | None ->
                let img = create_gradient_image img_width img_height in
                s.gradient_widget <- Some img ;
                img
          in
          ( Img.render widget ~focus:true,
            Printf.sprintf
              "Procedural Gradient\nGenerated: %d×%d pixels\nRGB interpolation"
              img_width
              img_height )
    in
    let mode_label =
      match s.mode with
      | Logo -> W.bold "1: Logo (current)"
      | Gradient -> "1: Logo"
    in
    let gradient_label =
      match s.mode with
      | Logo -> "2: Gradient"
      | Gradient -> W.bold "2: Gradient (current)"
    in
    let img_lines = String.split_on_char '\n' img_display in
    let info_lines = String.split_on_char '\n' img_info in
    let max_img_lines = List.length img_lines in
    let combined_lines = ref [] in
    for i = 0 to max_img_lines - 1 do
      let img_line =
        if i < List.length img_lines then List.nth img_lines i else ""
      in
      let info_line =
        if i < List.length info_lines then "  | " ^ List.nth info_lines i
        else ""
      in
      combined_lines := (img_line ^ info_line) :: !combined_lines
    done ;
    let combined = String.concat "\n" (List.rev !combined_lines) in
    let instructions =
      W.dim (mode_label ^ " | " ^ gradient_label ^ " | t: help | q: back")
    in
    String.concat "\n\n" [header; combined; instructions]

  let go_back s =
    {s with next_page = Some Demo_shared.Demo_config.launcher_page_name}

  let handle_key s key_str ~size:_ =
    let s = update s (KeyPressed key_str) in
    match key_str with
    | "1" -> {s with mode = Logo}
    | "2" -> {s with mode = Gradient}
    | "q" -> go_back s
    | _ -> s

  let move s _ = s

  let refresh s = s

  let enter s = s

  let service_select s _ = s

  let service_cycle s _ = s

  let handle_modal_key s _ ~size:_ = s

  let next_page s = s.next_page

  let keymap (_ : state) = []

  let handled_keys () = []

  let back s = go_back s

  let has_modal _ = false
end

include Demo_shared.Demo_page.Make (Inner)
