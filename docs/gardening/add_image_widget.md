# Add Image Display Widgets to MIAOU

**Goal**: Display images (BMP, JPG, PNG, GIF) in both terminal (ASCII/Unicode/Sixel) and SDL backends.

**Context**: Image display in TUI is rare but powerful. Mosaic doesn't have this. MIAOU's multi-backend architecture (terminal + SDL) makes this a **unique differentiator**.

**Timeline**: 5-7 days
- Days 1-2: Terminal image rendering (ASCII/block characters)
- Days 3-4: Sixel protocol support (advanced terminals)
- Days 5: SDL image rendering (native display)
- Days 6-7: GIF animation support (optional)

---

## Why Image Widgets Matter

### Use Cases for Octez:

**octez-manager/octez-setup**:
- ✅ **QR codes** for wallet addresses, backup seeds
- ✅ **Node topology diagrams** (network visualization)
- ✅ **Brand identity** (Tezos logo, octez branding)
- ✅ **Visual indicators** (status icons, badges)
- ✅ **Documentation** (inline diagrams, screenshots)
- ✅ **Monitoring graphs** exported as images

### Technical Advantages:

**Terminal rendering**:
- Unicode block chars (▀▄█) - works everywhere
- Sixel protocol - high quality in modern terminals
- ASCII art fallback - universal compatibility

**SDL rendering**:
- Native image display
- No quality loss
- Smooth animations

**Multi-backend = Best UX**:
- Terminal: Functional QR codes (good enough)
- SDL: Perfect quality logos/diagrams

---

## Image Formats & Decoding

### Format Support:

| Format | Priority | Decoder | Terminal | SDL | Notes |
|--------|----------|---------|----------|-----|-------|
| **BMP** | 🔴 High | Pure OCaml | ✅ | ✅ | Simple, uncompressed |
| **PNG** | 🔴 High | `camlimages` | ✅ | ✅ | Most common, lossless |
| **JPEG** | 🟡 Medium | `camlimages` | ✅ | ✅ | Photos, lossy |
| **GIF** | 🟢 Nice | `camlimages` | ✅ | ✅ | Animation support |
| **QR Code** | 🔴 High | `qrc` library | ✅ | ✅ | Generate, not decode |

### Dependencies:

```ocaml
(* dune-project *)
(depends
  ...
  (camlimages (>= 5.0))  ;; Image decoding
  (qrc (>= 0.1))          ;; QR code generation
)
```

**Alternative**: Could use `stb_image` bindings for lighter dependency (C library, single file).

---

## Widgets to Implement

### 1. Image Widget (Terminal Backend) - Priority: 🔴 CRITICAL

**Location**: `src/miaou_widgets_display/image_widget.ml` + `.mli`

**Purpose**: Display images in terminal using Unicode block characters or Sixel protocol.

**API Design**:

```ocaml
type image_source =
  | File of string           (* Path to image file *)
  | Data of bytes            (* Raw image data *)
  | QR of string             (* Generate QR code from string *)

type render_mode =
  | Auto                     (* Detect best available *)
  | Blocks                   (* Unicode half-blocks ▀▄ *)
  | Ascii                    (* ASCII art (low quality) *)
  | Sixel                    (* Sixel protocol (high quality) *)

type fit_mode =
  | Contain                  (* Fit inside dimensions, preserve aspect *)
  | Cover                    (* Fill dimensions, may crop *)
  | Stretch                  (* Fill dimensions, ignore aspect *)
  | Original                 (* Use original size *)

type t

(** Create an image widget.
    @param source Image source (file path, data, or QR code content)
    @param width Target display width in columns
    @param height Target display height in rows
    @param mode Rendering mode (default: Auto)
    @param fit How to fit image into dimensions (default: Contain)
*)
val create :
  source:image_source ->
  width:int ->
  height:int ->
  ?mode:render_mode ->
  ?fit:fit_mode ->
  ?alt_text:string ->        (* Fallback text if image fails *)
  unit -> t

(** Render the image to string *)
val render : t -> focus:bool -> string

(** Update image source (for animations) *)
val set_source : t -> image_source -> unit

(** Check if terminal supports Sixel *)
val supports_sixel : unit -> bool

(** Get image dimensions *)
val dimensions : t -> (int * int)
```

**Implementation Details**:

#### **1. Image Loading**:

```ocaml
open Camlimages

let load_image = function
  | File path ->
      (* Detect format from extension *)
      let img = match Filename.extension path with
        | ".bmp" | ".BMP" -> Bmp.load path []
        | ".png" | ".PNG" -> Png.load path []
        | ".jpg" | ".jpeg" | ".JPG" | ".JPEG" -> Jpeg.load path []
        | ".gif" | ".GIF" -> Gif.load path []
        | _ -> failwith "Unsupported image format"
      in
      Images.Rgba32 (Rgba32.of_image img)

  | Data bytes ->
      (* Try to detect format from magic bytes *)
      (* PNG: 89 50 4E 47, JPEG: FF D8 FF, BMP: 42 4D, GIF: 47 49 46 *)
      let magic = Bytes.sub bytes 0 (min 4 (Bytes.length bytes)) in
      (* ... detection logic ... *)

  | QR code_content ->
      (* Generate QR code using qrc library *)
      let qr = Qrc.create ~ec_level:`M code_content in
      let matrix = Qrc.to_matrix qr in
      (* Convert matrix to image *)
      qr_matrix_to_rgba matrix
```

#### **2. Block Character Rendering** (Unicode Half-Blocks):

```ocaml
(** Convert RGBA pixel pair to Unicode half-block character.
    Uses ▀ (upper half) and ▄ (lower half) with ANSI colors.

    Approach:
    - Process image 2 rows at a time
    - Top pixel → foreground color
    - Bottom pixel → background color
    - Char '▀' shows top color in upper half, bg color in lower half
*)

let pixel_to_ansi_color (r, g, b, _a) =
  (* Convert RGB to nearest ANSI 256-color *)
  if r = g && g = b then
    (* Grayscale: use grayscale ramp (232-255) *)
    232 + (r * 23 / 255)
  else
    (* Color: use 6x6x6 color cube (16-231) *)
    16 + (36 * (r / 51)) + (6 * (g / 51)) + (b / 51)

let render_blocks img width height =
  let scaled = scale_image img width (height * 2) in  (* 2x height for half-blocks *)
  let buf = Buffer.create (width * height * 20) in  (* Estimate *)

  for row = 0 to height - 1 do
    for col = 0 to width - 1 do
      let top_pixel = get_pixel scaled col (row * 2) in
      let bottom_pixel = get_pixel scaled col (row * 2 + 1) in

      let fg = pixel_to_ansi_color top_pixel in
      let bg = pixel_to_ansi_color bottom_pixel in

      (* ANSI escape: \033[38;5;<fg>m\033[48;5;<bg>m *)
      Buffer.add_string buf (Printf.sprintf "\027[38;5;%dm\027[48;5;%dm▀" fg bg)
    done;
    Buffer.add_string buf "\027[0m\n"  (* Reset colors at end of line *)
  done;
  Buffer.contents buf
```

**Visual explanation**:
```
Original pixels:     Block rendering:
[RED]                ▀  (RED foreground)
[BLUE]               ▀  (BLUE background)

Each character = 2 vertical pixels!
```

#### **3. ASCII Art Rendering** (Fallback):

```ocaml
(** Convert to grayscale ASCII art using brightness levels *)

let ascii_chars = [|' '; '.'; ':'; '-'; '='; '+'; '*'; '#'; '%'; '@'|]

let render_ascii img width height =
  let scaled = scale_to_grayscale img width height in
  let buf = Buffer.create (width * height) in

  for row = 0 to height - 1 do
    for col = 0 to width - 1 do
      let brightness = get_pixel_brightness scaled col row in
      let char_idx = brightness * (Array.length ascii_chars - 1) / 255 in
      Buffer.add_char buf ascii_chars.(char_idx)
    done;
    Buffer.add_char buf '\n'
  done;
  Buffer.contents buf
```

#### **4. Sixel Protocol Rendering** (High Quality):

```ocaml
(** Sixel: bitmap graphics protocol supported by modern terminals
    (XTerm, mintty, mlterm, WezTerm, iTerm2 with sixel plugin)

    Format: ESC P <params> q <data> ESC \

    Sixel uses 6 vertical pixels per character row, hence the name.
*)

let supports_sixel () =
  (* Check TERM environment variable *)
  match Sys.getenv_opt "TERM" with
  | Some term when String.contains term "xterm" -> true
  | Some term when String.contains term "mlterm" -> true
  | _ ->
      (* Try to query terminal capabilities *)
      (* Send CSI c (Primary Device Attributes) and check response *)
      false  (* Conservative: assume no support *)

let render_sixel img =
  (* This is complex - use a library or external tool *)
  (* Option 1: Use libsixel bindings if available *)
  (* Option 2: Call external 'img2sixel' tool *)
  (* Option 3: Implement Sixel encoder (significant effort) *)

  (* Simplified approach: call img2sixel *)
  let temp_file = Filename.temp_file "miaou_img" ".png" in
  save_png img temp_file;
  let cmd = Printf.sprintf "img2sixel -w %d %s" width temp_file in
  let ic = Unix.open_process_in cmd in
  let sixel_data = really_input_string ic (in_channel_length ic) in
  Unix.close_process_in ic;
  Sys.remove temp_file;
  sixel_data
```

**Note**: Sixel is powerful but complex. Consider using external tool initially, optimize later.

#### **5. QR Code Generation**:

```ocaml
let generate_qr content width =
  let qr = Qrc.create ~ec_level:`M content in
  let matrix = Qrc.to_matrix qr in
  let size = Array.length matrix in

  (* QR codes should be square *)
  let module_size = width / size in

  (* Render using block characters (each block = 1 module) *)
  let buf = Buffer.create (size * size) in
  for row = 0 to size - 1 do
    for col = 0 to size - 1 do
      let is_black = matrix.(row).(col) in
      Buffer.add_string buf (if is_black then "██" else "  ")
    done;
    Buffer.add_char buf '\n'
  done;
  Buffer.contents buf
```

**Tests** (`test/test_image_widget.ml`):

```ocaml
let test_load_bmp () =
  let img = Image_widget.create
    ~source:(File "test/fixtures/test.bmp")
    ~width:40
    ~height:20
    () in
  let output = Image_widget.render img ~focus:false in
  (* Check output is non-empty and contains ANSI codes *)
  check bool "has output" true (String.length output > 0)

let test_qr_generation () =
  let img = Image_widget.create
    ~source:(QR "https://tezos.com")
    ~width:30
    ~height:30
    () in
  let output = Image_widget.render img ~focus:false in
  (* QR codes should be square blocks *)
  check bool "is square-ish" true (String.contains output '█')

let test_ascii_fallback () =
  let img = Image_widget.create
    ~source:(File "test/fixtures/test.png")
    ~width:40
    ~height:20
    ~mode:Ascii
    () in
  let output = Image_widget.render img ~focus:false in
  (* Should use ASCII chars, no ANSI escape codes *)
  check bool "no ansi" false (String.contains output '\027')
```

---

### 2. Image Widget (SDL Backend) - Priority: 🔴 CRITICAL

**Location**: `src/miaou_widgets_display/image_widget_sdl.ml` + `.mli`

**Purpose**: Native image display in SDL backend with full quality.

**API Design**:

```ocaml
(** SDL-specific image widget - identical API to terminal version *)

type t

val create :
  source:image_source ->
  width:int ->
  height:int ->
  ?fit:fit_mode ->
  ?alt_text:string ->
  unit -> t

(** Render to SDL surface/texture *)
val render_sdl : t -> Tsdl.Sdl.renderer -> x:int -> y:int -> unit
```

**Implementation Details**:

```ocaml
open Tsdl
open Tsdl_image

type t = {
  source: image_source;
  texture: Sdl.texture option ref;  (* Cached texture *)
  width: int;
  height: int;
  fit: fit_mode;
}

let create ~source ~width ~height ?(fit = Contain) ?alt_text () =
  {
    source;
    texture = ref None;
    width;
    height;
    fit;
  }

let load_texture renderer source =
  match source with
  | File path ->
      (* Use SDL_image to load directly *)
      (match Image.load path with
       | Ok surface ->
           Sdl.create_texture_from_surface renderer surface
       | Error (`Msg e) ->
           Printf.eprintf "Failed to load image: %s\n" e;
           Error (`Msg e))

  | Data bytes ->
      (* Load from memory using SDL_RWops *)
      let rw = Sdl.rw_from_mem bytes in
      (match Image.load_rw rw with
       | Ok surface ->
           Sdl.create_texture_from_surface renderer surface
       | Error e -> Error e)

  | QR content ->
      (* Generate QR code as image, convert to SDL surface *)
      let qr = Qrc.create ~ec_level:`M content in
      let matrix = Qrc.to_matrix qr in
      (* Create SDL surface from matrix *)
      qr_to_surface matrix

let render_sdl t renderer ~x ~y =
  (* Load texture if not cached *)
  (match !(t.texture) with
   | Some tex -> tex
   | None ->
       match load_texture renderer t.source with
       | Ok tex ->
           t.texture := Some tex;
           tex
       | Error _ ->
           (* TODO: Render alt_text or error placeholder *)
           return)
  |> fun texture ->

  (* Calculate dest rect based on fit mode *)
  let src_rect = None in  (* Use full source *)
  let dest_rect = calculate_dest_rect t.width t.height t.fit texture in

  (* Render texture *)
  Sdl.render_copy renderer ~src:src_rect ~dst:(Some dest_rect) texture

let calculate_dest_rect width height fit texture =
  let (_, _, tex_w, tex_h) =
    match Sdl.query_texture texture with
    | Ok info -> info
    | Error _ -> (0, 0, width, height)
  in

  let dest_rect = match fit with
    | Contain ->
        (* Scale to fit inside, preserve aspect ratio *)
        let scale = min
          (float_of_int width /. float_of_int tex_w)
          (float_of_int height /. float_of_int tex_h)
        in
        let scaled_w = int_of_float (float_of_int tex_w *. scale) in
        let scaled_h = int_of_float (float_of_int tex_h *. scale) in
        Sdl.Rect.create
          ~x:(x + (width - scaled_w) / 2)
          ~y:(y + (height - scaled_h) / 2)
          ~w:scaled_w
          ~h:scaled_h

    | Cover ->
        (* Scale to cover, may crop *)
        (* ... similar logic but use max instead of min ... *)

    | Stretch ->
        (* Fill entire area, ignore aspect ratio *)
        Sdl.Rect.create ~x ~y ~w:width ~h:height

    | Original ->
        (* Use original size, centered *)
        Sdl.Rect.create
          ~x:(x + (width - tex_w) / 2)
          ~y:(y + (height - tex_h) / 2)
          ~w:tex_w
          ~h:tex_h
  in
  dest_rect
```

**Tests** (SDL tests require display, so use screenshots):

```ocaml
let test_sdl_image_load () =
  (* Create SDL window/renderer *)
  let window = create_test_window () in
  let renderer = Sdl.create_renderer window in

  let img = Image_widget.create
    ~source:(File "test/fixtures/tezos_logo.png")
    ~width:200
    ~height:200
    () in

  Image_widget.render_sdl img renderer ~x:0 ~y:0;

  (* Capture screenshot and compare to reference *)
  let screenshot = capture_renderer renderer in
  check_image_similarity screenshot "test/fixtures/expected_logo.png" 0.95
```

---

### 3. Animated GIF Widget - Priority: 🟢 OPTIONAL

**Location**: `src/miaou_widgets_display/gif_widget.ml` + `.mli`

**Purpose**: Display animated GIFs with frame timing.

**API Design**:

```ocaml
type t

val create :
  source:image_source ->  (* Must be GIF *)
  width:int ->
  height:int ->
  ?loop:bool ->           (* Loop animation (default: true) *)
  unit -> t

(** Render current frame *)
val render : t -> focus:bool -> string

(** Advance to next frame (call on timer) *)
val next_frame : t -> unit

(** Get frame delay in milliseconds *)
val frame_delay : t -> int
```

**Implementation**:

```ocaml
open Camlimages

type frame = {
  image: Images.rgba32;
  delay_ms: int;  (* Delay until next frame *)
}

type t = {
  frames: frame array;
  current_frame: int ref;
  width: int;
  height: int;
  loop: bool;
}

let create ~source ~width ~height ?(loop = true) () =
  let frames = load_gif_frames source in
  {
    frames;
    current_frame = ref 0;
    width;
    height;
    loop;
  }

let load_gif_frames = function
  | File path ->
      let gif = Gif.load path [] in
      (* GIF.load returns an image with frames *)
      (* Extract frame sequence and delays *)
      extract_frames_from_gif gif
  | _ -> failwith "GIF widget requires File source"

let render t ~focus =
  let frame = t.frames.(!(t.current_frame)) in
  (* Use image_widget rendering logic *)
  Image_widget.render_blocks frame.image t.width t.height

let next_frame t =
  let next = !(t.current_frame) + 1 in
  if next >= Array.length t.frames then
    if t.loop then t.current_frame := 0
    else t.current_frame := Array.length t.frames - 1  (* Stay on last frame *)
  else
    t.current_frame := next

let frame_delay t =
  let frame = t.frames.(!(t.current_frame)) in
  frame.delay_ms
```

**Demo Integration**:

```ocaml
(* In page update loop *)
type state = {
  gif: Gif_widget.t;
  last_frame_time: float ref;
}

let update st msg =
  match msg with
  | Tick dt ->
      let now = Unix.gettimeofday () in
      let elapsed_ms = int_of_float ((now -. !(st.last_frame_time)) *. 1000.) in
      if elapsed_ms >= Gif_widget.frame_delay st.gif then (
        Gif_widget.next_frame st.gif;
        st.last_frame_time := now
      );
      st
  | _ -> st
```

---

## Module Structure

```
src/miaou_widgets_display/
├── image_widget.ml              # Terminal backend
├── image_widget.mli
├── image_widget_sdl.ml          # SDL backend
├── image_widget_sdl.mli
├── gif_widget.ml                # Animated GIF (optional)
├── gif_widget.mli
└── image_utils.ml               # Shared: scaling, color conversion

src/miaou_widgets_display/dune:
(library
 ...
 (libraries
   ...
   camlimages.core
   camlimages.png
   camlimages.jpeg
   camlimages.gif
   qrc
   tsdl
   tsdl-image)
 (modules
   ...
   image_widget
   image_widget_sdl
   gif_widget
   image_utils))
```

---

## Use Case Examples

### 1. QR Code for Wallet Address

```ocaml
(* In octez-setup: Display backup seed as QR code *)

let qr = Image_widget.create
  ~source:(QR "tezos://tz1abc...xyz?amount=10")
  ~width:40
  ~height:20
  () in

let page_view state ~focus ~size =
  let lines = [
    "Wallet Created Successfully!";
    "";
    "Scan this QR code to import on mobile:";
    "";
    Image_widget.render qr ~focus:true;
    "";
    "Or copy address: tz1abc...xyz";
  ] in
  String.concat "\n" lines
```

**Terminal Output** (block characters):
```
Wallet Created Successfully!

Scan this QR code to import on mobile:

██████████████  ██  ██████████████
██          ██      ██          ██
██  ██████  ██  ██  ██  ██████  ██
██  ██████  ██  ██  ██  ██████  ██
██  ██████  ██      ██  ██████  ██
██          ██  ██  ██          ██
██████████████  ██  ██████████████
                ██
  ██  ██    ██████    ██  ██  ██
    ██████  ██    ██████████
██    ██      ██  ██      ██████
  ██████  ██████████████  ██
                ██
██████████████    ██████  ██  ████
██          ██  ██  ██  ██████  ██
██  ██████  ██      ████  ██  ████
██  ██████  ██  ██████████    ██
██  ██████  ██  ██  ██████  ██████
██          ██    ██    ████    ██
██████████████  ██  ██      ██████

Or copy address: tz1abc...xyz
```

### 2. Tezos Logo Branding

```ocaml
(* Welcome screen with logo *)

let logo = Image_widget.create
  ~source:(File "/usr/share/octez/logo.png")
  ~width:60
  ~height:20
  ~fit:Contain
  () in

(* In terminal: renders as colored blocks *)
(* In SDL: renders as crisp PNG *)
```

### 3. Node Topology Diagram

```ocaml
(* Network visualization *)

let topology = Image_widget.create
  ~source:(File "/tmp/network_graph.png")
  ~width:80
  ~height:30
  ~fit:Cover
  () in

(* Graph generated by external tool (graphviz), displayed in TUI *)
```

### 4. Status Icons

```ocaml
(* Small icons for service status *)

let icon_ok = Image_widget.create
  ~source:(File "assets/check.bmp")
  ~width:3
  ~height:2
  () in

let icon_error = Image_widget.create
  ~source:(File "assets/cross.bmp")
  ~width:3
  ~height:2
  () in

(* Render inline with text *)
Printf.sprintf "%s Baker: Running" (Image_widget.render icon_ok ~focus:false)
(* Output: "✓ Baker: Running" (but as image, not text) *)
```

---

## Technical Challenges & Solutions

### Challenge 1: Color Quantization

**Problem**: Terminals support 256 colors, images have millions.

**Solutions**:
- Use ANSI 256-color palette (6×6×6 RGB cube + 24 grayscales)
- Dithering (Floyd-Steinberg) for better quality
- Fall back to 16-color ANSI if terminal is limited

```ocaml
let quantize_rgb (r, g, b) =
  (* Simple: round to nearest of 6 levels per channel *)
  let quantize_channel c =
    let level = c * 5 / 255 in
    level * 51  (* 0, 51, 102, 153, 204, 255 *)
  in
  (quantize_channel r, quantize_channel g, quantize_channel b)

(* Advanced: Floyd-Steinberg dithering *)
let dither_image img =
  (* Propagate quantization error to neighbors *)
  (* ... implementation ... *)
```

### Challenge 2: Aspect Ratio

**Problem**: Terminal characters are not square (typically ~1:2 width:height ratio).

**Solution**: Scale image with aspect correction before rendering.

```ocaml
let terminal_aspect_ratio = 2.0  (* Typical: chars are 2x taller than wide *)

let scale_for_terminal img target_width target_height =
  (* Adjust target height to compensate for character aspect ratio *)
  let adjusted_height = int_of_float (
    float_of_int target_height *. terminal_aspect_ratio
  ) in
  scale_image img target_width adjusted_height
```

### Challenge 3: Sixel Support Detection

**Problem**: Not all terminals support Sixel.

**Solution**: Runtime detection with fallback.

```ocaml
let detect_sixel_support () =
  (* Method 1: Check TERM variable *)
  let term_supports = match Sys.getenv_opt "TERM" with
    | Some s when String.contains s "mlterm" -> true
    | Some s when String.contains s "xterm" -> true  (* Maybe *)
    | _ -> false
  in

  (* Method 2: Query terminal *)
  (* Send DA1 (Device Attributes) request: \033[c *)
  (* Read response: look for "4" in capabilities (Sixel) *)

  (* Conservative: only use Sixel if MIAOU_SIXEL=1 env var set *)
  term_supports && Sys.getenv_opt "MIAOU_SIXEL" = Some "1"
```

### Challenge 4: Performance

**Problem**: Image decoding and rendering can be slow.

**Solutions**:
- Cache rendered output (don't re-render on every frame)
- Load images asynchronously in background
- Use smaller images when possible

```ocaml
type t = {
  source: image_source;
  cached_render: string option ref;  (* Cache terminal rendering *)
  width: int;
  height: int;
}

let render t ~focus =
  match !(t.cached_render) with
  | Some cached -> cached
  | None ->
      let rendered = render_blocks (load_image t.source) t.width t.height in
      t.cached_render := Some rendered;
      rendered

(* Invalidate cache when source changes *)
let set_source t source =
  t.source <- source;
  t.cached_render := None
```

---

## Testing Strategy

### Unit Tests:

```ocaml
let test_load_formats () =
  List.iter (fun (ext, path) ->
    let img = Image_widget.create ~source:(File path) ~width:20 ~height:10 () in
    check bool (ext ^ " loads") true (Image_widget.dimensions img = (20, 10))
  ) [
    ("bmp", "test/fixtures/test.bmp");
    ("png", "test/fixtures/test.png");
    ("jpg", "test/fixtures/test.jpg");
  ]

let test_qr_encodes_data () =
  let data = "https://tezos.com" in
  let img = Image_widget.create ~source:(QR data) ~width:30 ~height:30 () in
  let rendered = Image_widget.render img ~focus:false in
  (* QR code should be decodable back to original data *)
  (* Use external QR decoder to verify *)
  check bool "qr valid" true (is_valid_qr rendered data)

let test_aspect_ratio_preserved () =
  (* Load 100x50 image, request 40x20 with Contain *)
  let img = Image_widget.create
    ~source:(File "test/fixtures/wide.png")
    ~width:40
    ~height:20
    ~fit:Contain
    () in
  (* Should be 40 wide, 20 tall (or less if aspect preserved) *)
  (* Check that output doesn't exceed bounds *)
  let rendered = Image_widget.render img ~focus:false in
  let lines = String.split_on_char '\n' rendered in
  check int "height ok" true (List.length lines <= 20)
```

### Visual Regression Tests:

```ocaml
(* Use headless driver to capture terminal output *)
let test_visual_qr () =
  Headless_driver.set_size 50 30;
  let img = Image_widget.create
    ~source:(QR "TEST")
    ~width:20
    ~height:20
    () in
  Headless_driver.render (Image_widget.render img ~focus:false);
  let output = Headless_driver.get_screen_content () in

  (* Compare with golden reference *)
  check string "qr matches" (load_file "test/golden/qr_test.txt") output
```

### SDL Tests:

```ocaml
(* Capture SDL framebuffer and compare *)
let test_sdl_render_quality () =
  let renderer = create_test_renderer () in
  let img = Image_widget_sdl.create
    ~source:(File "test/fixtures/test.png")
    ~width:100
    ~height:100
    ~fit:Contain
    () in

  Image_widget_sdl.render_sdl img renderer ~x:0 ~y:0;

  let screenshot = capture_renderer renderer in
  let reference = load_image "test/fixtures/test_expected.png" in

  (* Check pixel similarity (allow for minor compression differences) *)
  check float "similarity" 0.99 (image_similarity screenshot reference)
```

---

## Performance Targets

| Operation | Target | Notes |
|-----------|--------|-------|
| Load BMP (100×100) | <10ms | Uncompressed format |
| Load PNG (100×100) | <50ms | Decompression overhead |
| Load JPEG (100×100) | <50ms | Decompression overhead |
| Render blocks (40×20) | <5ms | Unicode block conversion |
| Render ASCII (80×40) | <2ms | Simple brightness map |
| Render Sixel (200×200) | <20ms | Protocol encoding |
| SDL texture creation | <10ms | GPU upload |
| SDL render | <1ms | GPU accelerated |
| QR generation (256 bytes) | <20ms | Matrix calculation |

---

## Dependencies to Add

```lisp
;; dune-project
(depends
  ...
  (camlimages (>= 5.0.4))    ;; Image I/O and manipulation
  (qrc (>= 0.1.0))            ;; QR code generation
  (tsdl-image (>= 0.5))       ;; SDL_image bindings (for SDL backend)
)
```

**Alternatives considered**:
- `stb_image` bindings - Lighter (single C file), but needs C binding work
- `imagelib` - Pure OCaml, but limited format support
- **Chosen: `camlimages`** - Comprehensive, well-maintained, good OCaml integration

---

## Integration with Existing Code

### Terminal Driver:

```ocaml
(* In lambda_term_driver.ml *)

let render_image img =
  (* Check if Sixel supported *)
  if Image_widget.supports_sixel () then
    Image_widget.render img ~focus ~mode:Sixel
  else
    Image_widget.render img ~focus ~mode:Blocks
```

### SDL Driver:

```ocaml
(* In sdl_driver.ml *)

let render_image_widget img x y =
  Image_widget_sdl.render_sdl img renderer ~x ~y
```

### Page Integration:

```ocaml
(* Example: Wallet page with QR code *)

module Wallet_page : PAGE_SIG = struct
  type state = {
    address: string;
    qr: Image_widget.t;
  }

  let init () =
    let address = "tz1abc...xyz" in
    let qr = Image_widget.create
      ~source:(QR address)
      ~width:30
      ~height:30
      () in
    { address; qr }

  let view st ~focus ~size =
    String.concat "\n" [
      "Your Wallet Address:";
      "";
      st.address;
      "";
      Image_widget.render st.qr ~focus;
      "";
      "Scan QR code to import";
    ]
end
```

---

## Demo Page

```ocaml
(* Add to example/demo_lib.ml *)

module Images_demo_page : PAGE_SIG = struct
  type state = {
    qr: Image_widget.t;
    logo: Image_widget.t;
    photo: Image_widget.t;
    gif: Gif_widget.t option;  (* Optional if GIF support added *)
  }

  let init () =
    {
      qr = Image_widget.create
        ~source:(QR "https://octez.tezos.com")
        ~width:25
        ~height:25
        ();

      logo = Image_widget.create
        ~source:(File "assets/tezos_logo.png")
        ~width:40
        ~height:15
        ~fit:Contain
        ();

      photo = Image_widget.create
        ~source:(File "assets/screenshot.jpg")
        ~width:60
        ~height:20
        ~fit:Cover
        ();

      gif = None;  (* TODO: Add animated GIF example *)
    }

  let view st ~focus ~size =
    let header = "Image Widgets Demo" in
    let sep = String.make 80 '─' in

    String.concat "\n" [
      header;
      sep;
      "";
      "QR Code (generated):";
      Image_widget.render st.qr ~focus;
      "";
      sep;
      "";
      "PNG Logo (loaded from file):";
      Image_widget.render st.logo ~focus;
      "";
      sep;
      "";
      "JPEG Photo (scaled to fit):";
      Image_widget.render st.photo ~focus;
      "";
      sep;
      "Press 'q' to quit";
    ]

  (* ... handle_key, etc. ... *)
end
```

---

## Success Criteria

### Functional:
- [ ] Load BMP, PNG, JPEG images from files
- [ ] Generate QR codes from strings
- [ ] Render in terminal using Unicode blocks
- [ ] Render in SDL with native quality
- [ ] Sixel support (if terminal capable)
- [ ] Fit modes work (Contain, Cover, Stretch, Original)
- [ ] Aspect ratio preserved correctly
- [ ] All widgets have complete `.mli` files

### Quality:
- [ ] QR codes are scannable on phone camera
- [ ] Images recognizable in terminal (not just noise)
- [ ] SDL rendering is pixel-perfect
- [ ] No crashes on malformed images
- [ ] Graceful fallback if image fails to load

### Performance:
- [ ] Image loading <50ms for typical images
- [ ] Terminal rendering <5ms for typical size
- [ ] SDL rendering <1ms per frame
- [ ] No memory leaks (test with valgrind)

### Documentation:
- [ ] Each widget has usage example in `.mli`
- [ ] Demo page shows all features
- [ ] README updated with image widget examples

---

## Why This Is A Differentiator

### Mosaic Doesn't Have This:
- ❌ No image loading/display
- ❌ No QR code support
- ❌ No multi-backend image rendering

### MIAOU Will Be Unique:
- ✅ **Only TUI framework with native image support**
- ✅ **Multi-backend** (Terminal + SDL = best of both)
- ✅ **QR codes** - killer feature for crypto/wallet UIs
- ✅ **Branding** - show logos, not just text

### Marketing Angle:
> "MIAOU: The only OCaml TUI framework with built-in image display. Show QR codes, logos, diagrams, and photos directly in your terminal or SDL window."

---

## Future Enhancements (Post-v1)

- [ ] **Webcam capture** - Display camera feed in TUI (Sixel)
- [ ] **Video playback** - Frame-by-frame video rendering
- [ ] **SVG support** - Vector graphics → rasterize to display
- [ ] **Image editing** - Crop, resize, filters in TUI
- [ ] **Chart export** - Save charts as PNG (charts → images)
- [ ] **Screenshot capture** - Capture current TUI as image

---

## Estimated LOC

- `image_widget.ml`: ~400 LOC (terminal backend)
- `image_widget_sdl.ml`: ~200 LOC (SDL backend)
- `gif_widget.ml`: ~150 LOC (optional)
- `image_utils.ml`: ~200 LOC (shared utilities)
- Tests: ~300 LOC
- **Total**: ~1,250 LOC

**Compared to**: Mosaic has 0 LOC for images (doesn't exist)

**ROI**: 1,250 LOC → Unique differentiating feature that no other OCaml TUI has!

---

## Timeline

**7 days for complete implementation**:

- **Day 1**: Image loading (camlimages integration, BMP/PNG/JPEG)
- **Day 2**: Terminal block rendering + color quantization
- **Day 3**: QR code generation and rendering
- **Day 4**: SDL backend implementation
- **Day 5**: Sixel protocol support (optional but cool)
- **Day 6**: GIF animation (optional)
- **Day 7**: Testing, demo page, documentation

**3-day MVP** (just QR codes + basic images):
- Day 1: Image loading + block rendering
- Day 2: QR code generation
- Day 3: SDL backend + demo

---

## Open Questions

1. **Sixel priority**: Is it worth the effort given limited terminal support?
   - **Recommendation**: Yes, but make it optional (env var controlled)

2. **Image caching**: Cache decoded images in memory or re-decode each time?
   - **Recommendation**: Cache for performance, add `clear_cache` function

3. **Async loading**: Load images in background thread?
   - **Recommendation**: Not in v1, keep simple. Add if performance issue.

4. **Image format priority**: Which formats are most important?
   - **Recommendation**: PNG (most common) > BMP (simplest) > JPEG (photos) > GIF (animations)

5. **SDL-only widgets**: Should some images be SDL-only (too complex for terminal)?
   - **Recommendation**: No, always provide terminal fallback (even if low quality)

---

This spec gives you **everything needed** to add image support to MIAOU and create a **unique selling point** that Mosaic can't match! 🎨📱
