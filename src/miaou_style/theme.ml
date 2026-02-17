(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

type widget_style = {
  style : Style.t;
  border_style : Border.style option;
  border_fg : Style.color option;
  border_bg : Style.color option;
}
[@@deriving yojson]

type rule = {selector : Selector.t; widget_style : widget_style}

type t = {
  name : string;
  primary : Style.t;
  secondary : Style.t;
  accent : Style.t;
  error : Style.t;
  warning : Style.t;
  success : Style.t;
  info : Style.t;
  text : Style.t;
  text_muted : Style.t;
  text_emphasized : Style.t;
  background : Style.t;
  background_secondary : Style.t;
  border : Style.t;
  border_focused : Style.t;
  border_dim : Style.t;
  selection : Style.t;
  default_border_style : Border.style;
  rules : rule list;
}

let empty_widget_style =
  {style = Style.empty; border_style = None; border_fg = None; border_bg = None}

(* Default dark theme matching typical miaou colors *)
let default =
  {
    name = "default";
    primary = Style.make ~fg:(Style.Fixed 75) ~bold:true ();
    secondary = Style.make ~fg:(Style.Fixed 245) ();
    accent = Style.make ~fg:(Style.Fixed 135) ();
    error = Style.make ~fg:(Style.Fixed 196) ();
    warning = Style.make ~fg:(Style.Fixed 208) ();
    success = Style.make ~fg:(Style.Fixed 46) ();
    info = Style.make ~fg:(Style.Fixed 81) ();
    text = Style.make ~fg:(Style.Fixed 252) ();
    text_muted = Style.make ~fg:(Style.Fixed 242) ~dim:true ();
    text_emphasized = Style.make ~fg:(Style.Fixed 255) ~bold:true ();
    background = Style.empty;
    (* Use terminal default *)
    background_secondary = Style.make ~bg:(Style.Fixed 236) ();
    border = Style.make ~fg:(Style.Fixed 240) ();
    border_focused = Style.make ~fg:(Style.Fixed 75) ~bold:true ();
    border_dim = Style.make ~fg:(Style.Fixed 238) ~dim:true ();
    selection = Style.make ~fg:(Style.Fixed 255) ~bg:(Style.Fixed 238) ();
    default_border_style = Border.Rounded;
    rules = [];
  }

let matching_rules theme ctx =
  theme.rules
  |> List.filter (fun rule -> Selector.matches rule.selector ctx)
  |> List.sort (fun r1 r2 ->
      Selector.compare_specificity
        (Selector.specificity r1.selector)
        (Selector.specificity r2.selector))

let merge_widget_style ~base ~overlay =
  {
    style = Style.patch ~base:base.style ~overlay:overlay.style;
    border_style =
      (match overlay.border_style with
      | Some _ as s -> s
      | None -> base.border_style);
    border_fg =
      (match overlay.border_fg with Some _ as c -> c | None -> base.border_fg);
    border_bg =
      (match overlay.border_bg with Some _ as c -> c | None -> base.border_bg);
  }

let resolve_style theme ctx =
  let rules = matching_rules theme ctx in
  List.fold_left
    (fun acc rule -> merge_widget_style ~base:acc ~overlay:rule.widget_style)
    empty_widget_style
    rules

let get_semantic_style theme name =
  match String.lowercase_ascii name with
  | "primary" -> Some theme.primary
  | "secondary" -> Some theme.secondary
  | "accent" -> Some theme.accent
  | "error" -> Some theme.error
  | "warning" -> Some theme.warning
  | "success" -> Some theme.success
  | "info" -> Some theme.info
  | "text" -> Some theme.text
  | "text_muted" -> Some theme.text_muted
  | "text_emphasized" -> Some theme.text_emphasized
  | "background" -> Some theme.background
  | "background_secondary" -> Some theme.background_secondary
  | "border" -> Some theme.border
  | "border_focused" -> Some theme.border_focused
  | "border_dim" -> Some theme.border_dim
  | "selection" -> Some theme.selection
  | _ -> None

let merge_opt_style ~base ~overlay = Style.patch ~base ~overlay

let merge ~base ~overlay =
  {
    name =
      (if overlay.name = "" || overlay.name = "default" then base.name
       else overlay.name);
    primary = merge_opt_style ~base:base.primary ~overlay:overlay.primary;
    secondary = merge_opt_style ~base:base.secondary ~overlay:overlay.secondary;
    accent = merge_opt_style ~base:base.accent ~overlay:overlay.accent;
    error = merge_opt_style ~base:base.error ~overlay:overlay.error;
    warning = merge_opt_style ~base:base.warning ~overlay:overlay.warning;
    success = merge_opt_style ~base:base.success ~overlay:overlay.success;
    info = merge_opt_style ~base:base.info ~overlay:overlay.info;
    text = merge_opt_style ~base:base.text ~overlay:overlay.text;
    text_muted =
      merge_opt_style ~base:base.text_muted ~overlay:overlay.text_muted;
    text_emphasized =
      merge_opt_style
        ~base:base.text_emphasized
        ~overlay:overlay.text_emphasized;
    background =
      merge_opt_style ~base:base.background ~overlay:overlay.background;
    background_secondary =
      merge_opt_style
        ~base:base.background_secondary
        ~overlay:overlay.background_secondary;
    border = merge_opt_style ~base:base.border ~overlay:overlay.border;
    border_focused =
      merge_opt_style ~base:base.border_focused ~overlay:overlay.border_focused;
    border_dim =
      merge_opt_style ~base:base.border_dim ~overlay:overlay.border_dim;
    selection = merge_opt_style ~base:base.selection ~overlay:overlay.selection;
    default_border_style = overlay.default_border_style;
    rules = base.rules @ overlay.rules;
    (* Overlay rules come after, so have precedence *)
  }

(* JSON serialization - custom to handle rules properly *)

let[@warning "-32"] rule_to_yojson rule =
  `Assoc
    [
      ("selector", `String (Selector.to_string rule.selector));
      ("style", widget_style_to_yojson rule.widget_style);
    ]

let rule_of_yojson json =
  let open Yojson.Safe.Util in
  try
    let selector_str = json |> member "selector" |> to_string in
    let widget_style_json = json |> member "style" in
    match Selector.parse selector_str with
    | None -> Error ("Invalid selector: " ^ selector_str)
    | Some selector -> (
        match widget_style_of_yojson widget_style_json with
        | Ok widget_style -> Ok {selector; widget_style}
        | Error e -> Error e)
  with Type_error (msg, _) -> Error msg

let rules_of_yojson json =
  let open Yojson.Safe.Util in
  try
    (* Rules can be an object with selector keys or a list *)
    match json with
    | `Assoc pairs ->
        let results =
          List.map
            (fun (selector_str, style_json) ->
              match Selector.parse selector_str with
              | None -> Error ("Invalid selector: " ^ selector_str)
              | Some selector -> (
                  match widget_style_of_yojson style_json with
                  | Ok widget_style -> Ok {selector; widget_style}
                  | Error e -> Error e))
            pairs
        in
        let rec collect acc = function
          | [] -> Ok (List.rev acc)
          | Ok r :: rest -> collect (r :: acc) rest
          | Error e :: _ -> Error e
        in
        collect [] results
    | `List items ->
        let results = List.map rule_of_yojson items in
        let rec collect acc = function
          | [] -> Ok (List.rev acc)
          | Ok r :: rest -> collect (r :: acc) rest
          | Error e :: _ -> Error e
        in
        collect [] results
    | `Null -> Ok []
    | _ -> Error "Rules must be an object or list"
  with Type_error (msg, _) -> Error msg

let to_yojson t =
  let rules_json =
    `Assoc
      (List.map
         (fun r ->
           (Selector.to_string r.selector, widget_style_to_yojson r.widget_style))
         t.rules)
  in
  `Assoc
    [
      ("name", `String t.name);
      ("primary", Style.to_yojson t.primary);
      ("secondary", Style.to_yojson t.secondary);
      ("accent", Style.to_yojson t.accent);
      ("error", Style.to_yojson t.error);
      ("warning", Style.to_yojson t.warning);
      ("success", Style.to_yojson t.success);
      ("info", Style.to_yojson t.info);
      ("text", Style.to_yojson t.text);
      ("text_muted", Style.to_yojson t.text_muted);
      ("text_emphasized", Style.to_yojson t.text_emphasized);
      ("background", Style.to_yojson t.background);
      ("background_secondary", Style.to_yojson t.background_secondary);
      ("border", Style.to_yojson t.border);
      ("border_focused", Style.to_yojson t.border_focused);
      ("border_dim", Style.to_yojson t.border_dim);
      ("selection", Style.to_yojson t.selection);
      ("default_border_style", Border.style_to_yojson t.default_border_style);
      ("rules", rules_json);
    ]

let of_yojson json =
  let open Yojson.Safe.Util in
  try
    let get_style name =
      let j = member name json in
      if j = `Null then Ok Style.empty else Style.of_yojson j
    in
    let ( let* ) = Result.bind in
    let* name =
      Ok (member "name" json |> to_string_option |> Option.value ~default:"")
    in
    let* primary = get_style "primary" in
    let* secondary = get_style "secondary" in
    let* accent = get_style "accent" in
    let* error = get_style "error" in
    let* warning = get_style "warning" in
    let* success = get_style "success" in
    let* info = get_style "info" in
    let* text = get_style "text" in
    let* text_muted = get_style "text_muted" in
    let* text_emphasized = get_style "text_emphasized" in
    let* background = get_style "background" in
    let* background_secondary = get_style "background_secondary" in
    let* border = get_style "border" in
    let* border_focused = get_style "border_focused" in
    let* border_dim = get_style "border_dim" in
    let* selection = get_style "selection" in
    let* default_border_style =
      let j = member "default_border_style" json in
      if j = `Null then Ok Border.Rounded else Border.style_of_yojson j
    in
    let* rules = rules_of_yojson (member "rules" json) in
    Ok
      {
        name;
        primary;
        secondary;
        accent;
        error;
        warning;
        success;
        info;
        text;
        text_muted;
        text_emphasized;
        background;
        background_secondary;
        border;
        border_focused;
        border_dim;
        selection;
        default_border_style;
        rules;
      }
  with Type_error (msg, _) -> Error msg
