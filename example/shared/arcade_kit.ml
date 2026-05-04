(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(* ---------- Particles ---------- *)

module Particles = struct
  type t = {
    capacity : int;
    xs : float array;
    ys : float array;
    vxs : float array;
    vys : float array;
    lives : float array;
    life0s : float array;
    hues : int array;
    alive : bool array;
    mutable count : int;
    mutable next : int;
  }

  let create ~capacity =
    {
      capacity;
      xs = Array.make capacity 0.0;
      ys = Array.make capacity 0.0;
      vxs = Array.make capacity 0.0;
      vys = Array.make capacity 0.0;
      lives = Array.make capacity 0.0;
      life0s = Array.make capacity 1.0;
      hues = Array.make capacity 0;
      alive = Array.make capacity false;
      count = 0;
      next = 0;
    }

  let clear t =
    Array.fill t.alive 0 t.capacity false ;
    t.count <- 0 ;
    t.next <- 0

  let alive_count t = t.count

  (* Find an open slot, recycling oldest if full. Cheap because next walks
     the ring forwards. *)
  let acquire t =
    let i = t.next in
    if not t.alive.(i) then t.count <- t.count + 1 ;
    t.next <- (i + 1) mod t.capacity ;
    i

  let spawn t ~x ~y ~vx ~vy ~life ~hue =
    let i = acquire t in
    t.xs.(i) <- x ;
    t.ys.(i) <- y ;
    t.vxs.(i) <- vx ;
    t.vys.(i) <- vy ;
    t.lives.(i) <- life ;
    t.life0s.(i) <- (if life > 0.0 then life else 1.0) ;
    t.hues.(i) <- hue ;
    t.alive.(i) <- true

  let spawn_burst t ~x ~y ~n ~speed ~life ~hue ~rng =
    for _ = 1 to n do
      let theta = Random.State.float rng (2.0 *. Float.pi) in
      let s = speed *. (0.3 +. (0.7 *. Random.State.float rng 1.0)) in
      let l = life *. (0.6 +. (0.8 *. Random.State.float rng 1.0)) in
      spawn t ~x ~y ~vx:(s *. cos theta) ~vy:(s *. sin theta) ~life:l ~hue
    done

  let tick t ~dt ~ax ~ay =
    let cap = t.capacity in
    for i = 0 to cap - 1 do
      if t.alive.(i) then begin
        let l = t.lives.(i) -. dt in
        if l <= 0.0 then begin
          t.alive.(i) <- false ;
          t.count <- t.count - 1
        end
        else begin
          t.lives.(i) <- l ;
          t.vxs.(i) <- t.vxs.(i) +. (ax *. dt) ;
          t.vys.(i) <- t.vys.(i) +. (ay *. dt) ;
          t.xs.(i) <- t.xs.(i) +. (t.vxs.(i) *. dt) ;
          t.ys.(i) <- t.ys.(i) +. (t.vys.(i) *. dt)
        end
      end
    done

  let iter t ~f =
    let cap = t.capacity in
    for i = 0 to cap - 1 do
      if t.alive.(i) then begin
        let life01 =
          if t.life0s.(i) > 0.0 then
            Float.max 0.0 (Float.min 1.0 (t.lives.(i) /. t.life0s.(i)))
          else 0.0
        in
        f ~x:t.xs.(i) ~y:t.ys.(i) ~life01 ~hue:t.hues.(i)
      end
    done
end

(* ---------- Hue ramps ---------- *)

module Hue = struct
  type ramp = string array

  let cyan =
    [|
      "38;5;17";
      "38;5;18";
      "38;5;19";
      "38;5;20";
      "38;5;26";
      "38;5;33";
      "38;5;39";
      "38;5;45";
      "38;5;51";
      "38;5;87";
      "38;5;123";
      "38;5;195";
    |]

  let magenta =
    [|
      "38;5;52";
      "38;5;53";
      "38;5;89";
      "38;5;90";
      "38;5;126";
      "38;5;127";
      "38;5;163";
      "38;5;164";
      "38;5;200";
      "38;5;201";
      "38;5;213";
      "38;5;225";
    |]

  let amber =
    [|
      "38;5;52";
      "38;5;94";
      "38;5;130";
      "38;5;166";
      "38;5;172";
      "38;5;208";
      "38;5;214";
      "38;5;220";
      "38;5;221";
      "38;5;226";
      "38;5;227";
      "38;5;229";
    |]

  let sand =
    [|
      "38;5;58";
      "38;5;94";
      "38;5;100";
      "38;5;136";
      "38;5;142";
      "38;5;143";
      "38;5;179";
      "38;5;180";
      "38;5;186";
      "38;5;187";
      "38;5;222";
      "38;5;229";
    |]

  let lava =
    [|
      "38;5;52";
      "38;5;88";
      "38;5;124";
      "38;5;160";
      "38;5;196";
      "38;5;202";
      "38;5;208";
      "38;5;214";
      "38;5;220";
      "38;5;226";
      "38;5;227";
      "38;5;231";
    |]

  let ice =
    [|
      "38;5;17";
      "38;5;19";
      "38;5;25";
      "38;5;31";
      "38;5;38";
      "38;5;44";
      "38;5;51";
      "38;5;87";
      "38;5;123";
      "38;5;159";
      "38;5;195";
      "38;5;231";
    |]

  let grass =
    [|
      "38;5;22";
      "38;5;28";
      "38;5;34";
      "38;5;70";
      "38;5;76";
      "38;5;112";
      "38;5;118";
      "38;5;148";
      "38;5;154";
      "38;5;190";
      "38;5;226";
      "38;5;229";
    |]

  let pick (r : ramp) ~life01 =
    let n = Array.length r in
    if n = 0 then ""
    else
      let f = Float.max 0.0 (Float.min 1.0 life01) in
      let i = int_of_float (f *. float_of_int (n - 1)) in
      r.(i)

  (* Crude RGB approximation tied to the same xterm-256 palette so callers
     using pixel-buffer rendering get colours close to the SGR ramp above.
     Kept in sync visually rather than algorithmically — this is intentional. *)
  let rgb_of_ramp_name name ~i ~n =
    let f = float_of_int i /. float_of_int (max 1 (n - 1)) in
    let lerp a b =
      int_of_float (float_of_int a +. ((float_of_int b -. float_of_int a) *. f))
    in
    let lerp3 (r0, g0, b0) (r1, g1, b1) =
      (lerp r0 r1, lerp g0 g1, lerp b0 b1)
    in
    match name with
    | "cyan" -> lerp3 (10, 20, 60) (200, 240, 255)
    | "magenta" -> lerp3 (60, 0, 60) (255, 200, 240)
    | "amber" -> lerp3 (60, 30, 0) (255, 240, 180)
    | "sand" -> lerp3 (60, 50, 30) (240, 230, 180)
    | "lava" -> lerp3 (80, 0, 0) (255, 240, 220)
    | "ice" -> lerp3 (10, 20, 70) (240, 250, 255)
    | "grass" -> lerp3 (10, 50, 10) (220, 240, 200)
    | _ -> lerp3 (40, 40, 40) (240, 240, 240)

  (* Identify ramp by reference equality — cheap and sufficient. *)
  let name_of (r : ramp) =
    if r == cyan then "cyan"
    else if r == magenta then "magenta"
    else if r == amber then "amber"
    else if r == sand then "sand"
    else if r == lava then "lava"
    else if r == ice then "ice"
    else if r == grass then "grass"
    else "amber"

  let rgb r ~life01 =
    let n = Array.length r in
    if n = 0 then (200, 200, 200)
    else
      let f = Float.max 0.0 (Float.min 1.0 life01) in
      let i = int_of_float (f *. float_of_int (n - 1)) in
      rgb_of_ramp_name (name_of r) ~i ~n
end

(* ---------- Screen FX ---------- *)

module Screen_fx = struct
  type t = {
    mutable flash_a : float;
    mutable flash_decay : float;
    mutable shake_mag : float;
    mutable shake_decay : float;
    mutable shake_seed : int;
  }

  let create () =
    {
      flash_a = 0.0;
      flash_decay = 0.0;
      shake_mag = 0.0;
      shake_decay = 0.0;
      shake_seed = 0;
    }

  let flash t ~intensity ~duration =
    let i = Float.max 0.0 (Float.min 1.0 intensity) in
    if i > t.flash_a then begin
      t.flash_a <- i ;
      t.flash_decay <- (if duration > 0.0 then i /. duration else i)
    end

  let shake t ~magnitude ~duration =
    let m = Float.max 0.0 magnitude in
    if m > t.shake_mag then begin
      t.shake_mag <- m ;
      t.shake_decay <- (if duration > 0.0 then m /. duration else m)
    end

  let tick t ~dt =
    if t.flash_a > 0.0 then begin
      t.flash_a <- Float.max 0.0 (t.flash_a -. (t.flash_decay *. dt))
    end ;
    if t.shake_mag > 0.0 then begin
      t.shake_mag <- Float.max 0.0 (t.shake_mag -. (t.shake_decay *. dt)) ;
      t.shake_seed <- t.shake_seed + 1
    end

  let flash_alpha t = t.flash_a

  let shake_offset t =
    if t.shake_mag <= 0.0 then (0, 0)
    else
      (* deterministic per-frame jitter — no Random.State allocation *)
      let s = t.shake_seed in
      let dx_phase = float_of_int (((s * 1103515245) + 12345) land 0xffff) in
      let dy_phase = float_of_int (((s * 22695477) + 1) land 0xffff) in
      let dx = int_of_float (t.shake_mag *. cos (dx_phase *. 0.0001)) in
      let dy = int_of_float (t.shake_mag *. sin (dy_phase *. 0.0001)) in
      (dx, dy)
end

(* ---------- Persistent score store ---------- *)

module Score_store = struct
  let dir () =
    let base =
      match Sys.getenv_opt "XDG_STATE_HOME" with
      | Some p when p <> "" -> p
      | _ -> (
          match Sys.getenv_opt "HOME" with
          | Some h -> Filename.concat h ".local/state"
          | None -> "/tmp")
    in
    Filename.concat base "miaou"

  let path ~demo = Filename.concat (dir ()) (demo ^ ".score")

  let mkdir_p p =
    let rec go p =
      if Sys.file_exists p then ()
      else begin
        let parent = Filename.dirname p in
        if parent <> p then go parent ;
        try Unix.mkdir p 0o755 with _ -> ()
      end
    in
    go p

  let load ~demo =
    let p = path ~demo in
    try
      let ic = open_in p in
      let line = input_line ic in
      close_in ic ;
      try int_of_string (String.trim line) with _ -> 0
    with _ -> 0

  let save ~demo score =
    try
      mkdir_p (dir ()) ;
      let p = path ~demo in
      let oc = open_out p in
      output_string oc (string_of_int score) ;
      output_char oc '\n' ;
      close_out oc
    with _ -> ()

  let record ~demo score =
    let prev = load ~demo in
    if score > prev then begin
      save ~demo score ;
      score
    end
    else prev
end

(* ---------- Pixel mode ---------- *)

module Pixel_mode = struct
  module Caps = Miaou_widgets_display.Terminal_caps

  let resolve ?(env_var = "MIAOU_PIXEL_MODE") () =
    match Sys.getenv_opt env_var with
    | Some "sixel" -> Caps.Sixel
    | Some "octant" -> Caps.Octant
    | Some "sextant" -> Caps.Sextant
    | Some "half_block" -> Caps.Half_block
    | Some "braille" -> Caps.Braille
    | _ -> Caps.Octant
end
