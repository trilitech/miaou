(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

module Inner = struct
  let tutorial_title = "Wizard Widget"

  let tutorial_markdown = [%blob "README.md"]

  module Wz = Miaou_widgets_layout.Wizard_widget
  module W = Miaou_widgets_display.Widgets

  type backend = Matrix | Sdl | Term | Web

  let backend_label = function
    | Matrix -> "matrix (default, diff-based)"
    | Sdl -> "sdl (graphics)"
    | Term -> "term (lambda-term)"
    | Web -> "web (xterm.js)"

  let backend_cycle backends b =
    let rec idx i = function
      | [] -> 0
      | x :: rest -> if x = b then i else idx (i + 1) rest
    in
    let n = List.length backends in
    let i = idx 0 backends in
    List.nth backends ((i + 1) mod n)

  let backend_cycle_back backends b =
    let rec idx i = function
      | [] -> 0
      | x :: rest -> if x = b then i else idx (i + 1) rest
    in
    let n = List.length backends in
    let i = idx 0 backends in
    List.nth backends ((i - 1 + n) mod n)

  let all_backends = [Matrix; Sdl; Term; Web]

  type ws = {backend : backend option; name : string}

  let initial = {backend = None; name = ""}

  let pick_backend_step : ws Wz.step =
    {
      title = "Backend";
      render =
        (fun s ~focus:_ ~size:_ ->
          let line =
            match s.backend with
            | None -> W.themed_muted "(none — press → to pick)"
            | Some b -> W.themed_emphasis (backend_label b)
          in
          let hint =
            W.themed_muted "Use ← / → to cycle. Enter advances when chosen."
          in
          String.concat "\n" ["Pick a backend:"; ""; "  " ^ line; ""; hint]);
      validate =
        (fun s ->
          if s.backend <> None then Ok () else Error "pick a backend first");
      on_key =
        (fun s ~key ->
          match key with
          | "Right" ->
              let b =
                match s.backend with
                | None -> Matrix
                | Some b -> backend_cycle all_backends b
              in
              {s with backend = Some b}
          | "Left" ->
              let b =
                match s.backend with
                | None -> Web
                | Some b -> backend_cycle_back all_backends b
              in
              {s with backend = Some b}
          | _ -> s);
    }

  let name_step : ws Wz.step =
    {
      title = "Name";
      render =
        (fun s ~focus:_ ~size:_ ->
          let display =
            if s.name = "" then W.themed_muted "(empty)"
            else W.themed_emphasis ("\"" ^ s.name ^ "\"")
          in
          let hint = W.themed_muted "Type letters. Backspace to correct." in
          String.concat "\n" ["Project name:"; ""; "  " ^ display; ""; hint]);
      validate =
        (fun s ->
          if String.length s.name > 0 then Ok ()
          else Error "name must be non-empty");
      on_key =
        (fun s ~key ->
          match key with
          | "Backspace" ->
              if s.name = "" then s
              else
                {s with name = String.sub s.name 0 (String.length s.name - 1)}
          | k when String.length k = 1 -> {s with name = s.name ^ k}
          | _ -> s);
    }

  let review_step : ws Wz.step =
    {
      title = "Review";
      render =
        (fun s ~focus:_ ~size:_ ->
          let backend =
            match s.backend with None -> "—" | Some b -> backend_label b
          in
          String.concat
            "\n"
            [
              "About to create:";
              "";
              W.themed_text "  Backend: " ^ W.themed_emphasis backend;
              W.themed_text "  Name:    " ^ W.themed_emphasis s.name;
              "";
              W.themed_muted "Press Enter to finish.";
            ]);
      validate = (fun _ -> Ok ());
      on_key = (fun s ~key:_ -> s);
    }

  let make_wizard () =
    Wz.create ~steps:[|pick_backend_step; name_step; review_step|] ~initial

  type state = {wizard : ws Wz.t; next_page : string option}

  type msg = unit

  let init () = {wizard = make_wizard (); next_page = None}

  let update s _ = s

  let view s ~focus ~size =
    let header = W.titleize "Wizard Demo (Esc cancels, t opens tutorial)" in
    let body = Wz.render s.wizard ~focus ~size in
    String.concat "\n" [header; ""; body]

  let go_back s =
    {s with next_page = Some Demo_shared.Demo_config.launcher_page_name}

  let handle_key s key_str ~size:_ =
    if Wz.is_cancelled s.wizard then go_back s
    else if Wz.is_finished s.wizard then
      match key_str with "Enter" | "Escape" | "Esc" -> go_back s | _ -> s
    else
      let wizard = Wz.handle_key s.wizard ~key:key_str in
      if Wz.is_cancelled wizard then go_back {s with wizard}
      else {s with wizard}

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

include Demo_shared.Demo_page.MakeSimple (Inner)
