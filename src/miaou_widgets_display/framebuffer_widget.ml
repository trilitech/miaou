(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Mathias Bourgoin <mathias.bourgoin@atacama.tech>        *)
(*                                                                            *)
(******************************************************************************)

(* Pixel-level framebuffer widget.
   Dispatches rendering to the best available sub-pixel mode via Terminal_caps. *)

let ansi_reset = "\027[0m"

let rgb_to_ansi_256 r g b =
  if r = g && g = b then
    if r < 8 then 16 else if r > 248 then 231 else 232 + ((r - 8) / 10)
  else
    let r' = r * 6 / 256 in
    let g' = g * 6 / 256 in
    let b' = b * 6 / 256 in
    16 + (36 * r') + (6 * g') + b'

type t = {
  mutable pixels : bytes; (* flat RGB, stride = width_px * 3 *)
  mutable width_px : int;
  mutable height_px : int;
  mutable dirty : bool;
  mutable render_cache : string option;
  mutable last_cols : int;
  mutable last_rows : int;
}

let create () =
  {
    pixels = Bytes.empty;
    width_px = 0;
    height_px = 0;
    dirty = true;
    render_cache = None;
    last_cols = 0;
    last_rows = 0;
  }

let resize_pixels t ~width ~height =
  let new_size = width * height * 3 in
  if width <> t.width_px || height <> t.height_px then begin
    let new_buf = Bytes.make new_size '\000' in
    (* Copy overlapping region *)
    let copy_w = min width t.width_px in
    let copy_h = min height t.height_px in
    for y = 0 to copy_h - 1 do
      Bytes.blit
        t.pixels
        (y * t.width_px * 3)
        new_buf
        (y * width * 3)
        (copy_w * 3)
    done ;
    t.pixels <- new_buf ;
    t.width_px <- width ;
    t.height_px <- height ;
    t.dirty <- true
  end

let set_pixel t ~x ~y ~r ~g ~b =
  if x >= 0 && x < t.width_px && y >= 0 && y < t.height_px then begin
    let offset = ((y * t.width_px) + x) * 3 in
    Bytes.set t.pixels offset (Char.chr (r land 0xFF)) ;
    Bytes.set t.pixels (offset + 1) (Char.chr (g land 0xFF)) ;
    Bytes.set t.pixels (offset + 2) (Char.chr (b land 0xFF)) ;
    t.dirty <- true
  end

let blit t ~src ~width ~height =
  let new_size = width * height * 3 in
  let src_size = Bytes.length src in
  let buf = Bytes.create new_size in
  Bytes.blit src 0 buf 0 (min new_size src_size) ;
  t.pixels <- buf ;
  t.width_px <- width ;
  t.height_px <- height ;
  t.dirty <- true ;
  t.render_cache <- None

let clear t ~r ~g ~b =
  let n = t.width_px * t.height_px in
  for i = 0 to n - 1 do
    Bytes.set t.pixels (i * 3) (Char.chr (r land 0xFF)) ;
    Bytes.set t.pixels ((i * 3) + 1) (Char.chr (g land 0xFF)) ;
    Bytes.set t.pixels ((i * 3) + 2) (Char.chr (b land 0xFF))
  done ;
  t.dirty <- true

let fill_rect t ~x ~y ~w ~h ~r ~g ~b =
  let x1 = max 0 x and y1 = max 0 y in
  let x2 = min t.width_px (x + w) in
  let y2 = min t.height_px (y + h) in
  for py = y1 to y2 - 1 do
    for px = x1 to x2 - 1 do
      let offset = ((py * t.width_px) + px) * 3 in
      Bytes.set t.pixels offset (Char.chr (r land 0xFF)) ;
      Bytes.set t.pixels (offset + 1) (Char.chr (g land 0xFF)) ;
      Bytes.set t.pixels (offset + 2) (Char.chr (b land 0xFF))
    done
  done ;
  t.dirty <- true

(* Inline pixel reader *)
let get_rgb t px py =
  if px < 0 || px >= t.width_px || py < 0 || py >= t.height_px then (0, 0, 0)
  else
    let offset = ((py * t.width_px) + px) * 3 in
    ( Char.code (Bytes.get t.pixels offset),
      Char.code (Bytes.get t.pixels (offset + 1)),
      Char.code (Bytes.get t.pixels (offset + 2)) )

(* ── Render: Half_block ──────────────────────────────────────────────────── *)

let render_half_block t cols rows =
  (* 1×2 pixels per cell: top pixel = fg ("▀"), bottom pixel = bg.
     Pure-black cells (0,0,0) are treated as transparent → space. *)
  let buf = Buffer.create (rows * ((cols * 25) + 1)) in
  for cy = 0 to rows - 1 do
    if cy > 0 then Buffer.add_char buf '\n' ;
    for cx = 0 to cols - 1 do
      let r_top, g_top, b_top = get_rgb t cx (cy * 2) in
      let r_bot, g_bot, b_bot = get_rgb t cx ((cy * 2) + 1) in
      if r_top = 0 && g_top = 0 && b_top = 0
      && r_bot = 0 && g_bot = 0 && b_bot = 0 then
        Buffer.add_char buf ' '
      else begin
        (* Use fg=top (▀), bg=bottom — both as truecolor bg fills for solid rendering.
           When colors match, one bg+space suffices. Otherwise ▀ with fg+bg. *)
        if r_top = r_bot && g_top = g_bot && b_top = b_bot then
          Buffer.add_string buf (Printf.sprintf "\027[48;2;%d;%d;%dm %s" r_top g_top b_top ansi_reset)
        else
          Buffer.add_string buf
            (Printf.sprintf "\027[38;2;%d;%d;%dm\027[48;2;%d;%d;%dm\xE2\x96\x80%s"
               r_top g_top b_top r_bot g_bot b_bot ansi_reset)
      end
    done
  done ;
  Buffer.contents buf

(* ── Render: Braille ─────────────────────────────────────────────────────── *)

let render_braille t cols rows =
  let canvas = Braille_canvas.create ~width:cols ~height:rows in
  for cy = 0 to rows - 1 do
    for cx = 0 to cols - 1 do
      for dy = 0 to 3 do
        for dx = 0 to 1 do
          let px = cx * 2 + dx and py = cy * 4 + dy in
          if px < t.width_px && py < t.height_px then begin
            let r, g, b = get_rgb t px py in
            let luma = ((r * 299) + (g * 587) + (b * 114)) / 1000 in
            if luma > 128 then Braille_canvas.set_dot canvas ~x:px ~y:py
          end
        done
      done
    done
  done ;
  Braille_canvas.render canvas

(* ── Render: Octant ──────────────────────────────────────────────────────── *)

let render_octant t cols rows =
  (* 2×4 pixels per cell with two-color quantization per cell.
     For each 2×4 block: compute average luma, classify each pixel as
     fg (above avg) or bg (below avg), build the octant pattern accordingly. *)
  let buf = Buffer.create (rows * ((cols * 25) + 1)) in
  for cy = 0 to rows - 1 do
    if cy > 0 then Buffer.add_char buf '\n' ;
    for cx = 0 to cols - 1 do
      (* Collect 8 pixels for this cell (row-major bit order) *)
      let rs = Array.make 8 0 in
      let gs = Array.make 8 0 in
      let bs = Array.make 8 0 in
      let lumas = Array.make 8 0 in
      let valid = ref 0 in
      for dy = 0 to 3 do
        for dx = 0 to 1 do
          let i = (dy * 2) + dx in
          let px = (cx * 2) + dx and py = (cy * 4) + dy in
          let r, g, b = get_rgb t px py in
          rs.(i) <- r ;
          gs.(i) <- g ;
          bs.(i) <- b ;
          lumas.(i) <- ((r * 299) + (g * 587) + (b * 114)) / 1000 ;
          incr valid
        done
      done ;
      if !valid = 0 then Buffer.add_char buf ' '
      else begin
        (* Average luma for threshold *)
        let sum_luma = Array.fold_left ( + ) 0 lumas in
        let avg_luma = sum_luma / 8 in
        (* Classify and accumulate fg/bg averages *)
        let pattern = ref 0 in
        let fg_r = ref 0 and fg_g = ref 0 and fg_b = ref 0 and fg_n = ref 0 in
        let bg_r = ref 0 and bg_g = ref 0 and bg_b = ref 0 and bg_n = ref 0 in
        for i = 0 to 7 do
          if lumas.(i) >= avg_luma then begin
            pattern := !pattern lor (1 lsl i) ;
            fg_r := !fg_r + rs.(i) ;
            fg_g := !fg_g + gs.(i) ;
            fg_b := !fg_b + bs.(i) ;
            incr fg_n
          end
          else begin
            bg_r := !bg_r + rs.(i) ;
            bg_g := !bg_g + gs.(i) ;
            bg_b := !bg_b + bs.(i) ;
            incr bg_n
          end
        done ;
        let glyph = Octant_canvas.glyph_of_pattern !pattern in
        match !pattern with
        | 0 ->
            (* All dark: use bg color as a space *)
            if !bg_n > 0 then begin
              let r = !bg_r / !bg_n
              and g = !bg_g / !bg_n
              and b = !bg_b / !bg_n in
              let idx = rgb_to_ansi_256 r g b in
              Buffer.add_string
                buf
                (Printf.sprintf "\027[48;5;%dm %s" idx ansi_reset)
            end
            else Buffer.add_char buf ' '
        | 0xFF ->
            (* All bright: use fg glyph for solid fill *)
            if !fg_n > 0 then begin
              let r = !fg_r / !fg_n
              and g = !fg_g / !fg_n
              and b = !fg_b / !fg_n in
              if r = 0 && g = 0 && b = 0 then Buffer.add_char buf ' '
              else
                let idx = rgb_to_ansi_256 r g b in
                Buffer.add_string buf (Printf.sprintf "\027[38;5;%dm%s%s" idx glyph ansi_reset)
            end
            else Buffer.add_char buf ' '
        | _ ->
            (* Mixed: fg for set bits, bg for unset bits *)
            let fg_code =
              if !fg_n > 0 then
                let r = !fg_r / !fg_n
                and g = !fg_g / !fg_n
                and b = !fg_b / !fg_n in
                Printf.sprintf "\027[38;5;%dm" (rgb_to_ansi_256 r g b)
              else ""
            in
            let bg_code =
              if !bg_n > 0 then
                let r = !bg_r / !bg_n
                and g = !bg_g / !bg_n
                and b = !bg_b / !bg_n in
                Printf.sprintf "\027[48;5;%dm" (rgb_to_ansi_256 r g b)
              else ""
            in
            Buffer.add_string buf fg_code ;
            Buffer.add_string buf bg_code ;
            Buffer.add_string buf glyph ;
            Buffer.add_string buf ansi_reset
      end
    done
  done ;
  Buffer.contents buf

(* ── Render: Sextant (U+1FB00 range, 2×3 per cell) ─────────────────────── *)

(* Sextant bit layout (Unicode 13, U+1FB00 range, reading order):
   bit 0: (row 0, col 0)  bit 1: (row 0, col 1)
   bit 2: (row 1, col 0)  bit 3: (row 1, col 1)
   bit 4: (row 2, col 0)  bit 5: (row 2, col 1)
   U+1FB00 = pattern 0b000001, ..., U+1FB3B = pattern 0b111110
   (patterns 0 and 63 use space / full block respectively) *)
let sextant_base = 0x1FB00

(* Encode a codepoint in the supplementary plane to UTF-8 *)
let encode_cp4 cp =
  String.init 4 (fun i ->
      match i with
      | 0 -> Char.chr (0xF0 lor (cp lsr 18))
      | 1 -> Char.chr (0x80 lor ((cp lsr 12) land 0x3F))
      | 2 -> Char.chr (0x80 lor ((cp lsr 6) land 0x3F))
      | _ -> Char.chr (0x80 lor (cp land 0x3F)))

(* Precompute sextant glyphs for all 64 patterns (6-bit) *)
let sextant_glyphs : string array =
  Array.init 64 (fun pattern ->
      match pattern with
      | 0 -> " "
      | 0x3F -> "\xE2\x96\x88" (* U+2588 FULL BLOCK *)
      | p -> encode_cp4 (sextant_base + p - 1))

let render_sextant t cols rows =
  let buf = Buffer.create (rows * ((cols * 25) + 1)) in
  for cy = 0 to rows - 1 do
    if cy > 0 then Buffer.add_char buf '\n' ;
    for cx = 0 to cols - 1 do
      let rs = Array.make 6 0 in
      let gs = Array.make 6 0 in
      let bs = Array.make 6 0 in
      let lumas = Array.make 6 0 in
      for dy = 0 to 2 do
        for dx = 0 to 1 do
          let i = (dy * 2) + dx in
          let px = (cx * 2) + dx and py = (cy * 3) + dy in
          let r, g, b = get_rgb t px py in
          rs.(i) <- r ;
          gs.(i) <- g ;
          bs.(i) <- b ;
          lumas.(i) <- ((r * 299) + (g * 587) + (b * 114)) / 1000
        done
      done ;
      let sum_luma = Array.fold_left ( + ) 0 lumas in
      let avg_luma = sum_luma / 6 in
      let pattern = ref 0 in
      let fg_r = ref 0 and fg_g = ref 0 and fg_b = ref 0 and fg_n = ref 0 in
      let bg_r = ref 0 and bg_g = ref 0 and bg_b = ref 0 and bg_n = ref 0 in
      for i = 0 to 5 do
        if lumas.(i) >= avg_luma then begin
          pattern := !pattern lor (1 lsl i) ;
          fg_r := !fg_r + rs.(i) ;
          fg_g := !fg_g + gs.(i) ;
          fg_b := !fg_b + bs.(i) ;
          incr fg_n
        end
        else begin
          bg_r := !bg_r + rs.(i) ;
          bg_g := !bg_g + gs.(i) ;
          bg_b := !bg_b + bs.(i) ;
          incr bg_n
        end
      done ;
      let glyph = sextant_glyphs.(!pattern) in
      match !pattern with
      | 0 ->
          if !bg_n > 0 then begin
            let r = !bg_r / !bg_n and g = !bg_g / !bg_n and b = !bg_b / !bg_n in
            Buffer.add_string buf (Printf.sprintf "\027[48;2;%d;%d;%dm %s" r g b ansi_reset)
          end
          else Buffer.add_char buf ' '
      | 0x3F ->
          (* All bright: use bg+space for pixel-exact solid fill (fg glyphs can
             have font-dependent gaps showing the terminal background through) *)
          if !fg_n > 0 then begin
            let r = !fg_r / !fg_n and g = !fg_g / !fg_n and b = !fg_b / !fg_n in
            if r = 0 && g = 0 && b = 0 then Buffer.add_char buf ' '
            else Buffer.add_string buf (Printf.sprintf "\027[48;2;%d;%d;%dm %s" r g b ansi_reset)
          end
          else Buffer.add_char buf ' '
      | _ ->
          let fg_code =
            if !fg_n > 0 then
              let r = !fg_r / !fg_n
              and g = !fg_g / !fg_n
              and b = !fg_b / !fg_n in
              Printf.sprintf "\027[38;2;%d;%d;%dm" r g b
            else ""
          in
          let bg_code =
            if !bg_n > 0 then
              let r = !bg_r / !bg_n
              and g = !bg_g / !bg_n
              and b = !bg_b / !bg_n in
              Printf.sprintf "\027[48;2;%d;%d;%dm" r g b
            else ""
          in
          Buffer.add_string buf fg_code ;
          Buffer.add_string buf bg_code ;
          Buffer.add_string buf glyph ;
          Buffer.add_string buf ansi_reset
    done
  done ;
  Buffer.contents buf

(* ── Render: Sixel ───────────────────────────────────────────────────────── *)

(* DCS Sixel encoding.
   Each sixel character covers a 1-pixel-wide × 6-pixel-tall column.
   Bit pattern: bit 0 = top row, bit 5 = bottom row. ASCII: pattern + 63.
   Pb=1 → unset pixels show terminal background (transparent). *)
let render_sixel t cols rows =
  let w = t.width_px and h = t.height_px in
  let buf = Buffer.create (max 1024 (w * h / 4)) in
  Buffer.add_string buf "\027P0;1;0q" ;
  (* Pass 1: build palette and color index map in one pass. *)
  let palette_tbl = Hashtbl.create 64 in
  let palette_rgb = Array.make 256 (0, 0, 0) in
  let n_colors = ref 0 in
  let transparent = -1 in
  let idx_map = Array.make (w * h) transparent in
  for py = 0 to h - 1 do
    let row_off = py * w in
    for px = 0 to w - 1 do
      let off = (row_off + px) * 3 in
      let r = Char.code (Bytes.unsafe_get t.pixels off) in
      let g = Char.code (Bytes.unsafe_get t.pixels (off + 1)) in
      let b = Char.code (Bytes.unsafe_get t.pixels (off + 2)) in
      if r <> 0 || g <> 0 || b <> 0 then begin
        let key = (r lsl 16) lor (g lsl 8) lor b in
        let ci = match Hashtbl.find_opt palette_tbl key with
          | Some i -> i
          | None ->
            if !n_colors >= 256 then begin
              let best_i = ref 0 and best_d = ref max_int in
              for i = 0 to !n_colors - 1 do
                let pr, pg, pb = palette_rgb.(i) in
                let d = (r-pr)*(r-pr) + (g-pg)*(g-pg) + (b-pb)*(b-pb) in
                if d < !best_d then (best_d := d ; best_i := i)
              done ;
              !best_i
            end else begin
              let i = !n_colors in
              Hashtbl.add palette_tbl key i ;
              palette_rgb.(i) <- (r, g, b) ;
              incr n_colors ; i
            end
        in
        idx_map.(row_off + px) <- ci
      end
    done
  done ;
  let nc = !n_colors in
  (* Emit palette. *)
  for i = 0 to nc - 1 do
    let r, g, b = palette_rgb.(i) in
    Buffer.add_string buf
      (Printf.sprintf "#%d;2;%d;%d;%d" i (r*100/255) (g*100/255) (b*100/255))
  done ;
  (* Pass 2: single-pass per band — build all color patterns simultaneously,
     then emit only colors that appeared.  O(w × 6 × bands) instead of
     O(nc × w × 6 × bands). *)
  let n_bands = (h + 5) / 6 in
  (* Per-color pattern array: band_pat.(ci).(px) = sixel bit pattern *)
  let band_pat = Array.init (max 1 nc) (fun _ -> Array.make w 0) in
  let color_present = Array.make (max 1 nc) false in
  let emit_rle pat count =
    let c = Char.chr (pat + 63) in
    if count <= 3 then
      for _ = 1 to count do Buffer.add_char buf c done
    else begin
      Buffer.add_char buf '!' ;
      Buffer.add_string buf (string_of_int count) ;
      Buffer.add_char buf c
    end
  in
  for band = 0 to n_bands - 1 do
    let py0 = band * 6 in
    (* Clear presence flags *)
    Array.fill color_present 0 nc false ;
    (* Single pass: scatter each pixel's bit into its color's pattern row *)
    for row = 0 to 5 do
      let py = py0 + row in
      if py < h then begin
        let row_off = py * w in
        let bit = 1 lsl row in
        for px = 0 to w - 1 do
          let ci = idx_map.(row_off + px) in
          if ci >= 0 then begin
            band_pat.(ci).(px) <- band_pat.(ci).(px) lor bit ;
            color_present.(ci) <- true
          end
        done
      end
    done ;
    (* Emit each color that appeared in this band *)
    for ci = 0 to nc - 1 do
      if color_present.(ci) then begin
        let pats = band_pat.(ci) in
        Buffer.add_string buf (Printf.sprintf "#%d" ci) ;
        let run_pat = ref pats.(0) in
        let run_len = ref 1 in
        for px = 1 to w - 1 do
          if pats.(px) = !run_pat then incr run_len
          else begin
            emit_rle !run_pat !run_len ;
            run_pat := pats.(px) ;
            run_len := 1
          end
        done ;
        emit_rle !run_pat !run_len ;
        Buffer.add_char buf '$' ;
        (* Clear for next band *)
        Array.fill pats 0 w 0
      end
    done ;
    if band < n_bands - 1 then Buffer.add_char buf '-'
  done ;
  Buffer.add_string buf "\027\\" ;
  ignore (cols, rows) ;
  Buffer.contents buf

(* ── Main render dispatcher ──────────────────────────────────────────────── *)

(* Sub-pixel dimensions for each mode: (px_per_cell_x, px_per_cell_y) *)
let px_per_cell mode =
  match mode with
  | Terminal_caps.Sixel ->
      (8, 16) (* approximate; real size via cell_pixel_size *)
  | Terminal_caps.Octant -> (2, 4)
  | Terminal_caps.Sextant -> (2, 3)
  | Terminal_caps.Half_block -> (1, 2)
  | Terminal_caps.Braille -> (2, 4)

let render_with_mode t ~mode ~cols ~rows =
  let px_x, px_y = px_per_cell mode in
  let need_w = cols * px_x and need_h = rows * px_y in
  if cols <> t.last_cols || rows <> t.last_rows then begin
    resize_pixels t ~width:need_w ~height:need_h ;
    t.last_cols <- cols ;
    t.last_rows <- rows ;
    t.render_cache <- None
  end ;
  if (not t.dirty) && t.render_cache <> None then Option.get t.render_cache
  else begin
    if t.width_px = 0 || t.height_px = 0 then
      resize_pixels t ~width:need_w ~height:need_h ;
    let output =
      match mode with
      | Terminal_caps.Sixel -> render_sixel t cols rows
      | Terminal_caps.Octant -> render_octant t cols rows
      | Terminal_caps.Sextant -> render_sextant t cols rows
      | Terminal_caps.Half_block -> render_half_block t cols rows
      | Terminal_caps.Braille -> render_braille t cols rows
    in
    t.dirty <- false ;
    t.render_cache <- Some output ;
    output
  end

let render t ~cols ~rows =
  render_with_mode t ~mode:(Terminal_caps.detect ()) ~cols ~rows

let () =
  Miaou_registry.register
    ~name:"framebuffer"
    ~mli:[%blob "framebuffer_widget.mli"]
    ()
