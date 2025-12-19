(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

module QR = Miaou_widgets_display.Qr_code_widget

type example = {label : string; data : string}

module Inner = struct
  let tutorial_title = "QR Code"

  let tutorial_markdown = [%blob "README.md"]

  type state = {
    examples : example list;
    current : int;
    next_page : string option;
  }

  type msg = unit

  let examples =
    [
      {label = "URL"; data = "miaou.dev"};
      {label = "Text"; data = "MIAOU"};
      {label = "Number"; data = "12345"};
      {label = "Email"; data = "hi@miaou.dev"};
    ]

  let init () = {examples; current = 0; next_page = None}

  let update s (_ : msg) = s

  let view s ~focus:_ ~size:_ =
    let module W = Miaou_widgets_display.Widgets in
    let header = W.titleize "QR Code Demo" in
    let example = List.nth s.examples s.current in
    let qr_result = QR.create ~data:example.data ~scale:1 () in
    let qr_lines =
      match qr_result with
      | Ok qr -> String.split_on_char '\n' (QR.render qr ~focus:true)
      | Error err -> ["QR Error: " ^ err]
    in
    let info_lines =
      [
        W.bold
          (Printf.sprintf
             "Example %d/%d"
             (s.current + 1)
             (List.length s.examples));
        "";
        W.bold "Type: " ^ example.label;
        W.bold "Data: " ^ W.dim example.data;
        "";
        "Scan this QR code with";
        "your phone's camera to";
        "access the content.";
        "";
        W.dim "Keys:";
        W.dim "  1-4: Switch example";
        W.dim "  t: Tutorial";
        W.dim "  q: Back";
      ]
    in
    let max_lines = max (List.length qr_lines) (List.length info_lines) in
    let combined_lines = ref [] in
    for i = 0 to max_lines - 1 do
      let qr_part =
        if i < List.length qr_lines then List.nth qr_lines i else ""
      in
      let info_part =
        if i < List.length info_lines then "  " ^ List.nth info_lines i else ""
      in
      combined_lines := (qr_part ^ info_part) :: !combined_lines
    done ;
    String.concat "\n" (header :: List.rev !combined_lines)

  let go_back s =
    {s with next_page = Some Demo_shared.Demo_config.launcher_page_name}

  let handle_key s key_str ~size:_ =
    match key_str with
    | "1" -> {s with current = 0}
    | "2" -> {s with current = 1}
    | "3" -> {s with current = 2}
    | "4" -> {s with current = 3}
    | "q" -> go_back s
    | _ -> s

  let move s _ = s

  let refresh s = s

  let enter s = s

  let service_select s _ = s

  let service_cycle s _ = s

  let handle_modal_key s _ ~size:_ = s

  let next_page s = s.next_page

  let keymap (_ : state) = []

  let handled_keys () = []

  let back s = go_back s

  let has_modal _ = false
end

include Demo_shared.Demo_page.Make (Inner)
