(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

module W = Miaou_widgets_display.Widgets

let nerd_font_enabled () =
  match Sys.getenv_opt "MIAOU_NERD_FONT" with
  | Some ("1" | "true" | "TRUE" | "yes" | "YES") -> true
  | _ -> false

(* Lower-case the trailing extension (no leading dot). Returns "" for
   files without a recognisable extension. *)
let extension_lower name =
  match Filename.extension name with
  | "" -> ""
  | ext ->
      let s = String.sub ext 1 (String.length ext - 1) in
      String.lowercase_ascii s

(* (icon-without-nerd, icon-nerd, fg-256-color-or-(-1)) per extension/special. *)
let table =
  [
    ("ml", ("🐫", "", 214));
    ("mli", ("🐫", "", 214));
    ("rs", ("🦀", "", 208));
    ("py", ("🐍", "", 33));
    ("js", ("📜", "", 220));
    ("ts", ("📜", "", 75));
    ("json", ("📦", "", 178));
    ("yaml", ("📦", "", 178));
    ("yml", ("📦", "", 178));
    ("toml", ("📦", "", 178));
    ("md", ("📝", "", 252));
    ("markdown", ("📝", "", 252));
    ("txt", ("📄", "", 250));
    ("log", ("📋", "", 244));
    ("sh", ("🔧", "", 64));
    ("bash", ("🔧", "", 64));
    ("zsh", ("🔧", "", 64));
    ("fish", ("🔧", "", 64));
    ("html", ("🌐", "", 202));
    ("css", ("🎨", "", 39));
    ("png", ("🖼", "", 141));
    ("jpg", ("🖼", "", 141));
    ("jpeg", ("🖼", "", 141));
    ("gif", ("🖼", "", 141));
    ("svg", ("🖼", "", 141));
    ("pdf", ("📕", "", 124));
    ("zip", ("📦", "", 130));
    ("tar", ("📦", "", 130));
    ("gz", ("📦", "", 130));
    ("xz", ("📦", "", 130));
    ("bz2", ("📦", "", 130));
    ("7z", ("📦", "", 130));
    ("rar", ("📦", "", 130));
    ("c", ("📘", "", 67));
    ("h", ("📘", "", 67));
    ("cpp", ("📘", "", 67));
    ("hpp", ("📘", "", 67));
    ("go", ("🐹", "", 75));
    ("hs", ("📘", "", 99));
    ("rb", ("💎", "", 197));
    ("lock", ("🔒", "", 244));
  ]

let lookup ext =
  match List.assoc_opt ext table with Some v -> Some v | None -> None

let choose_icon ~nerd unicode nerd_icon =
  if nerd && nerd_icon <> "" then nerd_icon else unicode

let dir_unicode = "📁"

let dir_nerd = "" (* nf-fa-folder *)

let parent_unicode = "📂"

let parent_nerd = "" (* nf-fa-folder_open *)

let plain_unicode = "📄"

let plain_nerd = "" (* nf-fa-file_o *)

let icon_for ~name ~is_dir =
  let nerd = nerd_font_enabled () in
  let icon =
    if name = ".." then choose_icon ~nerd parent_unicode parent_nerd
    else if is_dir then choose_icon ~nerd dir_unicode dir_nerd
    else
      let ext = extension_lower name in
      match lookup ext with
      | Some (u, n, _) -> choose_icon ~nerd u n
      | None -> choose_icon ~nerd plain_unicode plain_nerd
  in
  icon ^ " "

let color_for ~name ~is_dir =
  if is_dir then Some 75 (* cyan-ish for directories *)
  else
    let ext = extension_lower name in
    match lookup ext with Some (_, _, c) -> Some c | None -> None

let decorate ~name ~is_dir label =
  let icon = icon_for ~name ~is_dir in
  let colored =
    match color_for ~name ~is_dir with Some c -> W.fg c label | None -> label
  in
  icon ^ colored

let () =
  Miaou_registry.register ~name:"file_icons" ~mli:[%blob "file_icons.mli"] ()
