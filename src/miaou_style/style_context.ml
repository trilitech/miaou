(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

type _ Effect.t += Get_theme : Theme.t Effect.t

type _ Effect.t += Get_match_context : Selector.match_context Effect.t

(* Effect for updating the theme at runtime *)
type _ Effect.t += Set_theme : Theme.t -> unit Effect.t

let with_theme (theme : Theme.t) (f : unit -> 'a) : 'a =
  Effect.Deep.try_with
    f
    ()
    {
      effc =
        (fun (type a) (eff : a Effect.t) ->
          match eff with
          | Get_theme ->
              Some
                (fun (k : (a, _) Effect.Deep.continuation) ->
                  Effect.Deep.continue k theme)
          | _ -> None);
    }

let with_mutable_theme (initial : Theme.t) (f : unit -> 'a) : 'a =
  let theme_ref = ref initial in
  Effect.Deep.try_with
    f
    ()
    {
      effc =
        (fun (type a) (eff : a Effect.t) ->
          match eff with
          | Get_theme ->
              Some
                (fun (k : (a, _) Effect.Deep.continuation) ->
                  Effect.Deep.continue k !theme_ref)
          | Set_theme new_theme ->
              Some
                (fun (k : (a, _) Effect.Deep.continuation) ->
                  theme_ref := new_theme ;
                  Effect.Deep.continue k ())
          | _ -> None);
    }

let set_theme theme =
  try Effect.perform (Set_theme theme)
  with Effect.Unhandled (Set_theme _) ->
    (* No mutable handler installed, silently ignore *)
    ()

let reload_theme () =
  let theme = Theme_loader.load () in
  set_theme theme ;
  theme

let with_context (theme : Theme.t) (ctx : Selector.match_context)
    (f : unit -> 'a) : 'a =
  Effect.Deep.try_with
    f
    ()
    {
      effc =
        (fun (type a) (eff : a Effect.t) ->
          match eff with
          | Get_theme ->
              Some
                (fun (k : (a, _) Effect.Deep.continuation) ->
                  Effect.Deep.continue k theme)
          | Get_match_context ->
              Some
                (fun (k : (a, _) Effect.Deep.continuation) ->
                  Effect.Deep.continue k ctx)
          | _ -> None);
    }

let current_theme () : Theme.t =
  try Effect.perform Get_theme
  with Effect.Unhandled Get_theme -> Theme.default

let current_context () : Selector.match_context =
  try Effect.perform Get_match_context
  with Effect.Unhandled Get_match_context -> Selector.empty_context

let with_child_context ?widget_name ?focused ?selected ?index ?count ?ancestors
    (f : unit -> 'a) : 'a =
  let theme = current_theme () in
  let parent_ctx = current_context () in
  let new_ctx =
    {
      Selector.widget_name =
        Option.value widget_name ~default:parent_ctx.widget_name;
      focused = Option.value focused ~default:parent_ctx.focused;
      selected = Option.value selected ~default:parent_ctx.selected;
      hover = parent_ctx.hover;
      disabled = parent_ctx.disabled;
      child_index = index;
      child_count = count;
      ancestors =
        (match ancestors with
        | Some a -> a
        | None ->
            if parent_ctx.widget_name <> "" then
              parent_ctx.widget_name :: parent_ctx.ancestors
            else parent_ctx.ancestors);
    }
  in
  with_context theme new_ctx f

let current_style () : Theme.widget_style =
  let theme = current_theme () in
  let ctx = current_context () in
  Theme.resolve_style theme ctx

let primary () = (current_theme ()).primary

let secondary () = (current_theme ()).secondary

let accent () = (current_theme ()).accent

let error () = (current_theme ()).error

let warning () = (current_theme ()).warning

let success () = (current_theme ()).success

let info () = (current_theme ()).info

let text () = (current_theme ()).text

let text_muted () = (current_theme ()).text_muted

let text_emphasized () = (current_theme ()).text_emphasized

let background () = (current_theme ()).background

let background_secondary () = (current_theme ()).background_secondary

let selection () = (current_theme ()).selection

let border ?(focus = false) () =
  let theme = current_theme () in
  if focus then theme.border_focused else theme.border

let default_border_style () = (current_theme ()).default_border_style

let styled s =
  let theme = current_theme () in
  let ws = current_style () in
  let resolved = Style.to_resolved ~dark_mode:theme.dark_mode ws.style in
  Style.apply resolved s

let styled_with style s =
  let theme = current_theme () in
  let resolved = Style.to_resolved ~dark_mode:theme.dark_mode style in
  Style.apply resolved s

let widget_style name =
  let theme = current_theme () in
  let ctx = {(current_context ()) with widget_name = name} in
  Theme.resolve_style theme ctx
