(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

let output_dir = "website/src/media/captures"

let ensure_dir path = if not (Sys.file_exists path) then Unix.mkdir path 0o755

let escape_xml s =
  let b = Buffer.create (String.length s) in
  String.iter
    (function
      | '&' -> Buffer.add_string b "&amp;"
      | '<' -> Buffer.add_string b "&lt;"
      | '>' -> Buffer.add_string b "&gt;"
      | '"' -> Buffer.add_string b "&quot;"
      | c -> Buffer.add_char b c)
    s ;
  Buffer.contents b

let strip_ansi s =
  let len = String.length s in
  let b = Buffer.create len in
  let rec skip_osc i =
    if i >= len then i
    else if s.[i] = '\007' then i + 1
    else if i + 1 < len && s.[i] = '\027' && s.[i + 1] = '\\' then i + 2
    else skip_osc (i + 1)
  in
  let rec skip_csi i =
    if i >= len then i
    else
      let code = Char.code s.[i] in
      if code >= 0x40 && code <= 0x7e then i + 1 else skip_csi (i + 1)
  in
  let rec loop i =
    if i >= len then ()
    else if s.[i] = '\027' && i + 1 < len then
      match s.[i + 1] with
      | '[' -> loop (skip_csi (i + 2))
      | ']' -> loop (skip_osc (i + 2))
      | _ -> loop (i + 2)
    else (
      Buffer.add_char b s.[i] ;
      loop (i + 1))
  in
  loop 0 ;
  Buffer.contents b

let trim_right s =
  let rec loop i =
    if i < 0 then ""
    else
      match s.[i] with
      | ' ' | '\t' | '\r' -> loop (i - 1)
      | _ -> String.sub s 0 (i + 1)
  in
  loop (String.length s - 1)

let normalize_lines ~max_lines rendered =
  rendered |> strip_ansi |> String.split_on_char '\n' |> List.map trim_right
  |> List.filter (fun line -> String.trim line <> "")
  |> fun lines ->
  let rec take n acc = function
    | _ when n = 0 -> List.rev acc
    | [] -> List.rev acc
    | line :: rest -> take (n - 1) (line :: acc) rest
  in
  take max_lines [] lines

let svg ~title ~subtitle lines =
  let width = 1280 in
  let height = 760 in
  let line_height = 18 in
  let start_y = 112 in
  let text =
    lines
    |> List.mapi (fun i line ->
        Printf.sprintf
          "<text x=\"54\" y=\"%d\">%s</text>"
          (start_y + (i * line_height))
          (escape_xml line))
    |> String.concat "\n"
  in
  Printf.sprintf
    {|<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d" role="img" aria-labelledby="title desc">
  <title id="title">%s</title>
  <desc id="desc">%s</desc>
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#1b0b2b" />
      <stop offset="0.48" stop-color="#081724" />
      <stop offset="1" stop-color="#100812" />
    </linearGradient>
  </defs>
  <rect width="%d" height="%d" rx="38" fill="url(#bg)" />
  <rect x="28" y="28" width="1224" height="704" rx="28" fill="#050813" opacity="0.94" stroke="#5f7191" stroke-opacity="0.38" />
  <circle cx="68" cy="62" r="8" fill="#ff7ac8" />
  <circle cx="94" cy="62" r="8" fill="#ffd36e" />
  <circle cx="120" cy="62" r="8" fill="#82ffbd" />
  <text x="154" y="68" font-family="ui-monospace, SFMono-Regular, Menlo, Consolas, monospace" font-size="18" fill="#ffd36e">%s</text>
  <g font-family="ui-monospace, SFMono-Regular, Menlo, Consolas, monospace" font-size="14" fill="#e7f8ff" xml:space="preserve">
%s
  </g>
</svg>
|}
    width
    height
    width
    height
    (escape_xml title)
    (escape_xml subtitle)
    width
    height
    (escape_xml title)
    text

let write_svg ~file ~title ~subtitle rendered =
  let lines = normalize_lines ~max_lines:34 rendered in
  let oc = open_out (Filename.concat output_dir file) in
  output_string oc (svg ~title ~subtitle lines) ;
  close_out oc

let capture_page (type state msg) file title subtitle
    (module Page : Miaou.Core.Tui_page.PAGE_SIG
      with type state = state
       and type msg = msg) =
  let size = LTerm_geom.{rows = 34; cols = 110} in
  let state = Page.init () in
  let rendered = Page.view state ~focus:true ~size in
  write_svg ~file ~title ~subtitle rendered

let () =
  ensure_dir "website" ;
  ensure_dir "website/src" ;
  ensure_dir "website/src/media" ;
  ensure_dir output_dir ;
  Demo_shared.Demo_config.register_mocks () ;
  capture_page
    "responsive.svg"
    "Responsive layout demo"
    "Real render from example/demos/responsive/page.ml"
    (module Responsive_demo.Page) ;
  capture_page
    "style-system.svg"
    "Style system demo"
    "Real render from example/demos/style_system/page.ml"
    (module Style_system_demo.Page) ;
  capture_page
    "table.svg"
    "Table demo"
    "Real render from example/demos/table/page.ml"
    (module Table_demo.Page) ;
  capture_page
    "sparkline.svg"
    "Sparkline demo"
    "Real render from example/demos/sparkline/page.ml"
    (module Sparkline_demo.Page) ;
  capture_page
    "validated-textbox.svg"
    "Validated textbox demo"
    "Real render from example/demos/validated_textbox/page.ml"
    (module Validated_textbox_demo.Page) ;
  capture_page
    "miaou-force.svg"
    "Miaou Force"
    "Real render from example/demos/miaou_force/page.ml"
    (module Miaou_force_demo.Page) ;
  capture_page
    "miaou-crypt.svg"
    "Miaou Crypt"
    "Real render from example/demos/miaou_crypt/page.ml"
    (module Miaou_crypt_demo.Page) ;
  capture_page
    "miaou-links.svg"
    "Miaou Links"
    "Real render from example/demos/miaou_links/page.ml"
    (module Miaou_links_demo.Page) ;
  capture_page
    "geo-quiz.svg"
    "Geo Quiz"
    "Real render from example/demos/geo_quiz/page.ml"
    (module Geo_quiz_demo.Page)
