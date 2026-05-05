(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

module Globe = Miaou_widgets_display.Globe_widget
module FB = Miaou_widgets_display.Framebuffer_widget
module Caps = Miaou_widgets_display.Terminal_caps
module W = Miaou_widgets_display.Widgets

type layout = Compact | Standard | Wide

let pick_layout ~size =
  let cols = size.LTerm_geom.cols in
  let rows = size.LTerm_geom.rows in
  if cols < 80 || rows < 24 then Compact
  else if cols >= 140 then Wide
  else Standard

let too_small_msg = "Resize terminal — needs at least 40×15"

(* ---------- visible-width-aware centring helpers ---------- *)

let visible_width s =
  let n = String.length s in
  let i = ref 0 in
  let cells = ref 0 in
  while !i < n do
    let c = Char.code s.[!i] in
    if c = 0x1b && !i + 1 < n && s.[!i + 1] = '[' then begin
      i := !i + 2 ;
      while !i < n && (Char.code s.[!i] < 0x40 || Char.code s.[!i] > 0x7E) do
        incr i
      done ;
      if !i < n then incr i
    end
    else if c < 0x80 then begin
      incr cells ;
      incr i
    end
    else if c < 0xC0 then incr i
    else if c < 0xE0 then begin
      incr cells ;
      i := !i + 2
    end
    else if c < 0xF0 then begin
      incr cells ;
      i := !i + 3
    end
    else begin
      incr cells ;
      i := !i + 4
    end
  done ;
  !cells

let centre line ~width =
  let len = visible_width line in
  if len >= width then line else String.make ((width - len) / 2) ' ' ^ line

let pad_left s ~n = if n <= 0 then s else String.make n ' ' ^ s

(* ---------- map geometry (shared by render + mouse handler) ---------- *)

(* For a given (cols, rows) terminal area we choose the largest map sub-area
   that has equirectangular 2:1 pixel aspect.

   With sixel/octant the pixel-per-cell ratio is roughly 1:2 (cells are
   ~1 unit wide × 2 tall). To get 2:1 pixel aspect from cell-grid (W,H) we
   want pixel_w = 2 * pixel_h ⇒ W * px_x = 2 * H * px_y ⇒ W/H = 2 * py/px.

   For sixel (8,16): W/H = 4
   For octant (2,4): W/H = 4
   For sextant (2,3): W/H = 3
   For half_block (1,2): W/H = 4
   For braille (2,4): W/H = 4

   Use 4:1 cell ratio as default — correct for every mode except sextant. *)

let cell_aspect_ratio () =
  (* Match the chosen map_pixel_mode (set further below). For octant/half_block/
     braille/sixel the px-per-cell ratio is 1:2 so a 4:1 cell ratio gives 2:1
     pixel aspect. For sextant (2:3 px) use 3:1. *)
  match Sys.getenv_opt "MIAOU_GEO_QUIZ_PIXEL_MODE" with
  | Some "sextant" -> 3
  | _ -> 4

(* Cap the map size to keep per-frame encoding bounded. On huge terminals
   we don't need a 1000×300-cell map — the bg-build (60K coastline segments)
   and the per-frame block-encoding both scale with the pixel count, so an
   uncapped map freezes the UI on first render. 240×60 cells is plenty for
   continent shapes at sextant resolution. *)
let map_max_cols = 240

let map_max_rows = 60

let map_geometry ~size =
  let cols = size.LTerm_geom.cols in
  let rows = size.LTerm_geom.rows in
  let chrome =
    4
    (* 1 row prompt at top, ~3 rows score+footer at bottom *)
  in
  let avail_rows = max 6 (min map_max_rows (rows - chrome)) in
  let avail_cols = min map_max_cols cols in
  let want_ratio = cell_aspect_ratio () in
  let map_cols, map_rows =
    if avail_cols >= avail_rows * want_ratio then
      (avail_rows * want_ratio, avail_rows)
    else
      let mr = avail_cols / want_ratio in
      let mr = max 4 mr in
      (mr * want_ratio, mr)
  in
  let map_cols = min map_cols avail_cols in
  let map_rows = min map_rows avail_rows in
  let origin_col = (cols - map_cols) / 2 in
  let top_row =
    1
    (* under the 1-line prompt *)
  in
  (top_row, origin_col, map_cols, map_rows)

let cell_to_latlon ~map_cols ~map_rows ~map_col ~map_row =
  let lon =
    ((float_of_int map_col +. 0.5) /. float_of_int map_cols *. 360.0) -. 180.0
  in
  let lat =
    90.0 -. ((float_of_int map_row +. 0.5) /. float_of_int map_rows *. 180.0)
  in
  (lat, lon)

(* ---------- pixel-buffer drawing helpers ---------- *)

let put_pixel bytes ~px_w ~px_h ~x ~y ~r ~g ~b =
  if x >= 0 && x < px_w && y >= 0 && y < px_h then begin
    let off = ((y * px_w) + x) * 3 in
    Bytes.set bytes off (Char.chr r) ;
    Bytes.set bytes (off + 1) (Char.chr g) ;
    Bytes.set bytes (off + 2) (Char.chr b)
  end

let draw_line_px bytes ~px_w ~px_h ~x0 ~y0 ~x1 ~y1 ~r ~g ~b =
  let dx = abs (x1 - x0) in
  let dy = -abs (y1 - y0) in
  let sx = if x0 < x1 then 1 else -1 in
  let sy = if y0 < y1 then 1 else -1 in
  let err = ref (dx + dy) in
  let x = ref x0 in
  let y = ref y0 in
  let continue = ref true in
  while !continue do
    put_pixel bytes ~px_w ~px_h ~x:!x ~y:!y ~r ~g ~b ;
    if !x = x1 && !y = y1 then continue := false
    else begin
      let e2 = 2 * !err in
      if e2 >= dy then begin
        err := !err + dy ;
        x := !x + sx
      end ;
      if e2 <= dx then begin
        err := !err + dx ;
        y := !y + sy
      end
    end
  done

let draw_thick_line_px bytes ~px_w ~px_h ~x0 ~y0 ~x1 ~y1 ~thickness ~r ~g ~b =
  for dx = 0 to thickness - 1 do
    for dy = 0 to thickness - 1 do
      draw_line_px
        bytes
        ~px_w
        ~px_h
        ~x0:(x0 + dx)
        ~y0:(y0 + dy)
        ~x1:(x1 + dx)
        ~y1:(y1 + dy)
        ~r
        ~g
        ~b
    done
  done

let draw_pin_px bytes ~px_w ~px_h ~cx ~cy ~r ~g ~b ~size =
  (* Draw a "+" with a small dot in the centre — readable but not occluding. *)
  let arm = size in
  for d = -arm to arm do
    put_pixel bytes ~px_w ~px_h ~x:(cx + d) ~y:cy ~r ~g ~b ;
    put_pixel bytes ~px_w ~px_h ~x:cx ~y:(cy + d) ~r ~g ~b
  done ;
  (* small filled box around the centre for visibility *)
  for dx = -1 to 1 do
    for dy = -1 to 1 do
      put_pixel bytes ~px_w ~px_h ~x:(cx + dx) ~y:(cy + dy) ~r:255 ~g:255 ~b:255
    done
  done ;
  ignore (r, g, b)

(* ---------- the map renderer ---------- *)

let mode_px_per_cell mode =
  match mode with
  | Caps.Sixel -> (8, 16)
  | Caps.Octant -> (2, 4)
  | Caps.Sextant -> (2, 3)
  | Caps.Half_block -> (1, 2)
  | Caps.Braille -> (2, 4)

let lat_to_py ~px_h lat =
  let f = (90.0 -. lat) /. 180.0 in
  let y = int_of_float (f *. float_of_int px_h) in
  max 0 (min (px_h - 1) y)

let lon_to_px ~px_w lon =
  let f = (lon +. 180.0) /. 360.0 in
  let x = int_of_float (f *. float_of_int px_w) in
  max 0 (min (px_w - 1) x)

(* Inset the result by `origin_col` spaces on every line, returning a
   newline-separated string. *)
let indent_lines s ~n =
  if n <= 0 then s
  else
    let parts = String.split_on_char '\n' s in
    String.concat "\n" (List.map (pad_left ~n) parts)

(* Build the static background (ocean fill + graticule + coastline) once
   per (px_w, px_h). Cached on the game state so per-frame rendering only
   has to memcpy + overlay pins. *)
let build_map_background ~px_w ~px_h ~mode =
  let bytes = Bytes.make (3 * px_w * px_h) '\000' in
  (* Land/sea fill from the rasterised Natural Earth mask. Ocean is atlas
     navy (18,38,75); land is sand (210,180,120). The coastline overlay
     drawn below adds the boundary in a darker tone. *)
  for py = 0 to px_h - 1 do
    let lat =
      90.0 -. ((float_of_int py +. 0.5) /. float_of_int px_h *. 180.0)
    in
    let row_base = py * px_w * 3 in
    for px = 0 to px_w - 1 do
      let lon =
        ((float_of_int px +. 0.5) /. float_of_int px_w *. 360.0) -. 180.0
      in
      let off = row_base + (px * 3) in
      if Landmask.is_land ~lat ~lon then begin
        Bytes.set bytes off (Char.chr 210) ;
        Bytes.set bytes (off + 1) (Char.chr 180) ;
        Bytes.set bytes (off + 2) (Char.chr 120)
      end
      else begin
        Bytes.set bytes off (Char.chr 18) ;
        Bytes.set bytes (off + 1) (Char.chr 38) ;
        Bytes.set bytes (off + 2) (Char.chr 75)
      end
    done
  done ;
  (* Latitude graticule every 30°: faint dotted horizontal lines. *)
  let lat = ref (-60) in
  while !lat <= 60 do
    let y = lat_to_py ~px_h (float_of_int !lat) in
    let i = ref 0 in
    while !i < px_w do
      put_pixel bytes ~px_w ~px_h ~x:!i ~y ~r:50 ~g:75 ~b:120 ;
      i := !i + 8
    done ;
    lat := !lat + 30
  done ;
  (* Longitude graticule every 60° *)
  let lon = ref (-120) in
  while !lon <= 120 do
    let x = lon_to_px ~px_w (float_of_int !lon) in
    let j = ref 0 in
    while !j < px_h do
      put_pixel bytes ~px_w ~px_h ~x ~y:!j ~r:50 ~g:75 ~b:120 ;
      j := !j + 8
    done ;
    lon := !lon + 60
  done ;
  (* Coastline — sand/gold against the navy ocean. *)
  let segs = Lazy.force Coastline.segments in
  let coast_r, coast_g, coast_b = (235, 205, 130) in
  let thickness = match mode with Caps.Sixel -> 2 | _ -> 1 in
  Array.iter
    (fun seg ->
      let m = Array.length seg in
      for i = 0 to m - 2 do
        let lat1, lon1 = seg.(i) in
        let lat2, lon2 = seg.(i + 1) in
        if Float.abs (lon1 -. lon2) < 90.0 then begin
          let x0 = lon_to_px ~px_w lon1 in
          let y0 = lat_to_py ~px_h lat1 in
          let x1 = lon_to_px ~px_w lon2 in
          let y1 = lat_to_py ~px_h lat2 in
          draw_thick_line_px
            bytes
            ~px_w
            ~px_h
            ~x0
            ~y0
            ~x1
            ~y1
            ~thickness
            ~r:coast_r
            ~g:coast_g
            ~b:coast_b
        end
      done)
    segs ;
  bytes

(* Force a fast, widely-supported pixel mode for the world map. We default
   to Octant (2x4 sub-cells, 256-color) because the matrix driver's ANSI
   parser only understands 256-color SGR codes, not truecolor — sextant
   would render glyphs but lose the ocean/coast colors. Octant is denser
   than sextant anyway. Override with MIAOU_GEO_QUIZ_PIXEL_MODE=sixel|sextant|... *)
let map_pixel_mode () =
  match Sys.getenv_opt "MIAOU_GEO_QUIZ_PIXEL_MODE" with
  | Some "sixel" -> Caps.Sixel
  | Some "sextant" -> Caps.Sextant
  | Some "half_block" -> Caps.Half_block
  | Some "braille" -> Caps.Braille
  | _ -> Caps.Octant

let render_map_block (s : Game.state) ~map_cols ~map_rows ~cursor_lat
    ~cursor_lon ~truth =
  let mode = map_pixel_mode () in
  let px_x, px_y = mode_px_per_cell mode in
  let px_w = map_cols * px_x in
  let px_h = map_rows * px_y in
  let truth_key =
    match truth with
    | None -> "_"
    | Some (la, lo) -> Printf.sprintf "%.4f,%.4f" la lo
  in
  let cache_key =
    Printf.sprintf
      "%dx%d|%.4f,%.4f|%s"
      px_w
      px_h
      cursor_lat
      cursor_lon
      truth_key
  in
  let last_key, last_out = !(s.Game.map_render_cache) in
  if cache_key = last_key && last_key <> "" then last_out
  else if px_w <= 0 || px_h <= 0 then ""
  else begin
    let cached_bg, cached_w, cached_h = !(s.Game.map_bg_cache) in
    let bg =
      if cached_w = px_w && cached_h = px_h then cached_bg
      else
        let b = build_map_background ~px_w ~px_h ~mode in
        s.Game.map_bg_cache := (b, px_w, px_h) ;
        b
    in
    (* Per-frame: start from the cached background, overlay pins. *)
    let bytes = Bytes.copy bg in
    (match truth with
    | None -> ()
    | Some (lat, lon) ->
        let cx = lon_to_px ~px_w lon in
        let cy = lat_to_py ~px_h lat in
        draw_pin_px bytes ~px_w ~px_h ~cx ~cy ~r:255 ~g:60 ~b:70 ~size:8) ;
    let cx = lon_to_px ~px_w cursor_lon in
    let cy = lat_to_py ~px_h cursor_lat in
    draw_pin_px bytes ~px_w ~px_h ~cx ~cy ~r:90 ~g:240 ~b:255 ~size:6 ;
    FB.blit s.Game.map_fb ~src:bytes ~width:px_w ~height:px_h ;
    let out =
      FB.render_with_mode s.Game.map_fb ~mode ~cols:map_cols ~rows:map_rows
    in
    s.Game.map_render_cache := (cache_key, out) ;
    out
  end

(* ---------- Menu mode (Globe + chrome) ---------- *)

let render_menu (s : Game.state) ~size =
  let cols = size.LTerm_geom.cols in
  let rows = size.LTerm_geom.rows in
  let layout = pick_layout ~size in
  let globe_max_rows = 40 in
  let globe_rows =
    match layout with
    | Compact -> max 8 (rows / 2)
    | Standard -> max 12 (rows - 8)
    | Wide -> rows - 8
  in
  let globe_rows = min globe_max_rows globe_rows in
  let globe_cols = globe_rows * 2 in
  let globe_cols = min cols globe_cols in
  let globe_rows = max 5 (min (rows - 8) globe_rows) in
  let globe_cols = max 10 globe_cols in
  let globe_text = Globe.render s.globe ~cols:globe_cols ~rows:globe_rows in
  let title = W.themed_emphasis "MIAOU GEO QUIZ" in
  let subtitle = W.themed_muted "Place the prompted city on the world map" in
  let diff_label =
    Printf.sprintf
      "Difficulty: ◀ %s ▶  (Left/Right to change)"
      (Cities.tier_label s.difficulty)
  in
  let diff_desc = W.themed_muted (Cities.tier_description s.difficulty) in
  let footer = W.themed_muted "Enter — start · t — tutorial · Esc — quit" in
  let globe_lines = String.split_on_char '\n' globe_text in
  let centred =
    List.map (fun l -> centre l ~width:cols) globe_lines |> String.concat "\n"
  in
  String.concat
    "\n"
    [
      "";
      centre title ~width:cols;
      centre subtitle ~width:cols;
      "";
      centred;
      "";
      centre diff_label ~width:cols;
      centre diff_desc ~width:cols;
      "";
      centre footer ~width:cols;
    ]

(* ---------- Round mode ---------- *)

let format_time_remaining ~elapsed ~deadline =
  let r = Float.max 0.0 (deadline -. elapsed) in
  Printf.sprintf "%2.0fs" r

let render_round (s : Game.state) ~size =
  let cols = size.LTerm_geom.cols in
  let _, origin_col, map_cols, map_rows = map_geometry ~size in
  let prompt =
    match s.current with
    | None -> "(no city)"
    | Some c ->
        let label =
          if s.difficulty <= 3 then Printf.sprintf "%s, %s" c.name c.country
          else c.name
        in
        Printf.sprintf
          "Round %d / %d — Place: %s"
          (s.round_idx + 1)
          s.num_rounds
          label
  in
  let elapsed_in_round = Game.now_elapsed () -. s.round_start in
  let time_str =
    format_time_remaining ~elapsed:elapsed_in_round ~deadline:s.round_deadline_s
  in
  let total = Game.total_score s in
  let hud =
    Printf.sprintf
      "Time: %s · Score: %d · Round %d/%d · Tier: %s · Click or Arrow keys to \
       move · Enter to lock in"
      time_str
      total
      (s.round_idx + 1)
      s.num_rounds
      (Cities.tier_label s.difficulty)
  in
  let map =
    render_map_block
      s
      ~map_cols
      ~map_rows
      ~cursor_lat:s.cursor_lat
      ~cursor_lon:s.cursor_lon
      ~truth:None
  in
  let map = indent_lines map ~n:origin_col in
  let header = centre (W.themed_emphasis prompt) ~width:cols in
  let hud_styled = centre (W.themed_muted hud) ~width:cols in
  String.concat "\n" [header; map; hud_styled]

(* ---------- Round end mode ---------- *)

let render_round_end (s : Game.state) ~size =
  let cols = size.LTerm_geom.cols in
  let _, origin_col, map_cols, map_rows = map_geometry ~size in
  let r = match s.results with [] -> assert false | r :: _ -> r in
  let truth = (r.city.lat, r.city.lon) in
  let map =
    render_map_block
      s
      ~map_cols
      ~map_rows
      ~cursor_lat:r.guess_lat
      ~cursor_lon:r.guess_lon
      ~truth:(Some truth)
  in
  let map = indent_lines map ~n:origin_col in
  let title =
    if r.timed_out then W.themed_warning "⏱  Time up!"
    else W.themed_emphasis "Round complete"
  in
  let label =
    if s.difficulty <= 3 then Printf.sprintf "%s, %s" r.city.name r.city.country
    else r.city.name
  in
  let line1 = Printf.sprintf "%s  →  %.0f km away" label r.distance_km in
  let line2 =
    Printf.sprintf
      "Distance: %d  Time bonus: %d  Round: %d  Total: %d"
      r.distance_score
      r.time_bonus
      r.total
      (Game.total_score s)
  in
  let footer =
    if s.round_idx + 1 >= s.num_rounds then
      W.themed_muted "Enter — final results · Esc — back to menu"
    else W.themed_muted "Enter — next round · Esc — back to menu"
  in
  String.concat
    "\n"
    [
      centre title ~width:cols;
      map;
      centre line1 ~width:cols;
      centre line2 ~width:cols;
      centre footer ~width:cols;
    ]

(* ---------- Game over mode ---------- *)

let render_game_over (s : Game.state) ~size =
  let cols = size.LTerm_geom.cols in
  let scores = List.rev_map (fun r -> r.Game.total) s.results in
  let title = W.themed_emphasis "Final results" in
  let total = Game.total_score s in
  let max_total = Game.max_total_score s in
  let summary =
    Printf.sprintf
      "Total: %d / %d  (Tier: %s, %d rounds)"
      total
      max_total
      (Cities.tier_label s.difficulty)
      s.num_rounds
  in
  let max_score =
    List.fold_left max 1 (List.map (fun r -> r.Game.total) s.results)
  in
  let bar_w = max 10 (cols - 30) in
  let repeat n s =
    let b = Buffer.create (n * String.length s) in
    for _ = 1 to n do
      Buffer.add_string b s
    done ;
    Buffer.contents b
  in
  let bar_lines =
    List.mapi
      (fun i sc ->
        let filled = sc * bar_w / max_score in
        let bar =
          W.themed_text (repeat filled "█")
          ^ W.themed_muted (repeat (bar_w - filled) "·")
        in
        Printf.sprintf "Round %2d  %s  %5d" (i + 1) bar sc)
      scores
  in
  let footer = W.themed_muted "Enter — main menu · Esc — back to launcher" in
  String.concat
    "\n"
    ([centre title ~width:cols; centre summary ~width:cols; ""]
    @ List.map (fun l -> centre l ~width:cols) bar_lines
    @ [""; centre footer ~width:cols])

(* ---------- entry ---------- *)

let render (s : Game.state) ~size =
  let cols = size.LTerm_geom.cols in
  let rows = size.LTerm_geom.rows in
  if cols < 40 || rows < 15 then too_small_msg
  else
    match s.mode with
    | Game.Menu -> render_menu s ~size
    | Game.Round -> render_round s ~size
    | Game.Round_end -> render_round_end s ~size
    | Game.Game_over -> render_game_over s ~size
