(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

module C = Miaou_canvas.Canvas
module Anim = Miaou_helpers.Animation
open Model

(* -- Rendering ---------------------------------------------------------- *)

(* Style helpers with explicit background so draw_text calls don't clobber
   the background set by fill_rect (canvas cells are fully explicit: every
   set_char overwrites fg, bg, and char, so bg=-1 erases the filled bg). *)

let style_of ?(bg = -1) fg = {C.default_style with fg; bg}

let bold_style_of ?(bg = -1) fg = {C.default_style with fg; bg; bold = true}

let draw_background s c =
  let rows = C.rows c in
  let cols = C.cols c in
  let theme = theme_for_level s.level in
  C.fill_rect
    c
    ~row:1
    ~col:1
    ~width:(max 0 (cols - 2))
    ~height:(max 0 (rows - 2))
    ~char:" "
    ~style:{C.default_style with bg = theme.bg} ;
  for row = 1 to rows - 2 do
    for col = 1 to cols - 2 do
      let n = (row * 17) + (col * 11) + (s.frame * 3) + (s.level * 7) in
      if n mod 23 = 0 then
        C.set_char
          c
          ~row
          ~col
          ~char:"."
          ~style:
            {C.default_style with fg = theme.dust_a; bg = theme.bg; dim = true}
      else if n mod 37 = 0 then
        C.set_char
          c
          ~row
          ~col
          ~char:"'"
          ~style:
            {C.default_style with fg = theme.dust_b; bg = theme.bg; dim = true}
    done
  done

let draw_title_screen s c =
  let rows = C.rows c in
  let cols = C.cols c in
  C.clear c ;
  C.fill_rect
    c
    ~row:0
    ~col:0
    ~width:cols
    ~height:rows
    ~char:" "
    ~style:{C.default_style with bg = 17} ;
  for row = 0 to rows - 1 do
    for col = 0 to cols - 1 do
      let n = (row * 37) + (col * 17) + (s.frame * 5) in
      if n mod 97 = 0 then
        C.set_char
          c
          ~row
          ~col
          ~char:"."
          ~style:{C.default_style with fg = 251; bg = 17}
      else if n mod 131 = 0 then
        C.set_char
          c
          ~row
          ~col
          ~char:"*"
          ~style:{C.default_style with fg = 159; bg = 17; bold = true}
    done
  done ;
  let title = "MIAOU INVADERS" in
  let sub = "Arcade demo for Miaou" in
  let start = "Press Enter to start" in
  let demo = "Press d for AI demo mode" in
  let title_col = max 1 ((cols - String.length title) / 2) in
  let sub_col = max 1 ((cols - String.length sub) / 2) in
  let start_col = max 1 ((cols - String.length start) / 2) in
  let demo_col = max 1 ((cols - String.length demo) / 2) in
  let title_bg = 17 in
  let base_row = max 4 ((rows / 2) - 3) in
  C.draw_text
    c
    ~row:base_row
    ~col:title_col
    ~style:(bold_style_of ~bg:title_bg 123)
    title ;
  C.draw_text
    c
    ~row:(base_row + 2)
    ~col:sub_col
    ~style:(style_of ~bg:title_bg 153)
    sub ;
  if s.frame / 20 mod 2 = 0 then
    C.draw_text
      c
      ~row:(base_row + 4)
      ~col:start_col
      ~style:(bold_style_of ~bg:title_bg 229)
      start ;
  C.draw_text
    c
    ~row:(base_row + 6)
    ~col:demo_col
    ~style:(style_of ~bg:title_bg 151)
    demo ;
  let footer = "Esc:back" in
  C.draw_text
    c
    ~row:(rows - 1)
    ~col:(max 1 (cols - 10))
    ~style:(style_of ~bg:title_bg 240)
    footer

let camera_offset s =
  if s.shake <= 0.0 then (0, 0)
  else
    let amp = max 1 (int_of_float (2.0 *. (s.shake /. 0.35))) in
    let x = if s.frame mod 2 = 0 then amp else -amp in
    let y = if s.frame / 2 mod 2 = 0 then 1 else -1 in
    (x, y)

let draw_game s c =
  let rows = C.rows c in
  let cols = C.cols c in
  if s.show_title then draw_title_screen s c
  else begin
    let cam_x, cam_y = camera_offset s in
    let theme = theme_for_level s.level in
    (* Theme-bg-aware style helpers: every canvas cell must carry an explicit
       background so draw_text doesn't clobber the fill_rect background. *)
    let gst fg = style_of ~bg:theme.bg fg in
    let gbst fg = bold_style_of ~bg:theme.bg fg in
    C.clear c ;
    draw_background s c ;

    C.draw_box
      c
      ~row:0
      ~col:0
      ~width:cols
      ~height:rows
      ~border:Single
      ~style:(gst 240) ;

    let kind = shot_kind_of s.shot_color in
    let power = if s.shot_power = 0 then "-" else string_of_int s.shot_power in
    let weapon_fg =
      match s.shot_color with None -> 81 | Some color -> bonus_fg color
    in
    let hud_main =
      Printf.sprintf
        " Score:%d  Lives:%d  Lvl:%d  Weapon:%s P%s  BG:%s %s "
        s.score
        s.lives
        s.level
        (shot_name kind)
        power
        theme.name
        (if s.ai_mode then "[AI]" else "")
    in
    let hud_sub =
      let bonus_label =
        match s.shot_color with
        | None -> "None"
        | Some Ruby -> "Ruby"
        | Some Emerald -> "Emerald"
        | Some Sapphire -> "Sapphire"
      in
      Printf.sprintf " Driver: Matrix Layers  Bonus:%s " bonus_label
    in

    (match s.phase with
    | Playing -> ()
    | Paused ->
        let msg = "PAUSED" in
        let sub = "Press p to resume" in
        let col = max 1 ((cols - String.length msg) / 2) in
        let sub_col = max 1 ((cols - String.length sub) / 2) in
        let row = rows / 2 in
        C.draw_text c ~row ~col ~style:(gbst 226) msg ;
        C.draw_text c ~row:(row + 1) ~col:sub_col ~style:(gst 250) sub
    | Wave_clear anim ->
        let fg = if Anim.value anim > 0.5 then 46 else 120 in
        let msg = Printf.sprintf "WAVE %d CLEAR" s.level in
        let col = max 1 ((cols - String.length msg) / 2) in
        C.draw_text c ~row:(rows / 2) ~col ~style:(gbst fg) msg
    | Game_over anim ->
        let fg = if Anim.value anim > 0.5 then 196 else 203 in
        let msg = "GAME OVER" in
        let col = max 1 ((cols - String.length msg) / 2) in
        let row = rows / 2 in
        C.draw_text c ~row ~col ~style:(gbst fg) msg ;
        let sub = "Press 'r' to restart" in
        let sub_col = max 1 ((cols - String.length sub) / 2) in
        C.draw_text c ~row:(row + 1) ~col:sub_col ~style:(gst 245) sub) ;

    (match
       List.find_opt (fun (a : alien) -> a.alive && a.kind = Boss) s.aliens
     with
    | None -> ()
    | Some boss ->
        let ratio =
          if boss.hp_max <= 0 then 0.0
          else float_of_int boss.hp /. float_of_int boss.hp_max
        in
        let bar_w = max 12 (min (cols - 18) 42) in
        let filled = int_of_float (ratio *. float_of_int bar_w) in
        let empty = max 0 (bar_w - filled) in
        let bar = "[" ^ String.make filled '#' ^ String.make empty '-' ^ "]" in
        let label = Printf.sprintf " BOSS HP %d/%d " boss.hp boss.hp_max in
        let col = max 1 ((cols - String.length bar) / 2) in
        C.draw_text c ~row:1 ~col ~style:(gbst 196) bar ;
        C.draw_text
          c
          ~row:1
          ~col:(max 1 (col - String.length label - 1))
          ~style:(gst 209)
          label) ;

    (match s.boss_intro with
    | None -> ()
    | Some anim ->
        let v = Anim.value anim in
        let fg = if int_of_float (v *. 20.0) mod 2 = 0 then 203 else 196 in
        let msg = Printf.sprintf "WARNING - BOSS LEVEL %d" s.level in
        let sub = "Survive the barrage and break the core" in
        let warning = C.create ~rows:2 ~cols in
        let msg_col = max 1 ((cols - String.length msg) / 2) in
        let sub_col = max 1 ((cols - String.length sub) / 2) in
        C.draw_text warning ~row:0 ~col:msg_col ~style:(gbst fg) msg ;
        C.draw_text warning ~row:1 ~col:sub_col ~style:(gst 229) sub ;
        C.compose
          ~dst:c
          ~layers:[{C.canvas = warning; row = 3; col = 0; opaque = false}]) ;

    List.iter
      (fun a ->
        if a.alive then begin
          let col = Float.to_int a.pos.x - 1 + cam_x in
          let row = Float.to_int a.pos.y + cam_y in
          match a.kind with
          | Grunt ->
              let ch = alien_chars.(a.row mod Array.length alien_chars) in
              let fg =
                match a.row mod 3 with 0 -> 196 | 1 -> 208 | _ -> 226
              in
              C.draw_text c ~row ~col ~style:(gbst fg) ch
          | Boss ->
              let hp_ratio =
                if a.hp_max <= 0 then 0.0
                else float_of_int a.hp /. float_of_int a.hp_max
              in
              let fg =
                if hp_ratio > 0.66 then 203
                else if hp_ratio > 0.33 then 214
                else 196
              in
              C.draw_text c ~row ~col ~style:(gbst fg) boss_char
        end)
      s.aliens ;

    List.iter
      (fun (b : projectile) ->
        let col = Float.to_int b.ppos.x + cam_x in
        let row = Float.to_int b.ppos.y + cam_y in
        C.draw_text c ~row ~col ~style:(gbst b.fg) b.glyph)
      s.bullets ;

    List.iter
      (fun (b : projectile) ->
        let col = Float.to_int b.ppos.x + cam_x in
        let row = Float.to_int b.ppos.y + cam_y in
        C.draw_text c ~row ~col ~style:(gbst b.fg) b.glyph)
      s.alien_bullets ;

    List.iter
      (fun (b : bonus) ->
        let col = Float.to_int b.bpos.x + cam_x in
        let row = Float.to_int b.bpos.y + cam_y in
        let pulse =
          if (s.frame + int_of_float (b.phase *. 10.0)) mod 2 = 0 then "$"
          else "S"
        in
        C.draw_text c ~row ~col ~style:(gbst (bonus_fg b.color)) pulse)
      s.bonuses ;

    List.iter
      (fun e ->
        let fg = Anim.lerp_int e.efg_start e.efg_end e.anim in
        let ch =
          let v = Anim.value e.anim in
          if v < 0.2 then "*"
          else if v < 0.45 then e.echar
          else if v < 0.7 then "+"
          else "."
        in
        let col = Float.to_int e.epos.x + cam_x in
        let row = Float.to_int e.epos.y + cam_y in
        C.draw_text c ~row ~col ~style:(gbst fg) ch)
      s.explosions ;

    List.iter
      (fun p ->
        let fg = if Anim.value p.lanim < 0.5 then 118 else 194 in
        let col = Float.to_int p.lpos.x - 3 + cam_x in
        let row = Float.to_int p.lpos.y + cam_y in
        C.draw_text c ~row ~col ~style:(gbst fg) "+1 LIFE")
      s.life_popups ;

    (match s.phase with
    | Game_over _ -> ()
    | _ ->
        let base = ship_sprite s.shot_color s.shot_power in
        let sprite =
          match s.ship_morph with
          | Some _ when s.frame mod 4 = 0 || s.frame mod 4 = 1 -> base_ship_char
          | _ -> base
        in
        let half = String.length sprite / 2 in
        let ship_col = Float.to_int s.ship_x - half + cam_x in
        let ship_row = ship_row_for s.field_h + cam_y in
        let ship_fg =
          match s.shot_color with None -> 46 | Some color -> bonus_fg color
        in
        (match s.ship_morph with
        | None -> ()
        | Some morph ->
            let v = Anim.value morph in
            let pulse_fg = if v < 0.5 then 229 else 255 in
            let left_col = ship_col - 1 in
            let right_col = ship_col + String.length sprite in
            let aura = if s.frame mod 2 = 0 then "*" else "+" in
            C.draw_text
              c
              ~row:ship_row
              ~col:left_col
              ~style:(gbst pulse_fg)
              aura ;
            C.draw_text
              c
              ~row:ship_row
              ~col:right_col
              ~style:(gbst pulse_fg)
              aura ;
            if ship_row > 1 then
              C.draw_text
                c
                ~row:(ship_row - 1)
                ~col:(ship_col + half)
                ~style:(gst pulse_fg)
                "^") ;
        C.draw_text c ~row:ship_row ~col:ship_col ~style:(gbst ship_fg) sprite) ;

    let hint =
      "<-/->/h/l:move  Space:fire  p:pause  Collect $ for power  r:restart  \
       Esc:back"
    in

    (* HUD panel composited on top of gameplay. *)
    let hud_w =
      min (cols - 2) (max (String.length hud_main) (String.length hud_sub) + 4)
    in
    let hud_h = 4 in
    if hud_w > 8 && rows > 6 then begin
      let hud = C.create ~rows:hud_h ~cols:hud_w in
      let hud_row = max (ship_row_for s.field_h + 1) (rows - hud_h - 1) in
      let hud_col = max 1 ((cols - hud_w) / 2) in
      C.draw_box
        hud
        ~row:0
        ~col:0
        ~width:hud_w
        ~height:hud_h
        ~border:Rounded
        ~style:(style_of ~bg:236 250) ;
      C.fill_rect
        hud
        ~row:1
        ~col:1
        ~width:(hud_w - 2)
        ~height:(hud_h - 2)
        ~char:" "
        ~style:{C.default_style with bg = 236} ;
      C.draw_text
        hud
        ~row:1
        ~col:2
        ~style:(bold_style_of ~bg:236 weapon_fg)
        hud_main ;
      C.draw_text hud ~row:2 ~col:2 ~style:(style_of ~bg:236 252) hud_sub ;
      C.compose
        ~dst:c
        ~layers:[{C.canvas = hud; row = hud_row; col = hud_col; opaque = true}]
    end ;

    let hint_col = max 1 ((cols - String.length hint) / 2) in
    C.draw_text c ~row:(rows - 1) ~col:hint_col ~style:(gst 240) hint
  end
