(* SPDX-License-Identifier: MIT *)

let register () =
  let module W = Miaou_widgets_display.Widgets in
  let open Miaou_interfaces.Palette in
  let shade fg_code s = W.fg fg_code s in
  let shade_bg bg_code s = W.bg bg_code s in
  let muted s = W.dim (shade 249 s) in
  let palette : t =
    {
      fg_primary = shade 33;
      fg_secondary = shade 39;
      fg_muted = muted;
      bg_primary = shade_bg 24;
      fg_stealth = shade 240;
      bg_stealth = shade_bg 236;
      fg_slate = shade 67;
      bg_slate = shade_bg 17;
      fg_steel = shade 81;
      bg_steel = shade_bg 24;
      fg_white = shade 15;
      bg_white = shade_bg 15;
      purple_gradient = (fun s -> W.fg 177 s);
      purple_gradient_at =
        (fun _dir ~total_visible:_ ~start_pos:_ s -> W.fg 171 s);
      purple_gradient_line = (fun _dir s -> W.bg 53 (W.fg 15 s));
      fg_success = shade 118;
      fg_error = shade 203;
      selection_bg = (fun s -> W.bg 25 s);
      selection_fg = (fun s -> W.fg 231 s);
      fixed_region_bg = (fun s -> W.bg 237 s);
      header_bg = (fun s -> W.bg 61 (W.fg 231 s));
    }
  in
  Miaou_interfaces.Palette.set palette
