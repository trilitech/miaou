(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

(** Theme definition with semantic styles and CSS-like widget styling rules.
    
    A theme consists of:
    - Semantic styles (primary, error, text, etc.) for consistent appearance
    - Widget rules using CSS-like selectors for targeted styling
    
    Example theme JSON:
    {[
    {
      "name": "dark",
      "primary": { "fg": 75, "bold": true },
      "error": { "fg": 196 },
      "text": { "fg": 252 },
      "border": { "fg": 240 },
      "rules": {
        "table:focus": { "style": { "border_fg": 75 } },
        "flex_layout > :nth-child(even)": { "style": { "bg": 236 } },
        "modal .button": { "style": { "fg": 255, "bold": true } }
      }
    }
    ]}
*)

(** Widget style with optional border configuration *)
type widget_style = {
  style : Style.t;  (** Base style (colors, text attributes) *)
  border_style : Border.style option;  (** Optional border style override *)
  border_fg : Style.color option;  (** Optional border foreground color *)
  border_bg : Style.color option;  (** Optional border background color *)
}
[@@deriving yojson]

(** A style rule: selector -> widget style *)
type rule = {selector : Selector.t; widget_style : widget_style}

(** Theme definition *)
type t = {
  (* Metadata *)
  name : string;  (** Theme name (e.g., "dark", "light") *)
  (* Semantic styles *)
  primary : Style.t;  (** Primary accent color *)
  secondary : Style.t;  (** Secondary color *)
  accent : Style.t;  (** Accent/highlight color *)
  (* Status colors *)
  error : Style.t;  (** Error/danger *)
  warning : Style.t;  (** Warning *)
  success : Style.t;  (** Success/positive *)
  info : Style.t;  (** Information *)
  (* Text styles *)
  text : Style.t;  (** Normal text *)
  text_muted : Style.t;  (** Muted/secondary text *)
  text_emphasized : Style.t;  (** Emphasized text *)
  (* Background *)
  background : Style.t;  (** Main background *)
  background_secondary : Style.t;  (** Secondary/panel background *)
  (* Borders *)
  border : Style.t;  (** Default border *)
  border_focused : Style.t;  (** Focused border *)
  border_dim : Style.t;  (** Dimmed border *)
  (* Selection *)
  selection : Style.t;  (** Selected item *)
  (* Default border style *)
  default_border_style : Border.style;
  (* CSS-like rules for widget-specific styling *)
  rules : rule list;
}

(** {2 Default theme} *)

(** Empty widget style (inherits everything) *)
val empty_widget_style : widget_style

(** Default theme with sensible colors for dark terminals *)
val default : t

(** {2 Style resolution} *)

(** Find all rules matching a context, ordered by specificity (most specific last) *)
val matching_rules : t -> Selector.match_context -> rule list

(** Resolve the complete style for a widget context.
    Merges semantic styles with matching rules, respecting specificity. *)
val resolve_style : t -> Selector.match_context -> widget_style

(** Get semantic style by name (e.g., "primary", "error", "text") *)
val get_semantic_style : t -> string -> Style.t option

(** {2 Theme merging} *)

(** Merge two themes. Values from [overlay] take precedence when set. *)
val merge : base:t -> overlay:t -> t

(** {2 JSON serialization} *)

(** Convert theme to JSON *)
val to_yojson : t -> Yojson.Safe.t

(** Parse theme from JSON *)
val of_yojson : Yojson.Safe.t -> (t, string) result
