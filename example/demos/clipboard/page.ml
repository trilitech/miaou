(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

module Inner = struct
  let tutorial_title = "Clipboard"

  let tutorial_markdown = [%blob "README.md"]

  module Clipboard = Miaou_interfaces.Clipboard
  module Toast = Miaou_widgets_layout.Toast_widget
  module Textbox = Miaou_widgets_input.Textbox_widget

  (* Global ref to store text copied from modal *)
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

  let copy_text s text =
    match Clipboard.get () with
    | None ->
        {
          s with
          toasts = Toast.enqueue s.toasts Toast.Error "Clipboard not available";
        }
    | Some clip ->
        if not (clip.copy_available ()) then
          {
            s with
            toasts =
              Toast.enqueue s.toasts Toast.Warn "Clipboard disabled in driver";
          }
        else (
          clip.copy text ;
          {
            s with
            toasts =
              Toast.enqueue s.toasts Toast.Info
                (Printf.sprintf "Sent to clipboard: %s" text);
            last_copied = Some text;
            copy_count = s.copy_count + 1;
          })

  let open_copy_modal s =
    (* Define a modal module for the textbox *)
    let module Copy_modal = struct
      type state = Textbox.t

      type pstate = state Miaou.Core.Navigation.t

      type msg = unit

      type key_binding = state Miaou.Core.Tui_page.key_binding_desc

      let init () =
        Miaou.Core.Navigation.make
          (Textbox.create ~placeholder:(Some "Enter text to copy...") ())

      let view ps ~focus ~size:_ =
        let textbox = ps.Miaou.Core.Navigation.s in
        Textbox.render textbox ~focus

      let handle_key ps key_str ~size:_ =
        let textbox = ps.Miaou.Core.Navigation.s in
        let textbox' = Textbox.handle_key textbox ~key:key_str in
        Miaou.Core.Navigation.update (fun _ -> textbox') ps

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
          title = "Enter text to copy";
          left = Some 10;
          max_width = Some (Fixed 60);
          dim_background = true;
        }
      ~commit_on:["Enter"]
      ~cancel_on:["Esc"]
      ~on_close:(fun modal_ps outcome ->
        match outcome with
        | `Commit ->
            let textbox = modal_ps.Miaou.Core.Navigation.s in
            let text = Textbox.get_text textbox in
            if text <> "" then (
              (* Copy to clipboard *)
              match Clipboard.get () with
              | Some clip -> 
                  clip.copy text ;
                  (* Store for toast notification in next refresh *)
                  pending_modal_copy := Some text
              | None -> 
                  pending_modal_copy := Some "" (* Empty string = error *))
        | `Cancel -> ()) ;
    s

  let view s ~focus:_ ~size =
    let module W = Miaou_widgets_display.Widgets in
    let header = W.titleize "Clipboard Demo" in
    let tips =
      W.dim
        "Press Space/Enter to open copy modal • 1-5: copy samples • t: \
         tutorial • Esc: back"
    in

    let instructions =
      W.themed_text
        "This demo shows how to copy text to clipboard from a modal.\n\
         Press Space or Enter to open a modal where you can type text.\n\
         When you press Enter in the modal, it attempts to copy to clipboard.\n\
         \n\
         Note: Install wl-clipboard (Wayland) or xclip (X11) for reliable copying.\n\
         Without native tools, OSC 52 is used which may not work in all terminals."
    in

    let samples_section =
      let title = W.themed_emphasis "Quick Copy Samples:" in
      let samples =
        [
          "1. Hello, clipboard!";
          "2. git status";
          "3. ssh user@example.com";
          "4. https://github.com/nomadic-labs/miaou";
          "5. Lorem ipsum dolor sit amet";
        ]
        |> List.map W.themed_text
        |> String.concat "\n"
      in
      String.concat "\n" [title; samples]
    in

    let status_section =
      let copy_count_msg =
        W.themed_muted
          (Printf.sprintf "Copies: %d • Last: %s" s.copy_count
             (match s.last_copied with
             | None -> "none"
             | Some text ->
                 if String.length text > 30 then String.sub text 0 27 ^ "..."
                 else text))
      in
      copy_count_msg
    in

    let toasts = Toast.render s.toasts ~cols:size.LTerm_geom.cols in

    String.concat "\n\n"
      [header; tips; instructions; samples_section; status_section; toasts]

  let handle_key s key_str ~size:_ =
    match Miaou.Core.Keys.of_string key_str with
    | Some Miaou.Core.Keys.Escape -> go_back s
    | Some Miaou.Core.Keys.Enter | Some (Miaou.Core.Keys.Char " ") ->
        open_copy_modal s
    | Some (Miaou.Core.Keys.Char "1") -> copy_text s "Hello, clipboard!"
    | Some (Miaou.Core.Keys.Char "2") -> copy_text s "git status"
    | Some (Miaou.Core.Keys.Char "3") -> copy_text s "ssh user@example.com"
    | Some (Miaou.Core.Keys.Char "4") ->
        copy_text s "https://github.com/nomadic-labs/miaou"
    | Some (Miaou.Core.Keys.Char "5") ->
        copy_text s "Lorem ipsum dolor sit amet, consectetur adipiscing elit"
    | _ -> s

  let move s _ = s

  let refresh s = 
    let s = {s with toasts = Toast.tick s.toasts} in
    (* Process pending modal copy *)
    match !pending_modal_copy with
    | None -> s
    | Some "" ->
        (* Error case *)
        pending_modal_copy := None ;
        {s with toasts = Toast.enqueue s.toasts Toast.Error "Clipboard not available"}
    | Some text ->
        (* Success case *)
        pending_modal_copy := None ;
        {
          s with
          toasts = Toast.enqueue s.toasts Toast.Info (Printf.sprintf "Sent to clipboard: %s" text);
          last_copied = Some text;
          copy_count = s.copy_count + 1;
        }

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
