(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

[@@@warning "-32-34-37-69"]

module Logger_capability = Miaou_interfaces.Logger_capability
module Capture = Miaou_core.Tui_capture
module Modal_renderer = Miaou_internals.Modal_renderer
module Modal_manager = Miaou_core.Modal_manager
module Registry = Miaou_core.Registry
open Miaou_core.Tui_page

module Ttf = Tsdl_ttf.Ttf
module Sdl = Tsdl.Sdl
open LTerm_geom

let () = Random.self_init ()

let available = true

type color = {r : int; g : int; b : int; a : int}

type ansi_state = {fg : color; bg : color}

type config = {
  font_path : string option;
  font_size : int;
  window_title : string;
  fg : color;
  bg : color;
  gradient : bool;
  scale : float;
  transition : [ `None | `Slide | `Fade | `Explode | `Random ];
}

let detect_display_scale () =
  match Sdl.get_display_dpi 0 with
  | Ok (_ddpi, hdpi, _vdpi) ->
      let scale = hdpi /. 96.0 in
      let clamped = max 1.0 (min 3.0 scale) in
      Some clamped
  | Error _ -> None

let default_config =
  {
    font_path = None;
    font_size =
      (match Sys.getenv_opt "MIAOU_SDL_FONT_SIZE" with
      | Some s -> (try int_of_string s with _ -> 16)
      | None -> 16);
    window_title =
      Sys.getenv_opt "MIAOU_SDL_WINDOW_TITLE" |> Option.value ~default:"Miaou";
    fg = {r = 235; g = 235; b = 235; a = 255};
    bg = {r = 20; g = 20; b = 20; a = 255};
    gradient =
      (match Sys.getenv_opt "MIAOU_SDL_GRADIENT" with
      | Some v ->
          let v = String.lowercase_ascii (String.trim v) in
          not (v = "0" || v = "false" || v = "off")
      | None -> true);
    scale =
      (match Sys.getenv_opt "MIAOU_SDL_SCALE" with
      | Some v -> (try float_of_string v with _ -> 2.0)
      | None -> detect_display_scale () |> Option.value ~default:2.0);
    transition =
      (match Sys.getenv_opt "MIAOU_SDL_TRANSITION" with
      | Some v ->
          let v = String.lowercase_ascii (String.trim v) in
          if v = "slide" then `Slide
          else if v = "fade" then `Fade
          else if v = "explode" then `Explode
          else if v = "random" then `Random
          else `None
      | None -> `Slide);
  }

let font_candidates =
  [
    "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf";
    "/usr/share/fonts/truetype/liberation/LiberationMono-Regular.ttf";
    "/Library/Fonts/Menlo-Regular.ttf";
    "/System/Library/Fonts/Menlo.ttc";
    "/usr/share/fonts/TTF/DejaVuSansMono.ttf";
  ]

let pick_font_path (cfg : config) =
  match cfg.font_path with
  | Some p when Sys.file_exists p -> Ok p
  | Some p ->
      Error
        (Printf.sprintf
           "Configured MIAOU_SDL_FONT does not exist: %s (current working \
            directory: %s)"
           p
           (Sys.getcwd ()))
  | None -> (
      match Sys.getenv_opt "MIAOU_SDL_FONT" with
      | Some env when Sys.file_exists env -> Ok env
      | Some env ->
          Error
            (Printf.sprintf
               "Configured MIAOU_SDL_FONT does not exist: %s (cwd: %s)"
               env
               (Sys.getcwd ()))
      | None ->
          (* Pick the first available candidate; if none exist, report all. *)
          let available = List.filter Sys.file_exists font_candidates in
          match available with
          | p :: _ -> Ok p
          | [] ->
              Error
                (Printf.sprintf
                   "Could not find any monospaced font. Provide \
                    MIAOU_SDL_FONT=<path> to a .ttf file. Probed: %s"
                   (String.concat ", " font_candidates)))

let sdl_fail prefix msg =
  failwith (Printf.sprintf "%s: %s" prefix msg)

let with_sdl init_fn =
  match Sdl.init Sdl.Init.(video) with
  | Error (`Msg e) -> sdl_fail "SDL init" e
  | Ok () -> (
      ignore (Sdl.set_hint Sdl.Hint.render_scale_quality "linear") ;
      match Ttf.init () with
      | Error (`Msg e) ->
          let () = Sdl.quit () in
          sdl_fail "SDL_ttf init" e
      | Ok () -> (
          try
            let res = init_fn () in
            Ttf.quit () ;
            Sdl.quit () ;
            res
          with e ->
            Ttf.quit () ;
            Sdl.quit () ;
            raise e))

let ansi_palette =
  [|
    {r = 0; g = 0; b = 0; a = 255};
    {r = 205; g = 49; b = 49; a = 255};
    {r = 13; g = 188; b = 121; a = 255};
    {r = 229; g = 229; b = 16; a = 255};
    {r = 36; g = 114; b = 200; a = 255};
    {r = 188; g = 63; b = 188; a = 255};
    {r = 17; g = 168; b = 205; a = 255};
    {r = 229; g = 229; b = 229; a = 255};
  |]

let ansi_bright_palette =
  [|
    {r = 102; g = 102; b = 102; a = 255};
    {r = 241; g = 76; b = 76; a = 255};
    {r = 35; g = 209; b = 139; a = 255};
    {r = 245; g = 245; b = 67; a = 255};
    {r = 59; g = 142; b = 234; a = 255};
    {r = 214; g = 112; b = 214; a = 255};
    {r = 41; g = 184; b = 219; a = 255};
    {r = 229; g = 229; b = 229; a = 255};
  |]

let color_to_sdl ({r; g; b; a} : color) : Sdl.color =
  Sdl.Color.create ~r ~g ~b ~a

let clamp lo hi v = if v < lo then lo else if v > hi then hi else v

let color256 idx =
  let idx = clamp 0 255 idx in
  if idx < 16 then
    let base = ansi_palette in
    let bright = ansi_bright_palette in
    if idx < 8 then base.(idx) else bright.(idx - 8)
  else if idx < 232 then
    let n = idx - 16 in
    let r = n / 36 in
    let g = (n / 6) mod 6 in
    let b = n mod 6 in
    let to_int c = if c = 0 then 0 else 55 + (c * 40) in
    {r = to_int r; g = to_int g; b = to_int b; a = 255}
  else
    let level = 8 + ((idx - 232) * 10) in
    {r = level; g = level; b = level; a = 255}

let apply_sgr_code ~(default : ansi_state) state code =
  match code with
  | 0 ->
      (* reset *)
      {fg = default.fg; bg = default.bg}
  | 39 -> {state with fg = default.fg}
  | 49 -> {state with bg = default.bg}
  | c when c >= 30 && c <= 37 ->
      let idx = c - 30 in
      {state with fg = ansi_palette.(idx)}
  | c when c >= 90 && c <= 97 ->
      let idx = c - 90 in
      {state with fg = ansi_bright_palette.(idx)}
  | c when c >= 40 && c <= 47 ->
      let idx = c - 40 in
      {state with bg = ansi_palette.(idx)}
  | c when c >= 100 && c <= 107 ->
      let idx = c - 100 in
      {state with bg = ansi_bright_palette.(idx)}
  | _ -> state

let apply_extended_sgr ~(default : ansi_state) state codes =
  match codes with
  | 38 :: 5 :: n :: tl ->
      let fg = color256 n in
      List.fold_left (apply_sgr_code ~default) {state with fg} tl
  | 48 :: 5 :: n :: tl ->
      let bg = color256 n in
      List.fold_left (apply_sgr_code ~default) {state with bg} tl
  | lst -> List.fold_left (apply_sgr_code ~default) state lst

let parse_ansi_segments ~(default : ansi_state) (s : string) =
  let len = String.length s in
  let buf = Buffer.create 64 in
  let add_chunk acc state =
    if Buffer.length buf = 0 then acc
    else
      let chunk = Buffer.contents buf in
      Buffer.clear buf ;
      (state, chunk) :: acc
  in
  let rec loop i acc state =
    if i >= len then List.rev (add_chunk acc state)
    else
      match s.[i] with
      | '\027' when i + 1 < len && s.[i + 1] = '[' ->
          let j = ref (i + 2) in
          while !j < len && s.[!j] <> 'm' do
            incr j
          done ;
          if !j >= len then (
            Buffer.add_char buf s.[i] ;
            loop (i + 1) acc state)
          else
            let codes_str = String.sub s (i + 2) (!j - (i + 2)) in
            let codes =
              codes_str
              |> String.split_on_char ';'
              |> List.filter_map (fun c ->
                     match int_of_string_opt (String.trim c) with
                     | Some v -> Some v
                     | None -> None)
            in
            let state' = apply_extended_sgr ~default state codes in
            let acc' = add_chunk acc state in
            loop (!j + 1) acc' state'
      | '\r' -> loop (i + 1) acc state
      | c ->
          Buffer.add_char buf c ;
          loop (i + 1) acc state
  in
  loop 0 [] {fg = default.fg; bg = default.bg}

let strip_ansi_to_text ~default s =
  parse_ansi_segments ~default s |> List.map snd |> String.concat ""

let create_renderer window =
  match
    Sdl.create_renderer
      ~index:(-1)
      ~flags:Sdl.Renderer.(accelerated + presentvsync + targettexture)
      window
  with
  | Error (`Msg e) -> sdl_fail "create_renderer" e
  | Ok r -> r

let create_window title ~w ~h =
  match
    Sdl.create_window
      ~w
      ~h
      title
      Sdl.Window.(shown + resizable + allow_highdpi)
  with
  | Error (`Msg e) -> sdl_fail "create_window" e
  | Ok w -> w

let size_from_window ~char_w ~char_h ~scale window =
  let w, h = Sdl.get_window_size window in
  let cw = max 1 (int_of_float (float char_w *. scale)) in
  let ch = max 1 (int_of_float (float char_h *. scale)) in
  let cols = max 40 (w / cw) in
  let rows = max 12 (h / ch) in
  {rows; cols}

let render_lines renderer font ~(fg : color) ~(bg : color) ~(char_w : int)
    ~(char_h : int) ?(clear = true) ?(offset = 0) ?(present = true) lines =
  (* Clear background first when requested. *)
  (if clear then
   match Sdl.set_render_draw_color renderer bg.r bg.g bg.b bg.a with
   | Error (`Msg e) -> sdl_fail "set_render_draw_color" e
   | Ok () -> (
       match Sdl.render_clear renderer with
       | Error (`Msg e) -> sdl_fail "render_clear" e
       | Ok () -> ())
  else ()) ;
  let rec render_row y = function
    | [] -> ()
    | line :: rest ->
        let default_state : ansi_state = {fg; bg} in
        let padded =
          if offset <= 0 then line else String.make offset ' ' ^ line
        in
        let segments =
          parse_ansi_segments ~default:default_state padded
          |> List.map (fun ((st : ansi_state), txt) -> ((st.fg, st.bg), txt))
        in
        let rec render_seg x = function
          | [] -> ()
          | ((_, _), txt) :: tail when String.length txt = 0 -> render_seg x tail
          | ((fg_color, bg_color), txt) :: tail -> (
              (* Draw background block if non-default. *)
              let txt_w, txt_h =
                match Ttf.size_utf8 font txt with
                | Ok (w, h) -> (max w char_w, max h char_h)
                | Error _ -> (String.length txt * char_w, char_h)
              in
              if bg_color <> bg then (
                let _ =
                  Sdl.set_render_draw_color renderer bg_color.r bg_color.g
                    bg_color.b bg_color.a
                in
                let rect = Sdl.Rect.create ~x:(12 + x) ~y ~w:txt_w ~h:txt_h in
                ignore (Sdl.render_fill_rect renderer (Some rect)) ;
                (* Restore default draw color for subsequent clears. *)
                ignore
                  (Sdl.set_render_draw_color renderer bg.r bg.g bg.b bg.a)) ;
              match
                Ttf.render_utf8_blended font txt (color_to_sdl fg_color)
              with
              | Error (`Msg e) ->
                  (try
                     Sdl.log "render_utf8_blended failed for '%s': %s" txt e
                   with _ -> ()) ;
                  render_seg x tail
              | Ok surface -> (
                  let texture =
                    match Sdl.create_texture_from_surface renderer surface with
                    | Error (`Msg e) ->
                        Sdl.free_surface surface ;
                        sdl_fail "create_texture_from_surface" e
                    | Ok t -> t
                  in
                  (match Sdl.query_texture texture with
                  | Error (`Msg e) ->
                      Sdl.destroy_texture texture ;
                      Sdl.free_surface surface ;
                      sdl_fail "query_texture" e
                  | Ok (_, _, (w, h)) ->
                      let dst = Sdl.Rect.create ~x:(12 + x) ~y ~w ~h in
                      ignore (Sdl.render_copy renderer ~dst texture) ;
                      Sdl.destroy_texture texture ;
                      Sdl.free_surface surface ;
                      render_seg (x + txt_w) tail)))
        in
        render_seg 0 segments ;
        render_row (y + char_h) rest
  in
  render_row 10 lines ;
  if present then ignore (Sdl.render_present renderer) else ()

let shift_lines lines dx =
  List.map
    (fun line ->
      if dx >= 0 then String.make dx ' ' ^ line
      else
        let drop = min (String.length line) (-dx) in
        if drop >= String.length line then ""
        else String.sub line drop (String.length line - drop))
    lines

let draw_background renderer cfg _char_w char_h =
  if cfg.gradient then (
    let w, h =
      match Sdl.get_renderer_output_size renderer with
      | Ok (w, h) -> (w, h)
      | Error (`Msg e) -> sdl_fail "get_renderer_output_size" e
    in
    let steps =
      max 1
        (int_of_float
           (float h /. max 1.0 (float char_h *. cfg.scale)))
    in
    let lerp a b t =
      let a = float_of_int a in
      let b = float_of_int b in
      int_of_float (a +. (b -. a) *. t)
    in
    let target =
      let dim v = max 0 (v - 25) in
      {r = dim cfg.bg.r; g = dim cfg.bg.g; b = dim cfg.bg.b; a = cfg.bg.a}
    in
    for i = 0 to steps do
      let t = float_of_int i /. float_of_int (max 1 steps) in
      let col =
        {
          r = lerp cfg.bg.r target.r t;
          g = lerp cfg.bg.g target.g t;
          b = lerp cfg.bg.b target.b t;
          a = cfg.bg.a;
        }
      in
      ignore (Sdl.set_render_draw_color renderer col.r col.g col.b col.a) ;
      let y = int_of_float (float (i * char_h) *. cfg.scale) in
      ignore
        (Sdl.render_fill_rect
           renderer
           (Some
              (Sdl.Rect.create
                 ~x:0
                 ~y
                 ~w:(int_of_float (float w /. cfg.scale))
                 ~h:(int_of_float (float char_h *. cfg.scale)))))
    done)
  else
    match Sdl.set_render_draw_color renderer cfg.bg.r cfg.bg.g cfg.bg.b cfg.bg.a with
    | Ok () -> ignore (Sdl.render_clear renderer)
    | Error (`Msg e) -> sdl_fail "render_clear" e

let transition_slide renderer font cfg char_w char_h ~from_lines ~to_lines ~size
    =
  let steps = 24 in
  let width = size.cols in
  for step = 0 to steps do
    draw_background renderer cfg char_w char_h ;
    let off_old = - (step * width / steps) in
    let off_new = width - (step * width / steps) in
    render_lines renderer font ~fg:cfg.fg ~bg:cfg.bg ~char_w ~char_h
      ~clear:false ~offset:off_old ~present:false from_lines ;
    render_lines renderer font ~fg:cfg.fg ~bg:cfg.bg ~char_w ~char_h
      ~clear:false ~offset:off_new ~present:false to_lines ;
    ignore (Sdl.render_present renderer) ;
    Sdl.delay 16l
  done

let transition_fade renderer font cfg char_w char_h ~from_lines ~to_lines ~size
    =
  let steps = 24 in
  let bg = cfg.bg in
  (* Two-stage fade to reduce flicker: fade-out, then fade-in. *)
  let blend_rect =
    Sdl.Rect.create
      ~x:0
      ~y:0
      ~w:(size.cols * char_w)
      ~h:(size.rows * char_h)
  in
  let with_overlay alpha lines =
    draw_background renderer cfg char_w char_h ;
    render_lines renderer font ~fg:cfg.fg ~bg:cfg.bg ~char_w ~char_h
      ~clear:false ~present:false lines ;
    ignore (Sdl.set_render_draw_blend_mode renderer Sdl.Blend.mode_blend) ;
    ignore (Sdl.set_render_draw_color renderer bg.r bg.g bg.b alpha) ;
    ignore (Sdl.render_fill_rect renderer (Some blend_rect)) ;
    ignore (Sdl.render_present renderer) ;
    Sdl.delay 12l
  in
  for step = 0 to steps do
    let alpha = int_of_float (255. *. (float step /. float steps)) in
    with_overlay alpha from_lines
  done ;
  for step = 0 to steps do
    let alpha =
      255 - int_of_float (255. *. (float step /. float steps))
    in
    with_overlay alpha to_lines
  done

let transition_fade_soft renderer font cfg char_w char_h ~from_lines ~to_lines
    ~size =
  let steps = 32 in
  let bg = cfg.bg in
  let blend_rect =
    Sdl.Rect.create
      ~x:0
      ~y:0
      ~w:(size.cols * char_w)
      ~h:(size.rows * char_h)
  in
  let phase lines alpha =
    draw_background renderer cfg char_w char_h ;
    render_lines renderer font ~fg:cfg.fg ~bg:cfg.bg ~char_w ~char_h
      ~clear:false ~present:false lines ;
    ignore (Sdl.set_render_draw_blend_mode renderer Sdl.Blend.mode_blend) ;
    ignore (Sdl.set_render_draw_color renderer bg.r bg.g bg.b alpha) ;
    ignore (Sdl.render_fill_rect renderer (Some blend_rect)) ;
    ignore (Sdl.render_present renderer) ;
    Sdl.delay 14l
  in
  for step = 0 to steps do
    let t = float step /. float steps in
    let alpha = int_of_float (255. *. (t *. t)) in
    phase from_lines alpha
  done ;
  for step = 0 to steps do
    let t = float step /. float steps in
    let alpha = int_of_float (255. *. (1. -. (t *. t))) in
    phase to_lines alpha
  done

let transition_explode renderer font cfg char_w char_h ~from_lines ~to_lines
    ~size =
  let _ = size in
  let steps = 30 in
  let dt = 0.018 in
  let gravity = 300.0 in
  let max_particles = 2200 in
  let particles =
    let acc = ref [] in
    let count = ref 0 in
    List.iteri
      (fun row line ->
        String.iteri
          (fun col ch ->
            if !count < max_particles && ch <> ' ' then (
              incr count ;
              let x0 =
                float_of_int (col * char_w + (char_w / 2))
              in
              let y0 =
                float_of_int (row * char_h + (char_h / 2))
              in
              let angle = Random.float (2.0 *. Float.pi) in
              let speed = 140.0 +. (Random.float 260.0) in
              let vx = speed *. cos angle in
              let vy = (speed *. sin angle) -. 40.0 in
              let tint =
                let jitter v =
                  let off = Random.int 30 in
                  max 0 (min 255 (v + off))
                in
                {cfg.fg with r = jitter cfg.fg.r; g = jitter cfg.fg.g; b = jitter cfg.fg.b}
              in
              acc :=
                (ref x0, ref y0, vx, vy, tint)
                :: !acc))
          line)
      from_lines ;
    !acc
  in
  let draw_particles t =
    ignore (Sdl.set_render_draw_blend_mode renderer Sdl.Blend.mode_blend) ;
    List.iter
      (fun (x, y, vx, vy, c) ->
        let alpha =
          int_of_float (255. *. max 0.0 (1.0 -. t))
        in
        let new_vy = vy +. (gravity *. dt *. float steps /. float steps) in
        x := !x +. (vx *. dt) ;
        y := !y +. (new_vy *. dt) ;
        ignore (Sdl.set_render_draw_color renderer c.r c.g c.b alpha) ;
        let rect =
          Sdl.Rect.create
            ~x:(int_of_float !x)
            ~y:(int_of_float !y)
            ~w:(max 1 (char_w / 2))
            ~h:(max 1 (char_h / 2))
        in
        ignore (Sdl.render_fill_rect renderer (Some rect)))
      particles
  in
  for step = 0 to steps do
    let t = float step /. float steps in
    draw_background renderer cfg char_w char_h ;
    if step < steps / 3 then
      render_lines renderer font ~fg:cfg.fg ~bg:cfg.bg ~char_w ~char_h
        ~clear:false ~present:false from_lines ;
    draw_particles t ;
    if step >= steps / 2 then
      render_lines renderer font ~fg:cfg.fg ~bg:cfg.bg ~char_w ~char_h
        ~clear:false ~present:false to_lines ;
    ignore (Sdl.render_present renderer) ;
    Sdl.delay 14l
  done

let pick_random_transition () =
  let options = [ `Slide; `Fade; `Explode ] in
  let idx = Random.int (List.length options) in
  List.nth options idx

let perform_transition renderer font cfg char_w char_h ~from_lines ~to_lines
    ~size =
  let kind =
    match cfg.transition with
    | `Random -> pick_random_transition ()
    | other -> other
  in
  match kind with
  | `Slide ->
      transition_slide renderer font cfg char_w char_h ~from_lines ~to_lines
        ~size
  | `Fade ->
      let choose_soft = Random.int 2 = 0 in
      if choose_soft then
        transition_fade_soft renderer font cfg char_w char_h ~from_lines
          ~to_lines ~size
      else
        transition_fade renderer font cfg char_w char_h ~from_lines ~to_lines
          ~size
  | `Explode ->
      transition_explode renderer font cfg char_w char_h ~from_lines ~to_lines
        ~size
  | `Random -> ()
  | `None -> ()

let string_of_event_text e =
  match Sdl.Event.(get e typ |> enum) with
  | `Text_input -> Some Sdl.Event.(get e text_input_text)
  | _ -> None

let keyname_of_scancode sc =
  match Sdl.Scancode.enum sc with
  | `Return -> Some "Enter"
  | `Up -> Some "Up"
  | `Down -> Some "Down"
  | `Left -> Some "Left"
  | `Right -> Some "Right"
  | `Tab -> Some "NextPage"
  | `Backspace -> Some "Backspace"
  | `Escape -> Some "Esc"
  | `Delete -> Some "Delete"
  | `Space -> Some " "
  | `A -> Some "a"
  | `B -> Some "b"
  | `C -> Some "c"
  | `D -> Some "d"
  | `E -> Some "e"
  | `F -> Some "f"
  | `G -> Some "g"
  | `H -> Some "h"
  | `I -> Some "i"
  | `J -> Some "j"
  | `K -> Some "k"
  | `L -> Some "l"
  | `M -> Some "m"
  | `N -> Some "n"
  | `O -> Some "o"
  | `P -> Some "p"
  | `Q -> Some "q"
  | `R -> Some "r"
  | `S -> Some "s"
  | `T -> Some "t"
  | `U -> Some "u"
  | `V -> Some "v"
  | `W -> Some "w"
  | `X -> Some "x"
  | `Y -> Some "y"
  | `Z -> Some "z"
  | _ -> None

type next_action =
  | Refresh
  | Quit
  | Key of string

let poll_event ~timeout_ms ~on_resize =
  let e = Sdl.Event.create () in
  let start = Sdl.get_ticks () in
  let rec loop () =
    match Sdl.poll_event (Some e) with
    | true -> (
        match Sdl.Event.(get e typ |> enum) with
        | `Quit -> Quit
        | `Window_event ->
            on_resize () ;
            Refresh
        | `Key_down -> (
            let repeat = Sdl.Event.get e Sdl.Event.keyboard_repeat <> 0 in
            match
              Sdl.Event.(get e keyboard_scancode |> keyname_of_scancode)
            with
            | Some k ->
                (* Treat repeat as a second press only for navigation keys; drop
                   repeats for Esc/Enter/Space to avoid double firing. *)
                let is_nav =
                  match k with
                  | "Up" | "Down" | "Left" | "Right" | "Tab" | "NextPage" -> true
                  | _ -> false
                in
                if repeat && not is_nav then loop () else Key k
            | None -> loop ())
        | `Text_input -> (
            match string_of_event_text e with
            | Some " " -> loop ()
            | Some txt -> Key txt
            | None -> loop ())
        | _ -> loop ())
    | false ->
        let elapsed_ms = Int32.(to_int (sub (Sdl.get_ticks ()) start)) in
        if elapsed_ms > timeout_ms then Refresh
        else (
          Sdl.delay 12l ;
          loop ())
  in
  loop ()

let render_page (type s) (module P : PAGE_SIG with type state = s) st size =
  let base = P.view st ~focus:true ~size in
  let with_modal =
    match Modal_renderer.render_overlay ~cols:(Some size.cols) ~base ~rows:size.rows () with
    | Some overlay -> overlay
    | None -> base
  in
  with_modal

let run_with_sdl (initial_page : (module PAGE_SIG)) (cfg : config) :
    [`Quit | `SwitchTo of string] =
  let available = true in
  ignore available ;
  with_sdl @@ fun () ->
  Miaou_widgets_display.Widgets.set_backend `Sdl ;
  let font_path =
    match pick_font_path cfg with
    | Ok p -> p
    | Error msg -> failwith msg
  in
  let font =
    match Ttf.open_font font_path cfg.font_size with
    | Error (`Msg e) ->
        sdl_fail
          "open_font"
          (Printf.sprintf "font=%s: %s" font_path e)
    | Ok f -> f
  in
  let char_w, char_h =
    match Ttf.size_utf8 font "M" with
    | Error (`Msg e) -> sdl_fail "size_utf8" e
    | Ok (w, h) -> (max 8 w, max 12 h)
  in
  let win =
    create_window
      cfg.window_title
      ~w:(80 * char_w)
      ~h:(30 * char_h)
  in
  let renderer = create_renderer win in
  ignore (Sdl.render_set_scale renderer cfg.scale cfg.scale) ;
  ignore (Sdl.start_text_input ()) ;
  let size_ref = ref (size_from_window ~char_w ~char_h ~scale:cfg.scale win) in
  let update_size () =
    let s = size_from_window ~char_w ~char_h ~scale:cfg.scale win in
    size_ref := s ;
    Modal_manager.set_current_size s.rows s.cols
  in
  update_size () ;

  let render_and_draw (type s) (module P : PAGE_SIG with type state = s)
      (st : s) =
    let size = !size_ref in
    let text = render_page (module P) st size in
    let default_state : ansi_state = {fg = cfg.fg; bg = cfg.bg} in
    let clean_text = strip_ansi_to_text ~default:default_state text in
    Capture.record_frame ~rows:size.rows ~cols:size.cols clean_text ;
    draw_background renderer cfg char_w char_h ;
    render_lines renderer font ~fg:cfg.fg ~bg:cfg.bg ~char_w ~char_h
      ~clear:false ~present:false (String.split_on_char '\n' text) ;
    ignore (Sdl.render_present renderer)
  in

  let rec loop :
      type s.
      (module PAGE_SIG with type state = s) ->
      s ->
      [`Quit | `SwitchTo of string] =
   fun (module P : PAGE_SIG with type state = s) (st : s) ->
    render_and_draw (module P) st ;
    match poll_event ~timeout_ms:120 ~on_resize:update_size with
    | Quit -> `Quit
    | Refresh ->
        let st' = P.refresh st in
        (match P.next_page st' with
        | Some "__QUIT__" -> `Quit
        | Some name -> (
            match Registry.find name with
            | Some (module Next : PAGE_SIG) ->
                let st_to = Next.init () in
                let size = !size_ref in
                let from_text = render_page (module P) st size in
                let to_text = render_page (module Next) st_to size in
                perform_transition renderer font cfg char_w char_h
                  ~from_lines:(String.split_on_char '\n' from_text)
                  ~to_lines:(String.split_on_char '\n' to_text)
                  ~size ;
                loop (module Next) st_to
            | None -> `Quit)
        | None -> loop (module P) st')
    | Key k ->
        (match Logger_capability.get () with
        | Some logger ->
            logger.logf Debug (Printf.sprintf "SDL driver key=%s" k)
        | None -> ()) ;
        let forced_switch =
          String.length k > 11
          && String.sub k 0 11 = "__SWITCH__:"
          && Sys.getenv_opt "MIAOU_TEST_ALLOW_FORCED_SWITCH" = Some "1"
        in
        if not forced_switch then Capture.record_keystroke k ;
        if forced_switch then
          let name = String.sub k 11 (String.length k - 11) in
          match Registry.find name with
          | Some (module Next : PAGE_SIG) ->
              let st_to = Next.init () in
              let size = !size_ref in
              let from_text = render_page (module P) st size in
              let to_text = render_page (module Next) st_to size in
              perform_transition renderer font cfg char_w char_h
                ~from_lines:(String.split_on_char '\n' from_text)
                ~to_lines:(String.split_on_char '\n' to_text)
                ~size ;
              loop (module Next) st_to
          | None -> `Quit
        else
          let st' =
            if Modal_manager.has_active () then (
              Modal_manager.handle_key k ;
              st)
            else
              match k with
              | "Up" -> P.move st (-1)
              | "Down" -> P.move st 1
              | "Enter" -> P.enter st
              | "q" | "Q" -> st
              | _ -> P.handle_key st k ~size:!size_ref
          in
          render_and_draw (module P) st' ;
          if k = "q" || k = "Q" then `Quit
          else
            match P.next_page st' with
            | Some "__QUIT__" -> `Quit
            | Some name -> (
                match Registry.find name with
                | Some (module Next : PAGE_SIG) ->
                    let st_to = Next.init () in
                    let size = !size_ref in
                    let from_text = render_page (module P) st' size in
                    let to_text = render_page (module Next) st_to size in
                    perform_transition renderer font cfg char_w char_h
                      ~from_lines:(String.split_on_char '\n' from_text)
                      ~to_lines:(String.split_on_char '\n' to_text)
                      ~size ;
                    loop (module Next) st_to
                | None -> `Quit)
            | None -> loop (module P) st'
  in
  Fun.protect
    ~finally:(fun () ->
      Miaou_widgets_display.Widgets.set_backend `Terminal ;
      Ttf.close_font font ;
      Sdl.destroy_renderer renderer ;
      Sdl.destroy_window win)
    (fun () ->
      let module P0 : PAGE_SIG = (val initial_page) in
      loop (module P0) (P0.init ()))

let run ?config initial_page =
  let cfg = Option.value ~default:default_config config in
  run_with_sdl initial_page cfg
