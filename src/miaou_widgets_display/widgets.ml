(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)
[@@@warning "-32-34-37-69"]

let ansi code s = "\027[" ^ code ^ "m" ^ s ^ "\027[0m"

(** Detect whether OSC 8 hyperlinks are likely supported.
    Returns false inside tmux/screen (which strip OSC sequences by default)
    unless the user has set MIAOU_TUI_HYPERLINKS=on to force them. *)
let osc8_supported =
  lazy
    (match Sys.getenv_opt "MIAOU_TUI_HYPERLINKS" with
    | Some ("on" | "1" | "true") -> true
    | Some ("off" | "0" | "false") -> false
    | _ ->
        (* tmux and screen strip OSC sequences unless configured for passthrough *)
        let in_tmux = Sys.getenv_opt "TMUX" <> None in
        let in_screen = Sys.getenv_opt "STY" <> None in
        (not in_tmux) && not in_screen)

(** Wrap [display] in an OSC 8 hyperlink pointing to [url].
    Terminal emulators that support OSC 8 render [display] as a clickable
    link.  When running inside tmux or screen (which strip OSC sequences),
    [display] is returned as-is.  Override with MIAOU_TUI_HYPERLINKS=on. *)
let hyperlink ~url display =
  if Lazy.force osc8_supported then
    "\027]8;;" ^ url ^ "\027\\" ^ display ^ "\027]8;;\027\\"
  else display

let bold s = ansi "1" s

let dim s = ansi "2" s

let fg n s = ansi ("38;5;" ^ string_of_int n) s

let bg n s = ansi ("48;5;" ^ string_of_int n) s

let green s = ansi "32" s

let red s = ansi "31" s

let yellow s = ansi "33" s

let blue s = ansi "34" s

let magenta s = ansi "35" s

let cyan s = ansi "36" s

(* ============================================================================
   THEMED STYLING SYSTEM

   Miaou uses a two-layer styling approach:

   1. SEMANTIC STYLES (explicit) - Use these when you want to convey meaning:
      - themed_primary, themed_error, themed_success, themed_warning, etc.
      - Widget authors choose these intentionally based on content semantics

   2. CONTEXTUAL STYLES (automatic) - Applied by the style context:
      - Based on widget name, focus state, position (nth-child), etc.
      - Configured via CSS-like selectors in theme JSON
      - Parents set up context, children get styled automatically

   IMPORTANT FOR WIDGET AUTHORS:
   - ALWAYS use themed_* functions for semantic meaning (errors, success, etc.)
   - Use themed_text for normal content (NOT raw fg/bg with hardcoded numbers)
   - The raw fg/bg functions are for special cases only (gradients, charts)
   - Contextual styling (focus, selection, zebra stripes) is automatic

   See AGENTS.md and PAGE_SIG documentation for full guidelines.
   ============================================================================ *)

module Style = Miaou_style.Style
module Style_context = Miaou_style.Style_context

(* --- Semantic style functions --- *)

(** Apply a Style.t to a string, producing ANSI-formatted output *)
let styled style s = Style_context.styled_with style s

(** Primary content - main UI elements, important text *)
let themed_primary s = styled (Style_context.primary ()) s

(** Secondary content - less prominent elements *)
let themed_secondary s = styled (Style_context.secondary ()) s

(** Accent - highlights, links, interactive elements *)
let themed_accent s = styled (Style_context.accent ()) s

(** Error state - validation errors, failures, critical issues *)
let themed_error s = styled (Style_context.error ()) s

(** Warning state - cautions, potential issues *)
let themed_warning s = styled (Style_context.warning ()) s

(** Success state - confirmations, completed actions *)
let themed_success s = styled (Style_context.success ()) s

(** Info state - neutral information, tips *)
let themed_info s = styled (Style_context.info ()) s

(** Normal text - default readable content *)
let themed_text s = styled (Style_context.text ()) s

(** Muted text - less important, secondary information *)
let themed_muted s = styled (Style_context.text_muted ()) s

(** Emphasized text - bold/highlighted content *)
let themed_emphasis s = styled (Style_context.text_emphasized ()) s

(** Border styling - for widget frames and separators *)
let themed_border ?(focus = false) s = styled (Style_context.border ~focus ()) s

(** Selection highlight - for selected items in lists/tables *)
let themed_selection s = styled (Style_context.selection ()) s

(** Background - primary background color *)
let themed_background s = styled (Style_context.background ()) s

(** Alternate background - for contrast (e.g., alternate rows) *)
let themed_background_alt s = styled (Style_context.background_secondary ()) s

(* --- Contextual style application --- *)

(** Apply the current contextual style (based on widget name, focus, position).
    Use this when rendering content that should respect CSS-like selector rules
    from the theme. The style is determined by Style_context.current_style(). *)
let themed_contextual s = Style_context.styled s

let apply_bg_fill ~bg s =
  let prefix = "\027[48;5;" ^ string_of_int bg ^ "m" in
  let reset = Style.ansi_reset in
  let len_s = String.length s in
  let len_reset = String.length reset in
  let rec find_sub start =
    if start + len_reset > len_s then None
    else if String.sub s start len_reset = reset then Some start
    else find_sub (start + 1)
  in
  let buf = Buffer.create (len_s + 16) in
  Buffer.add_string buf prefix ;
  let rec loop i =
    match find_sub i with
    | None -> Buffer.add_string buf (String.sub s i (len_s - i))
    | Some j ->
        Buffer.add_string buf (String.sub s i (j - i)) ;
        Buffer.add_string buf reset ;
        Buffer.add_string buf prefix ;
        loop (j + len_reset)
  in
  loop 0 ;
  Buffer.add_string buf reset ;
  Buffer.contents buf

(** Apply themed foreground color to text that has no foreground set.
    This ensures all text is visible regardless of terminal defaults.
    Essential for light themes where default foreground may be invisible.

    The algorithm:
    - Split text into segments by ANSI escape sequences
    - For each plain text segment not preceded by a foreground color code,
      wrap it with the theme's text foreground color
    - Preserve all existing ANSI codes *)
let apply_themed_foreground content =
  let theme = Style_context.current_theme () in
  let text_style = theme.Miaou_style.Theme.text in
  let dark_mode = theme.Miaou_style.Theme.dark_mode in
  let resolved = Style.to_resolved ~dark_mode text_style in
  let fg = resolved.Style.r_fg in
  if fg < 0 then content (* No text color in theme *)
  else
    let fg_prefix = Printf.sprintf "\027[38;5;%dm" fg in
    let reset_fg = "\027[39m" in
    (* Regex to match ANSI escape sequences *)
    let ansi_re = Str.regexp "\027\\[[0-9;]*m" in
    (* Split into tokens: either ANSI codes or plain text *)
    let tokens = Str.full_split ansi_re content in
    (* Track whether we have an active foreground color *)
    let has_fg = ref false in
    let result = Buffer.create (String.length content * 2) in
    let code_sets_fg codes i =
      if i + 1 < Array.length codes && codes.(i) = "38" then
        match codes.(i + 1) with
        | "5" -> i + 2 < Array.length codes
        | "2" -> i + 4 < Array.length codes
        | _ -> false
      else false
    in
    let code_resets_fg code = code = "0" || code = "39" || code = "" in
    let code_sets_fg_simple code =
      String.length code = 2
      && ((code.[0] = '3' && code.[1] >= '0' && code.[1] <= '7')
         || (code.[0] = '9' && code.[1] >= '0' && code.[1] <= '7'))
    in
    List.iter
      (function
        | Str.Delim code ->
            (* Check if this code sets or resets foreground *)
            if String.length code > 2 then (
              let inner = String.sub code 2 (String.length code - 3) in
              let parts =
                if inner = "" then [||]
                else String.split_on_char ';' inner |> Array.of_list
              in
              let fg_seen = ref !has_fg in
              let i = ref 0 in
              while !i < Array.length parts do
                let part = parts.(!i) in
                if code_resets_fg part then fg_seen := false
                else if code_sets_fg_simple part then fg_seen := true
                else if code_sets_fg parts !i then fg_seen := true ;
                if part = "38" && !i + 1 < Array.length parts then
                  match parts.(!i + 1) with
                  | "5" -> i := !i + 2
                  | "2" -> i := !i + 4
                  | _ -> i := !i + 1
                else i := !i + 1
              done ;
              has_fg := !fg_seen) ;
            Buffer.add_string result code
        | Str.Text txt ->
            if txt <> "" then
              if !has_fg then Buffer.add_string result txt
              else (
                (* No foreground set - apply theme's text color *)
                Buffer.add_string result fg_prefix ;
                Buffer.add_string result txt ;
                Buffer.add_string result reset_fg))
      tokens ;
    Buffer.contents result

(** Apply contextual background to full line width without overriding text. *)
let themed_contextual_fill s =
  let style = Style_context.current_style () in
  let resolved = Style.to_resolved style.style in
  if resolved.r_bg < 0 then s else apply_bg_fill ~bg:resolved.r_bg s

(** Apply theme background to entire content, padding lines to full width.
    This ensures the terminal background is filled with the theme's color. *)
let apply_themed_background ~rows ~cols content =
  let theme = Style_context.current_theme () in
  let bg_style = theme.Miaou_style.Theme.background in
  let resolved =
    Style.to_resolved ~dark_mode:theme.Miaou_style.Theme.dark_mode bg_style
  in
  if resolved.Style.r_bg < 0 then content
  else
    let lines = String.split_on_char '\n' content in
    let line_count = List.length lines in
    (* Pad or truncate to exact row count *)
    let lines =
      if line_count < rows then
        lines @ List.init (rows - line_count) (fun _ -> "")
      else if line_count > rows then List.filteri (fun i _ -> i < rows) lines
      else lines
    in
    (* Apply background fill to each line *)
    let lines =
      List.map
        (fun line ->
          let vis_len = Miaou_helpers.Helpers.visible_chars_count line in
          let padded =
            if vis_len >= cols then line
            else line ^ String.make (cols - vis_len) ' '
          in
          apply_bg_fill ~bg:resolved.Style.r_bg padded)
        lines
    in
    String.concat "\n" lines

(** Get the resolved widget style for the current context.
    Returns a Theme.widget_style record with style, border_style, etc. *)
let current_widget_style () = Style_context.current_style ()

(* Modal border and title colors - use themed border_focused style *)
let color_border s = themed_border ~focus:true s

let title_highlight s =
  (* Title uses accent foreground on secondary background for subtle styling *)
  let accent = Style_context.accent () in
  let bg_secondary = Style_context.background_secondary () in
  let fg_color = match accent.fg with Some (Style.Fixed c) -> c | _ -> 75 in
  let bg_color =
    match bg_secondary.bg with Some (Style.Fixed c) -> c | _ -> 238
  in
  bg bg_color (fg fg_color (bold s))

let is_utf8_lead = Miaou_helpers.Helpers.is_utf8_lead

let is_esc_start = Miaou_helpers.Helpers.is_esc_start

let skip_ansi_until_m = Miaou_helpers.Helpers.skip_ansi_until_m

let visible_chars_count = Miaou_helpers.Helpers.visible_chars_count

let visible_byte_index_of_pos = Miaou_helpers.Helpers.visible_byte_index_of_pos

let has_trailing_reset = Miaou_helpers.Helpers.has_trailing_reset

let insert_before_reset = Miaou_helpers.Helpers.insert_before_reset

let pad_to_width = Miaou_helpers.Helpers.pad_to_width

let use_ascii_borders =
  lazy
    (let env_val =
       let pick () =
         match Sys.getenv_opt "MIAOU_TUI_UNICODE_BORDERS" with
         | Some v -> Some v
         | None -> (
             match Miaou_interfaces.System.get () with
             | Some sys -> sys.get_env_var "MIAOU_TUI_UNICODE_BORDERS"
             | None -> None)
       in
       match pick () with
       | Some v -> (
           match String.lowercase_ascii (String.trim v) with
           | "" | "auto" -> None
           | v' -> Some v')
       | None -> None
     in
     let is_truthy v =
       match v with "1" | "true" | "yes" | "on" -> true | _ -> false
     in
     let is_falsy v =
       match v with "0" | "false" | "no" | "off" -> true | _ -> false
     in
     match env_val with
     | Some v when is_truthy v -> false
     | Some v when is_falsy v -> true
     | _ -> (
         match Sys.getenv_opt "LANG" with
         | Some lang when String.contains lang '8' -> false
         | _ -> true))

let glyph_corner_tl = if Lazy.force use_ascii_borders then "+" else "┌"

let glyph_corner_tr = if Lazy.force use_ascii_borders then "+" else "┐"

let glyph_corner_bl = if Lazy.force use_ascii_borders then "+" else "└"

let glyph_corner_br = if Lazy.force use_ascii_borders then "+" else "┘"

let glyph_hline = if Lazy.force use_ascii_borders then "-" else "─"

let glyph_vline = if Lazy.force use_ascii_borders then "|" else "│"

let glyph_top_sep = if Lazy.force use_ascii_borders then "+" else "┬"

let glyph_mid_left = if Lazy.force use_ascii_borders then "+" else "├"

let glyph_mid_sep = if Lazy.force use_ascii_borders then "+" else "┼"

let glyph_mid_right = if Lazy.force use_ascii_borders then "+" else "┤"

let glyph_bottom_sep = if Lazy.force use_ascii_borders then "+" else "┴"

(* Rendering backends: terminal (ANSI/Unicode) vs SDL. The SDL path often
   benefits from ASCII fallbacks to avoid missing glyphs. *)
type backend = [`Terminal | `Sdl]

let current_backend : backend ref = ref `Terminal

let set_backend b = current_backend := b

let get_backend () = !current_backend

let prefer_ascii ?backend () =
  let b = match backend with Some b -> b | None -> !current_backend in
  match b with `Sdl -> true | `Terminal -> Lazy.force use_ascii_borders

(* Backend-aware glyph helpers (ASCII fallback for SDL or env override) *)
let glyph_up ?backend () = if prefer_ascii ?backend () then "^" else "▲"

let glyph_down ?backend () = if prefer_ascii ?backend () then "v" else "▼"

let glyph_bullet ?backend () = if prefer_ascii ?backend () then "*" else "•"

let hr ~width ?(char = '-') () =
  let ch = String.make 1 char in
  String.concat "" (List.init width (fun _ -> ch))

let pad_visible s width =
  let len = visible_chars_count s in
  if len >= width then
    let idx = visible_byte_index_of_pos s (max 0 (width - 1)) in
    String.sub s 0 idx ^ "…"
  else s ^ String.make (width - len) ' '

let wrap_text ~width s =
  let width = max 1 width in
  let chunk word =
    let rec aux acc w =
      if visible_chars_count w <= width then List.rev (w :: acc)
      else
        let idx = visible_byte_index_of_pos w width in
        let pre = String.sub w 0 idx in
        let rest = String.sub w idx (String.length w - idx) in
        aux (pre :: acc) (String.trim rest)
    in
    aux [] word
  in
  let words = String.split_on_char ' ' s |> List.filter (fun w -> w <> "") in
  let rec loop line acc = function
    | [] -> if line = "" then List.rev acc else List.rev (line :: acc)
    | w :: ws ->
        let wl = visible_chars_count w in
        if line = "" then
          if wl <= width then loop w acc ws
          else
            let parts = chunk w in
            let acc = List.rev_append parts acc in
            loop "" acc ws
        else
          let ll = visible_chars_count line in
          if ll + 1 + wl <= width then loop (line ^ " " ^ w) acc ws
          else loop "" (line :: acc) (w :: ws)
  in
  loop "" [] words

let json_pretty (raw : string) : string =
  try Yojson.Safe.prettify raw with _ -> raw

let json_pretty_ansi (raw : string) : string =
  let c_key s = cyan s in
  let c_string s = green s in
  let c_number s = magenta s in
  let c_bool s = ansi "33;1" s in
  let c_null s = dim s in
  let c_punct s = ansi "38;5;240" s in
  let open Yojson.Safe in
  try
    let j = from_string raw in
    let buf = Buffer.create (String.length raw + 256) in
    let rec pp indent (v : Yojson.Safe.t) =
      match v with
      | `Assoc kvs -> (
          Buffer.add_string buf (c_punct "{") ;
          match kvs with
          | [] -> Buffer.add_string buf (c_punct "}")
          | _ ->
              Buffer.add_char buf '\n' ;
              List.iteri
                (fun i (k, vv) ->
                  Buffer.add_string buf (String.make (indent + 2) ' ') ;
                  Buffer.add_string buf (c_key (to_string (`String k))) ;
                  Buffer.add_string buf (c_punct ": ") ;
                  pp_value (indent + 2) vv ;
                  if i < List.length kvs - 1 then
                    Buffer.add_string buf (c_punct ",") ;
                  Buffer.add_char buf '\n')
                kvs ;
              Buffer.add_string buf (String.make indent ' ') ;
              Buffer.add_string buf (c_punct "}"))
      | `List lst -> (
          Buffer.add_string buf (c_punct "[") ;
          match lst with
          | [] -> Buffer.add_string buf (c_punct "]")
          | _ ->
              Buffer.add_char buf '\n' ;
              List.iteri
                (fun i vv ->
                  Buffer.add_string buf (String.make (indent + 2) ' ') ;
                  pp_value (indent + 2) vv ;
                  if i < List.length lst - 1 then
                    Buffer.add_string buf (c_punct ",") ;
                  Buffer.add_char buf '\n')
                lst ;
              Buffer.add_string buf (String.make indent ' ') ;
              Buffer.add_string buf (c_punct "]"))
      | _ -> pp_value indent v
    and pp_value indent v =
      match v with
      | `Assoc _ | `List _ -> pp indent v
      | `String _ -> Buffer.add_string buf (c_string (to_string v))
      | `Int _ | `Float _ -> Buffer.add_string buf (c_number (to_string v))
      | `Bool _ -> Buffer.add_string buf (c_bool (to_string v))
      | `Null -> Buffer.add_string buf (c_null "null")
      | _ -> Buffer.add_string buf (to_string v)
    in
    pp 0 j ;
    Buffer.contents buf
  with _ -> json_pretty raw

let highlight_matches ~(is_regex : bool) ~(query : string option)
    (line : string) : string =
  match query with
  | None -> line
  | Some q -> (
      let q = String.trim q in
      if Sys.getenv_opt "MIAOU_DEBUG" = Some "1" then
        Printf.eprintf
          "[HIGHLIGHT] Called with query='%s' (len=%d), is_regex=%b, line_len=%d\n\
           %!"
          q
          (String.length q)
          is_regex
          (String.length line) ;
      if q = "" then line
      else
        (* Use black text on bright yellow background for high visibility *)
        let hl s = ansi "0;30;103" s in
        let apply_with (rex : Str.regexp) : string =
          let len = String.length line in
          let buf = Buffer.create (len + 32) in
          let match_count = ref 0 in
          let rec loop pos =
            if pos >= len then ()
            else
              try
                let idx = Str.search_forward rex line pos in
                let m = Str.matched_string line in
                let mlen = String.length m in
                Buffer.add_substring buf line pos (idx - pos) ;
                if mlen > 0 then (
                  incr match_count ;
                  Buffer.add_string buf (hl m) ;
                  loop (idx + mlen))
                else (
                  Buffer.add_string buf m ;
                  loop (idx + 1))
              with Not_found -> Buffer.add_substring buf line pos (len - pos)
          in
          loop 0 ;
          let result = Buffer.contents buf in
          if Sys.getenv_opt "MIAOU_DEBUG" = Some "1" && !match_count > 0 then
            Printf.eprintf
              "[HIGHLIGHT] Found %d match(es) in line, added ANSI codes\n%!"
              !match_count ;
          result
        in
        try
          let rex =
            if is_regex then Str.regexp_case_fold q (* Case-insensitive regex *)
            else
              Str.regexp_string_case_fold
                q (* Case-insensitive literal string *)
          in
          apply_with rex
        with _ -> line)

let footer_hints (pairs : (string * string) list) : string =
  let parts =
    List.map (fun (k, v) -> themed_secondary (k ^ ": ") ^ themed_text v) pairs
  in
  String.concat "    " parts

let footer_hints_wrapped ~cols (pairs : (string * string) list) : string =
  let segments =
    List.map (fun (k, v) -> themed_secondary (k ^ ": ") ^ themed_text v) pairs
  in
  let space = "    " in
  let lines = ref [] in
  let current = ref "" in
  let add_line () =
    if !current <> "" then (
      lines := !current :: !lines ;
      current := "")
  in
  let seg_visible s = visible_chars_count s in
  List.iter
    (fun seg ->
      if !current = "" then
        let truncated = if seg_visible seg > cols then seg else seg in
        current := truncated
      else
        let candidate = !current ^ space ^ seg in
        if seg_visible candidate > cols then (
          add_line () ;
          current := seg)
        else current := candidate)
    segments ;
  add_line () ;
  String.concat "\n" (List.rev !lines)

let footer_hints_wrapped_capped ~cols ~max_lines
    (pairs : (string * string) list) : string =
  if max_lines <= 0 then ""
  else
    let segments =
      List.map (fun (k, v) -> themed_secondary (k ^ ": ") ^ themed_text v) pairs
    in
    let space = "    " in
    let lines = ref [] in
    let current = ref "" in
    let seg_visible s = visible_chars_count s in
    let add_line () =
      if !current <> "" then (
        lines := !current :: !lines ;
        current := "")
    in
    let overflow = ref false in
    List.iter
      (fun seg ->
        if not !overflow then
          if !current = "" then
            let truncated = if seg_visible seg > cols then seg else seg in
            current := truncated
          else
            let candidate = !current ^ space ^ seg in
            if seg_visible candidate > cols then (
              add_line () ;
              if List.length !lines >= max_lines then overflow := true
              else current := seg)
            else current := candidate)
      segments ;
    add_line () ;
    let rendered = List.rev !lines in
    let rendered =
      if List.length rendered > max_lines then
        let kept, _drop =
          let rec take n acc lst =
            match (n, lst) with
            | 0, _ | _, [] -> (List.rev acc, lst)
            | n, x :: xs -> take (n - 1) (x :: acc) xs
          in
          take max_lines [] rendered
        in
        kept
      else rendered
    in
    if List.length rendered < List.length !lines || !overflow then
      let ellipsis = themed_muted "… more (? for all)" in
      let trimmed =
        if List.length rendered = max_lines then
          let all_but_last, _last =
            let rec rev_split = function
              | [] -> ([], "")
              | [x] -> ([], x)
              | x :: xs ->
                  let a, b = rev_split xs in
                  (x :: a, b)
            in
            rev_split rendered
          in
          all_but_last @ [ellipsis]
        else rendered @ [ellipsis]
      in
      String.concat "\n" trimmed
    else String.concat "\n" rendered

let titleize title =
  let left = " " in
  let star = themed_accent "★ " in
  let t = themed_primary title in
  themed_background (left ^ bold (star ^ t))

let render_frame ~title ?(header = []) ?cols ~body ~footer () : string =
  let cols = match cols with Some c -> c | None -> 80 in
  let title_line = titleize title in
  let sep = fg 238 (hr ~width:cols ()) in
  let header_s =
    match header with [] -> "" | lst -> String.concat "\n" lst ^ "\n"
  in
  let pad_to_cols_lines (s : string) : string list =
    let lines = String.split_on_char '\n' s in
    let pad_line l =
      let v = visible_chars_count l in
      if v = cols then l
      else if v > cols then
        let byte_idx = visible_byte_index_of_pos l (max 0 (cols - 1)) in
        let prefix = String.sub l 0 byte_idx in
        prefix ^ "…"
      else pad_to_width l cols ' '
    in
    List.map pad_line lines
  in
  let body_s =
    pad_to_cols_lines (header_s ^ body)
    |> List.map themed_contextual_fill
    |> String.concat "\n"
  in
  let footer_s =
    pad_to_cols_lines footer
    |> List.map themed_contextual_fill
    |> String.concat "\n"
  in
  String.concat "\n" [title_line; sep; body_s; footer_s]

let color_for_status s =
  match String.trim s with
  | "active" -> green
  | "failed" -> red
  | "inactive" -> dim
  | _ -> fun x -> x

let sel_marker i cursor = if i = cursor then "👉  " else "   "

let chip_ok s = bg 22 (fg 15 (" ✔ " ^ s ^ " "))

let chip_warn s = bg 58 (fg 15 (" ⚠ " ^ s ^ " "))

let chip_err s = bg 52 (fg 15 (" ✖ " ^ s ^ " "))

(* Common banner helpers *)
let pad_to_cols_line ~cols (s : string) : string =
  let v = visible_chars_count s in
  if v = cols then s
  else if v > cols then
    let byte_idx = visible_byte_index_of_pos s (max 0 (cols - 1)) in
    let prefix = String.sub s 0 byte_idx in
    prefix ^ "…"
  else pad_to_width s cols ' '

let warning_banner ~cols msg = pad_to_cols_line ~cols (chip_warn msg)

let ok_banner ~cols msg = pad_to_cols_line ~cols (chip_ok msg)

let info_banner ~cols msg =
  (* Use cyan on neutral background for info, matching title_highlight palette. *)
  let chip_info s = bg 24 (fg 15 (" ℹ " ^ s ^ " ")) in
  pad_to_cols_line ~cols (chip_info msg)

let error_banner ~cols msg = pad_to_cols_line ~cols (chip_err msg)

let palette () = Miaou_interfaces.Palette.require ()

let fg_primary s = (palette ()).fg_primary s

let fg_secondary s = (palette ()).fg_steel s

let fg_muted s = (palette ()).fg_stealth s

let bg_selection s = (palette ()).selection_bg s

let selection_fg = (palette ()).selection_fg

(** Render a box with only a left border and colored background.
    Useful for displaying context sections, file content, or quoted messages.

    @param border_color ANSI 256 color for the left border (default: 75, blue)
    @param bg_color ANSI 256 color for background (default: 236, dark gray)
    @param cols Total width of the box
    @param content The text content (may be multiline)
*)
let render_left_border_box ?(border_color = 75) ?(bg_color = 236) ~cols content
    =
  let vline =
    if Lazy.force use_ascii_borders then fg border_color "|"
    else fg border_color "▎"
  in
  let lines = String.split_on_char '\n' content in
  let inner_width = cols - 1 in
  (* 1 char for left border *)
  let render_line line =
    let visible_len = visible_chars_count line in
    let padded =
      if visible_len >= inner_width then
        let byte_idx = visible_byte_index_of_pos line (inner_width - 1) in
        String.sub line 0 byte_idx ^ "…"
      else line ^ String.make (inner_width - visible_len) ' '
    in
    vline ^ bg bg_color padded
  in
  String.concat "\n" (List.map render_line lines)

(* Overlay the modal content centered onto the base screen. *)
let overlay ~base ~content ~top ~left ~canvas_h ~canvas_w : string =
  let base_lines = String.split_on_char '\n' base in
  let content_lines = String.split_on_char '\n' content in
  let get_line lines i =
    if i < List.length lines then List.nth lines i else ""
  in
  let c_h = List.length content_lines in
  let c_w =
    List.fold_left
      (fun acc s -> max acc (visible_chars_count s))
      0
      content_lines
  in
  let set_overlay (base_line : string) (overlay_line : string) : string =
    (* base_line should already be padded to canvas_w by caller (e.g. dim_line).
       We only pad to reach 'left' position if needed for overlay placement. *)
    let base_v = visible_chars_count base_line in
    let pad_left = max 0 (left - base_v) in
    let base_padded =
      if pad_left > 0 then base_line ^ String.make pad_left ' ' else base_line
    in
    let span = min c_w (max 0 (canvas_w - left)) in
    (* Use the beginning of the base line up to 'left' position, preserving styling *)
    let pre =
      if left <= 0 then ""
      else
        let idx = visible_byte_index_of_pos base_padded left in
        String.sub base_padded 0 idx
    in
    let idx_left = visible_byte_index_of_pos base_padded left in
    let ov =
      let s = overlay_line in
      let s = if visible_chars_count s > span then s else s in
      s
    in
    let ov_chars = visible_chars_count ov in
    let byte_index_after_span_from i span =
      let len = String.length base_padded in
      let rec loop i rem =
        if rem <= 0 then i
        else if i >= len then len
        else if is_esc_start base_padded i then
          let j = skip_ansi_until_m base_padded (i + 2) in
          loop j rem
        else
          let j = ref (i + 1) in
          while !j < len && Char.code base_padded.[!j] land 0xC0 = 0x80 do
            incr j
          done ;
          loop !j (rem - 1)
      in
      loop i span
    in
    let idx_post = byte_index_after_span_from idx_left ov_chars in
    let post =
      if idx_post < String.length base_padded then
        String.sub base_padded idx_post (String.length base_padded - idx_post)
      else ""
    in
    (* Extract any ANSI prefix from base_line (e.g., background color) and prepend
       to post so it inherits the same styling. The prefix is everything before
       the first visible character. *)
    let base_prefix =
      let len = String.length base_line in
      let rec find_first_visible i =
        if i >= len then i
        else if is_esc_start base_line i then
          let j = skip_ansi_until_m base_line (i + 2) in
          find_first_visible j
        else i
      in
      let first_vis = find_first_visible 0 in
      if first_vis > 0 then String.sub base_line 0 first_vis else ""
    in
    let post =
      if post <> "" && base_prefix <> "" then base_prefix ^ post else post
    in
    pre ^ ov ^ post
  in
  let rec build i acc =
    if i >= canvas_h then List.rev acc
    else
      let base_line = get_line base_lines i in
      if i >= top && i < top + c_h then
        let overlay_line = get_line content_lines (i - top) in
        let line = set_overlay base_line overlay_line in
        build (i + 1) (line :: acc)
      else build (i + 1) (base_line :: acc)
  in
  String.concat "\n" (build 0 [])

let center_modal ~(cols : int option) ?rows ?title ?(padding = 0)
    ?(max_width = 76) ?(max_height = 30) ?(dim_background = false) ?left
    ~content ~base () =
  (* If title contains newlines, extract extra lines and prepend to content *)
  let title_first_line, extra_title_lines =
    match title with
    | None -> (None, [])
    | Some t -> (
        match String.index_opt t '\n' with
        | None -> (Some t, [])
        | Some idx ->
            let first = String.sub t 0 idx in
            let rest = String.sub t (idx + 1) (String.length t - idx - 1) in
            let rest_lines = String.split_on_char '\n' rest in
            (Some first, rest_lines))
  in
  (* Prepend extra title lines to content *)
  let content_with_title_extras =
    if extra_title_lines = [] then content
    else String.concat "\n" extra_title_lines ^ "\n" ^ content
  in
  let cont_lines = String.split_on_char '\n' content_with_title_extras in
  let inner_w =
    List.fold_left (fun acc s -> max acc (visible_chars_count s)) 0 cont_lines
  in
  let inner_h = List.length cont_lines in
  let title_w =
    match title_first_line with
    | None -> 0
    | Some t -> visible_chars_count (" " ^ t ^ " ")
  in
  let content_w = min max_width (max inner_w title_w) in
  let total_w =
    match cols with
    | Some c -> min c (content_w + 2 + (padding * 2))
    | None -> content_w + 2 + (padding * 2)
  in
  let inner_area_w = max 0 (total_w - 2) in
  let content_w = max 0 (inner_area_w - (2 * padding)) in
  let max_content_h = max 0 (max_height - 2 - (2 * padding)) in
  let cont_lines =
    let rec take n xs acc =
      match (n, xs) with
      | 0, _ | _, [] -> List.rev acc
      | n, x :: xt -> take (n - 1) xt (x :: acc)
    in
    if inner_h <= max_content_h then cont_lines
    else take max_content_h cont_lines []
  in
  let total_h = 2 + (2 * padding) + List.length cont_lines in
  let repeat n s =
    let buf = Buffer.create (n * String.length s) in
    for _ = 1 to max 0 n do
      Buffer.add_string buf s
    done ;
    Buffer.contents buf
  in
  let hline = repeat (max 0 inner_area_w) glyph_hline in
  let top_bar_colored =
    match title_first_line with
    | None ->
        color_border glyph_corner_tl
        ^ color_border hline
        ^ color_border glyph_corner_tr
    | Some t ->
        (* Only the first line of title gets the blue background *)
        let t' = " " ^ t ^ " " in
        let t_vis = visible_chars_count t' in
        let left_len = max 0 ((inner_area_w - t_vis) / 2) in
        let right_len = max 0 (inner_area_w - t_vis - left_len) in
        let left_h = repeat left_len glyph_hline in
        let right_h = repeat right_len glyph_hline in
        color_border glyph_corner_tl
        ^ color_border left_h ^ title_highlight t' ^ color_border right_h
        ^ color_border glyph_corner_tr
  in
  let bottom_bar_colored =
    color_border glyph_corner_bl
    ^ color_border hline
    ^ color_border glyph_corner_br
  in
  let clip s =
    let vlen = visible_chars_count s in
    if vlen <= content_w then s
    else
      let byte_idx = visible_byte_index_of_pos s (max 0 (content_w - 1)) in
      let prefix = String.sub s 0 byte_idx in
      prefix ^ "…"
  in
  (* Get modal background color from theme. Try background first, then
     background_secondary as fallback. Modals need an explicit background
     to avoid showing through to terminal default. *)
  let modal_bg =
    let bg_style = Style_context.background () in
    match bg_style.bg with
    | Some (Style.Fixed c) -> Some c
    | _ -> (
        (* Fallback to background_secondary *)
        let bg_sec = Style_context.background_secondary () in
        match bg_sec.bg with Some (Style.Fixed c) -> Some c | _ -> None)
  in
  let fill_bg s =
    match modal_bg with Some c -> apply_bg_fill ~bg:c s | None -> s
  in
  let pad_line s =
    let s' = clip s in
    let left_spaces = String.make padding ' ' in
    let mid_len = visible_chars_count s' in
    let right_len = max 0 (inner_area_w + 2 - (1 + padding + mid_len) - 1) in
    let right_spaces =
      if right_len > 0 then String.make right_len ' ' else ""
    in
    (* Build the content part and apply background fill.
       We need to ensure the background is applied to the entire line
       including any spaces, and survives any ANSI resets in the content. *)
    let content = left_spaces ^ s' ^ right_spaces in
    let content_with_bg = fill_bg content in
    (* Both borders need bg fill so they don't show terminal default *)
    let left_border = fill_bg (color_border glyph_vline) in
    let right_border = fill_bg (color_border glyph_vline) in
    left_border ^ content_with_bg ^ right_border
  in
  let rec replicate n acc =
    if n <= 0 then List.rev acc else replicate (n - 1) ("" :: acc)
  in
  let top_pad = replicate padding [] in
  let bot_pad = replicate padding [] in
  let boxed_colored_lines =
    (* Apply background fill to border lines as well as content lines *)
    (fill_bg top_bar_colored :: List.map pad_line top_pad)
    @ List.map pad_line cont_lines
    @ List.map pad_line bot_pad
    @ [fill_bg bottom_bar_colored]
  in
  let boxed_colored =
    let buf = Buffer.create (total_h * (total_w + 1)) in
    List.iteri
      (fun i line ->
        if i > 0 then Buffer.add_char buf '\n' ;
        Buffer.add_string buf line)
      boxed_colored_lines ;
    Buffer.contents buf
  in
  (* Determine canvas dimensions first, as we need cols for padding dimmed lines *)
  let base_lines_raw = String.split_on_char '\n' base in
  let base_line_count = List.length base_lines_raw in
  let rows =
    match rows with Some r -> max r base_line_count | None -> base_line_count
  in
  let cols =
    match cols with
    | Some c -> c
    | None ->
        List.fold_left
          (fun acc l -> max acc (visible_chars_count l))
          0
          base_lines_raw
  in
  let base_to_use =
    if dim_background then
      (* For dimmed background, we need to both dim the text AND apply a
         background color. Use background_secondary for the dimmed area,
         which should be a slightly different shade than the main background. *)
      let dim_bg =
        let bg_sec = Style_context.background_secondary () in
        match bg_sec.bg with Some (Style.Fixed c) -> Some c | _ -> None
      in
      let dim_line l =
        let dimmed = dim l in
        (* Pad the line to full canvas width so background covers entire row *)
        let vis_len = visible_chars_count dimmed in
        let padded =
          if vis_len < cols then dimmed ^ String.make (cols - vis_len) ' '
          else dimmed
        in
        match dim_bg with
        | Some c -> apply_bg_fill ~bg:c padded
        | None -> padded
      in
      String.concat "\n" (List.map dim_line base_lines_raw)
    else base
  in
  let left =
    match left with Some l -> max 0 l | None -> max 0 ((cols - total_w) / 2)
  in
  let top = max 0 ((rows - total_h) / 2) in
  overlay
    ~base:base_to_use
    ~content:boxed_colored
    ~top
    ~left
    ~canvas_h:rows
    ~canvas_w:cols
