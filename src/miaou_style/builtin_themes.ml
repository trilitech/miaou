(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

(** Built-in themes inspired by popular color schemes.

    These themes are embedded directly in the library for easy access without
    requiring external files. Themes can be listed with [list_builtin] and
    loaded with [get_builtin].

    Color mappings use the 256-color palette for broad terminal compatibility.
    Some themes have borders (default_border_style: "Rounded") while others
    use borderless style (default_border_style: "None") for a cleaner look.
*)

(** Theme descriptors with metadata *)
type builtin_theme = {
  id : string;
  name : string;
  description : string;
  dark_mode : bool;
  borderless : bool;
}

let all_themes =
  [
    (* Dark themes *)
    {
      id = "catppuccin-mocha";
      name = "Catppuccin Mocha";
      description = "Soothing pastel dark theme";
      dark_mode = true;
      borderless = false;
    };
    {
      id = "dracula";
      name = "Dracula";
      description = "Dark theme with vibrant colors";
      dark_mode = true;
      borderless = false;
    };
    {
      id = "nord";
      name = "Nord";
      description = "Arctic, north-bluish dark theme";
      dark_mode = true;
      borderless = false;
    };
    {
      id = "gruvbox-dark";
      name = "Gruvbox Dark";
      description = "Retro groove dark theme";
      dark_mode = true;
      borderless = false;
    };
    {
      id = "tokyonight";
      name = "Tokyo Night";
      description = "Clean dark theme inspired by Tokyo nights";
      dark_mode = true;
      borderless = false;
    };
    {
      id = "opencode";
      name = "OpenCode";
      description = "Clean borderless dark theme (OpenCode style)";
      dark_mode = true;
      borderless = true;
    };
    {
      id = "oled";
      name = "OLED";
      description =
        "True black background with soft pastel colors for OLED screens";
      dark_mode = true;
      borderless = true;
    };
    (* Light themes *)
    {
      id = "catppuccin-latte";
      name = "Catppuccin Latte";
      description = "Soothing pastel light theme";
      dark_mode = false;
      borderless = false;
    };
    {
      id = "nord-light";
      name = "Nord Light";
      description = "Arctic, north-bluish light theme";
      dark_mode = false;
      borderless = false;
    };
    {
      id = "gruvbox-light";
      name = "Gruvbox Light";
      description = "Retro groove light theme";
      dark_mode = false;
      borderless = false;
    };
    {
      id = "tokyonight-day";
      name = "Tokyo Night Day";
      description = "Clean light theme inspired by Tokyo days";
      dark_mode = false;
      borderless = false;
    };
    (* System theme *)
    {
      id = "system";
      name = "System";
      description = "Uses terminal's own colors and background";
      dark_mode = true;
      borderless = false;
    };
  ]

(** List all available built-in themes *)
let list_builtin () = all_themes

(** List just the theme IDs *)
let list_builtin_ids () = List.map (fun t -> t.id) all_themes

(** Get theme info by ID *)
let get_info id = List.find_opt (fun t -> t.id = id) all_themes

(* Generate JSON strings for each theme *)

let catppuccin_mocha_json =
  {|{
  "name": "Catppuccin Mocha",
  "dark_mode": true,
  "primary": { "fg": { "Fixed": 183 }, "bold": true },
  "secondary": { "fg": { "Fixed": 146 } },
  "accent": { "fg": { "Fixed": 212 } },
  "error": { "fg": { "Fixed": 211 } },
  "warning": { "fg": { "Fixed": 223 } },
  "success": { "fg": { "Fixed": 150 } },
  "info": { "fg": { "Fixed": 117 } },
  "text": { "fg": { "Fixed": 189 } },
  "text_muted": { "fg": { "Fixed": 146 }, "dim": true },
  "text_emphasized": { "fg": { "Fixed": 231 }, "bold": true },
  "background": { "bg": { "Fixed": 236 } },
  "background_secondary": { "bg": { "Fixed": 238 } },
  "border": { "fg": { "Fixed": 243 } },
  "border_focused": { "fg": { "Fixed": 183 }, "bold": true },
  "border_dim": { "fg": { "Fixed": 240 }, "dim": true },
  "selection": { "fg": { "Fixed": 231 }, "bg": { "Fixed": 238 } },
  "default_border_style": "Rounded",
  "rules": {}
}|}

let catppuccin_latte_json =
  {|{
  "name": "Catppuccin Latte",
  "dark_mode": false,
  "primary": { "fg": { "Fixed": 99 }, "bold": true },
  "secondary": { "fg": { "Fixed": 102 } },
  "accent": { "fg": { "Fixed": 133 } },
  "error": { "fg": { "Fixed": 160 } },
  "warning": { "fg": { "Fixed": 172 } },
  "success": { "fg": { "Fixed": 71 } },
  "info": { "fg": { "Fixed": 37 } },
  "text": { "fg": { "Fixed": 59 } },
  "text_muted": { "fg": { "Fixed": 102 }, "dim": true },
  "text_emphasized": { "fg": { "Fixed": 235 }, "bold": true },
  "background": { "bg": { "Fixed": 224 } },
  "background_secondary": { "bg": { "Fixed": 223 } },
  "border": { "fg": { "Fixed": 181 } },
  "border_focused": { "fg": { "Fixed": 99 }, "bold": true },
  "border_dim": { "fg": { "Fixed": 188 }, "dim": true },
  "selection": { "fg": { "Fixed": 235 }, "bg": { "Fixed": 188 } },
  "default_border_style": "Rounded",
  "rules": {}
}|}

let dracula_json =
  {|{
  "name": "Dracula",
  "dark_mode": true,
  "primary": { "fg": { "Fixed": 141 }, "bold": true },
  "secondary": { "fg": { "Fixed": 146 } },
  "accent": { "fg": { "Fixed": 212 } },
  "error": { "fg": { "Fixed": 203 } },
  "warning": { "fg": { "Fixed": 215 } },
  "success": { "fg": { "Fixed": 84 } },
  "info": { "fg": { "Fixed": 117 } },
  "text": { "fg": { "Fixed": 231 } },
  "text_muted": { "fg": { "Fixed": 146 }, "dim": true },
  "text_emphasized": { "fg": { "Fixed": 231 }, "bold": true },
  "background": { "bg": { "Fixed": 235 } },
  "background_secondary": { "bg": { "Fixed": 237 } },
  "border": { "fg": { "Fixed": 60 } },
  "border_focused": { "fg": { "Fixed": 141 }, "bold": true },
  "border_dim": { "fg": { "Fixed": 238 }, "dim": true },
  "selection": { "fg": { "Fixed": 231 }, "bg": { "Fixed": 60 } },
  "default_border_style": "Rounded",
  "rules": {}
}|}

let nord_json =
  {|{
  "name": "Nord",
  "dark_mode": true,
  "primary": { "fg": { "Fixed": 110 }, "bold": true },
  "secondary": { "fg": { "Fixed": 146 } },
  "accent": { "fg": { "Fixed": 139 } },
  "error": { "fg": { "Fixed": 131 } },
  "warning": { "fg": { "Fixed": 173 } },
  "success": { "fg": { "Fixed": 108 } },
  "info": { "fg": { "Fixed": 109 } },
  "text": { "fg": { "Fixed": 253 } },
  "text_muted": { "fg": { "Fixed": 146 }, "dim": true },
  "text_emphasized": { "fg": { "Fixed": 231 }, "bold": true },
  "background": { "bg": { "Fixed": 236 } },
  "background_secondary": { "bg": { "Fixed": 238 } },
  "border": { "fg": { "Fixed": 60 } },
  "border_focused": { "fg": { "Fixed": 110 }, "bold": true },
  "border_dim": { "fg": { "Fixed": 238 }, "dim": true },
  "selection": { "fg": { "Fixed": 231 }, "bg": { "Fixed": 60 } },
  "default_border_style": "Rounded",
  "rules": {}
}|}

let nord_light_json =
  {|{
  "name": "Nord Light",
  "dark_mode": false,
  "primary": { "fg": { "Fixed": 67 }, "bold": true },
  "secondary": { "fg": { "Fixed": 66 } },
  "accent": { "fg": { "Fixed": 139 } },
  "error": { "fg": { "Fixed": 131 } },
  "warning": { "fg": { "Fixed": 173 } },
  "success": { "fg": { "Fixed": 108 } },
  "info": { "fg": { "Fixed": 109 } },
  "text": { "fg": { "Fixed": 59 } },
  "text_muted": { "fg": { "Fixed": 66 }, "dim": true },
  "text_emphasized": { "fg": { "Fixed": 236 }, "bold": true },
  "background": { "bg": { "Fixed": 255 } },
  "background_secondary": { "bg": { "Fixed": 254 } },
  "border": { "fg": { "Fixed": 249 } },
  "border_focused": { "fg": { "Fixed": 67 }, "bold": true },
  "border_dim": { "fg": { "Fixed": 252 }, "dim": true },
  "selection": { "fg": { "Fixed": 236 }, "bg": { "Fixed": 252 } },
  "default_border_style": "Rounded",
  "rules": {}
}|}

let gruvbox_dark_json =
  {|{
  "name": "Gruvbox Dark",
  "dark_mode": true,
  "primary": { "fg": { "Fixed": 108 }, "bold": true },
  "secondary": { "fg": { "Fixed": 102 } },
  "accent": { "fg": { "Fixed": 175 } },
  "error": { "fg": { "Fixed": 167 } },
  "warning": { "fg": { "Fixed": 214 } },
  "success": { "fg": { "Fixed": 142 } },
  "info": { "fg": { "Fixed": 175 } },
  "text": { "fg": { "Fixed": 223 } },
  "text_muted": { "fg": { "Fixed": 102 }, "dim": true },
  "text_emphasized": { "fg": { "Fixed": 230 }, "bold": true },
  "background": { "bg": { "Fixed": 235 } },
  "background_secondary": { "bg": { "Fixed": 237 } },
  "border": { "fg": { "Fixed": 239 } },
  "border_focused": { "fg": { "Fixed": 108 }, "bold": true },
  "border_dim": { "fg": { "Fixed": 237 }, "dim": true },
  "selection": { "fg": { "Fixed": 230 }, "bg": { "Fixed": 239 } },
  "default_border_style": "Rounded",
  "rules": {}
}|}

let gruvbox_light_json =
  {|{
  "name": "Gruvbox Light",
  "dark_mode": false,
  "primary": { "fg": { "Fixed": 24 }, "bold": true },
  "secondary": { "fg": { "Fixed": 102 } },
  "accent": { "fg": { "Fixed": 133 } },
  "error": { "fg": { "Fixed": 124 } },
  "warning": { "fg": { "Fixed": 136 } },
  "success": { "fg": { "Fixed": 100 } },
  "info": { "fg": { "Fixed": 133 } },
  "text": { "fg": { "Fixed": 239 } },
  "text_muted": { "fg": { "Fixed": 102 }, "dim": true },
  "text_emphasized": { "fg": { "Fixed": 235 }, "bold": true },
  "background": { "bg": { "Fixed": 230 } },
  "background_secondary": { "bg": { "Fixed": 229 } },
  "border": { "fg": { "Fixed": 144 } },
  "border_focused": { "fg": { "Fixed": 24 }, "bold": true },
  "border_dim": { "fg": { "Fixed": 187 }, "dim": true },
  "selection": { "fg": { "Fixed": 235 }, "bg": { "Fixed": 187 } },
  "default_border_style": "Rounded",
  "rules": {}
}|}

let tokyonight_json =
  {|{
  "name": "Tokyo Night",
  "dark_mode": true,
  "primary": { "fg": { "Fixed": 111 }, "bold": true },
  "secondary": { "fg": { "Fixed": 103 } },
  "accent": { "fg": { "Fixed": 141 } },
  "error": { "fg": { "Fixed": 210 } },
  "warning": { "fg": { "Fixed": 179 } },
  "success": { "fg": { "Fixed": 149 } },
  "info": { "fg": { "Fixed": 117 } },
  "text": { "fg": { "Fixed": 153 } },
  "text_muted": { "fg": { "Fixed": 103 }, "dim": true },
  "text_emphasized": { "fg": { "Fixed": 231 }, "bold": true },
  "background": { "bg": { "Fixed": 234 } },
  "background_secondary": { "bg": { "Fixed": 236 } },
  "border": { "fg": { "Fixed": 60 } },
  "border_focused": { "fg": { "Fixed": 111 }, "bold": true },
  "border_dim": { "fg": { "Fixed": 238 }, "dim": true },
  "selection": { "fg": { "Fixed": 231 }, "bg": { "Fixed": 60 } },
  "default_border_style": "Rounded",
  "rules": {}
}|}

let tokyonight_day_json =
  {|{
  "name": "Tokyo Night Day",
  "dark_mode": false,
  "primary": { "fg": { "Fixed": 33 }, "bold": true },
  "secondary": { "fg": { "Fixed": 103 } },
  "accent": { "fg": { "Fixed": 128 } },
  "error": { "fg": { "Fixed": 161 } },
  "warning": { "fg": { "Fixed": 136 } },
  "success": { "fg": { "Fixed": 64 } },
  "info": { "fg": { "Fixed": 30 } },
  "text": { "fg": { "Fixed": 59 } },
  "text_muted": { "fg": { "Fixed": 103 }, "dim": true },
  "text_emphasized": { "fg": { "Fixed": 235 }, "bold": true },
  "background": { "bg": { "Fixed": 254 } },
  "background_secondary": { "bg": { "Fixed": 253 } },
  "border": { "fg": { "Fixed": 249 } },
  "border_focused": { "fg": { "Fixed": 33 }, "bold": true },
  "border_dim": { "fg": { "Fixed": 252 }, "dim": true },
  "selection": { "fg": { "Fixed": 235 }, "bg": { "Fixed": 252 } },
  "default_border_style": "Rounded",
  "rules": {}
}|}

(* OpenCode-style borderless theme - clean, minimal, no borders *)
let opencode_json =
  {|{
  "name": "OpenCode",
  "dark_mode": true,
  "primary": { "fg": { "Fixed": 216 }, "bold": true },
  "secondary": { "fg": { "Fixed": 245 } },
  "accent": { "fg": { "Fixed": 183 } },
  "error": { "fg": { "Fixed": 203 } },
  "warning": { "fg": { "Fixed": 220 } },
  "success": { "fg": { "Fixed": 77 } },
  "info": { "fg": { "Fixed": 183 } },
  "text": { "fg": { "Fixed": 252 } },
  "text_muted": { "fg": { "Fixed": 245 }, "dim": true },
  "text_emphasized": { "fg": { "Fixed": 231 }, "bold": true },
  "background": { "bg": { "Fixed": 234 } },
  "background_secondary": { "bg": { "Fixed": 236 } },
  "border": { "fg": { "Fixed": 236 } },
  "border_focused": { "fg": { "Fixed": 236 } },
  "border_dim": { "fg": { "Fixed": 236 }, "dim": true },
  "selection": { "fg": { "Fixed": 231 }, "bg": { "Fixed": 238 } },
  "default_border_style": "None",
  "rules": {}
}|}

(* OLED theme - true black background with soft pastel colors for OLED screens *)
let oled_json =
  {|{
  "name": "OLED",
  "dark_mode": true,
  "primary": { "fg": { "Fixed": 146 } },
  "secondary": { "fg": { "Fixed": 102 } },
  "accent": { "fg": { "Fixed": 139 } },
  "error": { "fg": { "Fixed": 174 } },
  "warning": { "fg": { "Fixed": 180 } },
  "success": { "fg": { "Fixed": 108 } },
  "info": { "fg": { "Fixed": 110 } },
  "text": { "fg": { "Fixed": 249 } },
  "text_muted": { "fg": { "Fixed": 243 } },
  "text_emphasized": { "fg": { "Fixed": 252 } },
  "background": { "bg": { "Fixed": 16 } },
  "background_secondary": { "bg": { "Fixed": 233 } },
  "border": { "fg": { "Fixed": 235 } },
  "border_focused": { "fg": { "Fixed": 240 } },
  "border_dim": { "fg": { "Fixed": 233 } },
  "selection": { "fg": { "Fixed": 252 }, "bg": { "Fixed": 236 } },
  "default_border_style": "None",
  "rules": {}
}|}

(* System theme - uses terminal's own colors via basic ANSI codes (0-15).
   No explicit background or text color: inherits from the terminal. *)
let system_json =
  {|{
  "name": "System",
  "dark_mode": true,
  "primary": { "fg": { "Fixed": 12 }, "bold": true },
  "secondary": { "fg": { "Fixed": 8 } },
  "accent": { "fg": { "Fixed": 13 } },
  "error": { "fg": { "Fixed": 1 }, "bold": true },
  "warning": { "fg": { "Fixed": 3 }, "bold": true },
  "success": { "fg": { "Fixed": 2 } },
  "info": { "fg": { "Fixed": 6 } },
  "text": { "fg": { "Fixed": -1 } },
  "text_muted": { "fg": { "Fixed": -1 }, "dim": true },
  "text_emphasized": { "fg": { "Fixed": -1 }, "bold": true },
  "background": { "bg": { "Fixed": -1 } },
  "background_secondary": { "bg": { "Fixed": -1 } },
  "border": { "fg": { "Fixed": -1 }, "dim": true },
  "border_focused": { "fg": { "Fixed": 12 }, "bold": true },
  "border_dim": { "fg": { "Fixed": -1 }, "dim": true },
  "selection": { "fg": { "Fixed": -1 }, "bg": { "Fixed": -1 }, "reverse": true },
  "default_border_style": "Rounded",
  "rules": {}
}|}

(** Get the JSON string for a built-in theme *)
let get_json id =
  match id with
  | "catppuccin-mocha" -> Some catppuccin_mocha_json
  | "catppuccin-latte" -> Some catppuccin_latte_json
  | "dracula" -> Some dracula_json
  | "nord" -> Some nord_json
  | "nord-light" -> Some nord_light_json
  | "gruvbox-dark" -> Some gruvbox_dark_json
  | "gruvbox-light" -> Some gruvbox_light_json
  | "tokyonight" -> Some tokyonight_json
  | "tokyonight-day" -> Some tokyonight_day_json
  | "opencode" -> Some opencode_json
  | "oled" -> Some oled_json
  | "system" -> Some system_json
  | _ -> None

(** Load a built-in theme by ID *)
let get_builtin id =
  match get_json id with
  | None -> None
  | Some json -> (
      match Theme.of_yojson (Yojson.Safe.from_string json) with
      | Ok theme -> Some (Theme.merge ~base:Theme.default ~overlay:theme)
      | Error _ -> None)

(** Check if a theme ID is a built-in theme *)
let is_builtin id = List.exists (fun t -> t.id = id) all_themes
