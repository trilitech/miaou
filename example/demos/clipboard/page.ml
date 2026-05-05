(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

module Inner = struct
  let tutorial_title = "Clipboard"

  let tutorial_markdown = [%blob "README.md"]

  module Clipboard = Miaou_interfaces.Clipboard
  module Toast = Miaou_widgets_layout.Toast_widget
  module Textbox = Miaou_widgets_input.Textbox_widget

  let pending_modal_copy : string option ref = ref None

  type state = {
    toasts : Toast.t;
    last_copied : string option;
    copy_count : int;
    next_page : string option;
  }

  type msg = unit

  let init () =
    {
      toasts = Toast.empty ();
      last_copied = None;
      copy_count = 0;
      next_page = None;
    }

  let update s (_ : msg) = s

  let go_back s =
    {s with next_page = Some Demo_shared.Demo_config.launcher_page_name}

  let toast s severity message =
    {s with toasts = Toast.enqueue s.toasts severity message}

  let copy_text s text =
    match Clipboard.get () with
    | None -> toast s Toast.Error "Clipboard not available"
    | Some clip ->
        if not (clip.copy_available ()) then
          toast s Toast.Warn "Clipboard disabled in driver"
        else (
          clip.copy text ;
          {
            s with
            toasts =
              Toast.enqueue
                s.toasts
                Toast.Success
                (Printf.sprintf "Copied: %s" text);
            last_copied = Some text;
            copy_count = s.copy_count + 1;
          })

  let queue_modal_copy text = if text <> "" then pending_modal_copy := Some text

  let open_copy_modal s =
    let module Copy_modal = struct
      type state = Textbox.t

      type pstate = state Miaou.Core.Navigation.t

      type msg = unit

      type key_binding = state Miaou.Core.Tui_page.key_binding_desc

      let init () =
        Miaou.Core.Navigation.make
          (Textbox.create ~placeholder:(Some "Enter text to copy...") ())

      let view ps ~focus ~size:_ =
        Textbox.render ps.Miaou.Core.Navigation.s ~focus

      let handle_key ps key_str ~size:_ =
        Miaou.Core.Navigation.update
          (fun textbox -> Textbox.handle_key textbox ~key:key_str)
          ps

      let handle_modal_key ps _ ~size:_ = ps

      let update ps _ = ps

      let move ps _ = ps

      let refresh ps = ps

      let service_select ps _ = ps

      let service_cycle ps _ = ps

      let back ps = ps

      let has_modal _ = false

      let keymap (_ : pstate) = []

      let handled_keys () = []

      let on_key ps key ~size =
        let key_str = Miaou.Core.Keys.to_string key in
        (handle_key ps key_str ~size, Miaou_interfaces.Key_event.Bubble)

      let on_modal_key ps key ~size =
        let key_str = Miaou.Core.Keys.to_string key in
        (handle_modal_key ps key_str ~size, Miaou_interfaces.Key_event.Bubble)

      let key_hints (_ : pstate) = []
    end in
    Miaou.Core.Modal_manager.push
      (module Copy_modal)
      ~init:(Copy_modal.init ())
      ~ui:
        {
          title = "Copy text";
          left = Some 10;
          max_width = Some (Fixed 60);
          dim_background = true;
        }
      ~commit_on:["Enter"]
      ~cancel_on:["Esc"]
      ~on_close:(fun modal_ps -> function
        | `Commit ->
            modal_ps.Miaou.Core.Navigation.s |> Textbox.get_text
            |> queue_modal_copy
        | `Cancel -> ()) ;
    s

  let samples =
    [|
      "Hello, clipboard!";
      "git status";
      "ssh user@example.com";
      "https://github.com/trilitech/miaou";
      "Lorem ipsum dolor sit amet";
    |]

  let view s ~focus:_ ~size =
    let module W = Miaou_widgets_display.Widgets in
    let sample_lines =
      samples |> Array.to_list
      |> List.mapi (fun i sample ->
          W.themed_text (Printf.sprintf "%d. %s" (i + 1) sample))
      |> String.concat "\n"
    in
    let last =
      match s.last_copied with
      | None -> "none"
      | Some text ->
          if String.length text > 34 then String.sub text 0 31 ^ "..." else text
    in
    let status =
      W.themed_muted (Printf.sprintf "Copies: %d | Last: %s" s.copy_count last)
    in
    let toasts = Toast.render s.toasts ~cols:size.LTerm_geom.cols in
    String.concat
      "\n\n"
      [
        W.titleize "Clipboard";
        W.dim
          "Space/Enter: modal copy | 1-5: quick copy | t: tutorial | Esc: back";
        W.themed_text
          "The demo copies text through the registered Clipboard capability.";
        sample_lines;
        status;
        toasts;
      ]

  let handle_key s key_str ~size:_ =
    match Miaou.Core.Keys.of_string key_str with
    | Some Miaou.Core.Keys.Escape -> go_back s
    | Some Miaou.Core.Keys.Enter | Some (Miaou.Core.Keys.Char " ") ->
        open_copy_modal s
    | Some (Miaou.Core.Keys.Char key) -> (
        match int_of_string_opt key with
        | Some n when n >= 1 && n <= Array.length samples ->
            copy_text s samples.(n - 1)
        | _ -> s)
    | _ -> s

  let move s _ = s

  let refresh s =
    let s = {s with toasts = Toast.tick s.toasts} in
    match !pending_modal_copy with
    | None -> s
    | Some text ->
        pending_modal_copy := None ;
        copy_text s text

  let enter s = s

  let service_select s _ = s

  let service_cycle s _ = refresh s

  let handle_modal_key s _ ~size:_ = s

  let next_page s = s.next_page

  let keymap (_ : state) = []

  let handled_keys () = []

  let back s = go_back s

  let has_modal _ = Miaou.Core.Modal_manager.has_active ()
end

include Demo_shared.Demo_page.MakeSimple (Inner)
