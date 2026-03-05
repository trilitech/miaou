(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Mathias Bourgoin <mathias.bourgoin@atacama.tech>        *)
(*                                                                            *)
(******************************************************************************)

(* Pixel-level framebuffer widget.
   Dispatches rendering to the best available sub-pixel mode via Terminal_caps. *)

let ansi_reset = "\027[0m"

(* Shared RGB → ANSI 256 color conversion *)
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
  (* 1×2 pixels per cell: top pixel = fg ("▀"), bottom pixel = bg *)
  let buf = Buffer.create (rows * ((cols * 25) + 1)) in
  for cy = 0 to rows - 1 do
    if cy > 0 then Buffer.add_char buf '\n' ;
    for cx = 0 to cols - 1 do
      let r_top, g_top, b_top = get_rgb t cx (cy * 2) in
      let r_bot, g_bot, b_bot = get_rgb t cx ((cy * 2) + 1) in
      let fg_idx = rgb_to_ansi_256 r_top g_top b_top in
      let bg_idx = rgb_to_ansi_256 r_bot g_bot b_bot in
      if fg_idx = bg_idx then
        Buffer.add_string
          buf
          (Printf.sprintf "\027[38;5;%dm\xE2\x96\x88%s" fg_idx ansi_reset)
      else
        Buffer.add_string
          buf
          (Printf.sprintf
             "\027[38;5;%dm\027[48;5;%dm\xE2\x96\x80%s"
             fg_idx
             bg_idx
             ansi_reset)
    done
  done ;
  Buffer.contents buf

(* ── Render: Braille ─────────────────────────────────────────────────────── *)

let render_braille t cols rows =
  (* 2×4 pixels per cell — monochrome via brightness threshold *)
  let canvas = Braille_canvas.create ~width:cols ~height:rows in
  let dot_w = cols * 2 and dot_h = rows * 4 in
  for dy = 0 to dot_h - 1 do
    for dx = 0 to dot_w - 1 do
      let r, g, b = get_rgb t dx dy in
      (* Luma threshold: set dot if pixel is bright enough *)
      let luma = ((r * 299) + (g * 587) + (b * 114)) / 1000 in
      if luma >= 128 then Braille_canvas.set_dot canvas ~x:dx ~y:dy
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
            (* All bright: full block with fg color *)
            if !fg_n > 0 then begin
              let r = !fg_r / !fg_n
              and g = !fg_g / !fg_n
              and b = !fg_b / !fg_n in
              let idx = rgb_to_ansi_256 r g b in
              Buffer.add_string
                buf
                (Printf.sprintf "\027[38;5;%dm%s%s" idx glyph ansi_reset)
            end
            else Buffer.add_string buf glyph
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
            Buffer.add_string
              buf
              (Printf.sprintf
                 "\027[48;5;%dm %s"
                 (rgb_to_ansi_256 r g b)
                 ansi_reset)
          end
          else Buffer.add_char buf ' '
      | 0x3F ->
          if !fg_n > 0 then begin
            let r = !fg_r / !fg_n and g = !fg_g / !fg_n and b = !fg_b / !fg_n in
            Buffer.add_string
              buf
              (Printf.sprintf
                 "\027[38;5;%dm%s%s"
                 (rgb_to_ansi_256 r g b)
                 glyph
                 ansi_reset)
          end
          else Buffer.add_string buf glyph
      | _ ->
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
    done
  done ;
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

let render t ~cols ~rows =
  let mode = Terminal_caps.detect () in
  let px_x, px_y = px_per_cell mode in
  let need_w = cols * px_x and need_h = rows * px_y in
  (* Resize pixel buffer if terminal size changed *)
  if cols <> t.last_cols || rows <> t.last_rows then begin
    resize_pixels t ~width:need_w ~height:need_h ;
    t.last_cols <- cols ;
    t.last_rows <- rows ;
    t.render_cache <- None
  end ;
  (* Return cached output if clean *)
  if (not t.dirty) && t.render_cache <> None then Option.get t.render_cache
  else begin
    (* Ensure buffer is at least the required size *)
    if t.width_px = 0 || t.height_px = 0 then
      resize_pixels t ~width:need_w ~height:need_h ;
    let output =
      match mode with
      | Terminal_caps.Sixel ->
          (* Phase 2: Sixel not yet implemented; fall back to Half_block *)
          render_half_block t cols rows
      | Terminal_caps.Octant -> render_octant t cols rows
      | Terminal_caps.Sextant -> render_sextant t cols rows
      | Terminal_caps.Half_block -> render_half_block t cols rows
      | Terminal_caps.Braille -> render_braille t cols rows
    in
    t.dirty <- false ;
    t.render_cache <- Some output ;
    output
  end

let () =
  Miaou_registry.register
    ~name:"framebuffer"
    ~mli:[%blob "framebuffer_widget.mli"]
    ()
