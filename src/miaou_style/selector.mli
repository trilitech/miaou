(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

(** CSS-like selector system for widget styling.
    
    Selectors allow targeting specific widgets and their states.
    They support:
    - Widget names: ["table"], ["modal"], ["flex_layout"]
    - Pseudo-classes: [":focus"], [":selected"], [":hover"]
    - Positional: [":first-child"], [":last-child"], [":nth-child(even)"], [":nth-child(odd)"], [":nth-child(3)"]
    - Combinators: ["parent > child"] (direct child), ["ancestor descendant"] (any descendant)
    
    Example selectors:
    - ["table"] - matches any table widget
    - ["table:focus"] - matches focused table
    - ["flex_layout > :nth-child(even)"] - matches even children of flex_layout
    - ["modal .button:focus"] - matches focused button inside modal
*)

(** Pseudo-class selectors *)
type pseudo_class =
  | Focus  (** :focus - widget has input focus *)
  | Selected  (** :selected - item is selected *)
  | Hover  (** :hover - mouse is over (if supported) *)
  | Disabled  (** :disabled - widget is disabled *)
  | First_child  (** :first-child - first child of parent *)
  | Last_child  (** :last-child - last child of parent *)
  | Nth_child_even  (** :nth-child(even) - even-indexed children *)
  | Nth_child_odd  (** :nth-child(odd) - odd-indexed children *)
  | Nth_child of int  (** :nth-child(n) - specific index (1-based) *)
[@@deriving yojson]

(** A single selector part (element + pseudo-classes) *)
type simple_selector = {
  element : string option;  (** Widget name, or None for universal selector *)
  pseudo_classes : pseudo_class list;  (** Pseudo-classes to match *)
}
[@@deriving yojson]

(** Combinator between selector parts *)
type combinator =
  | Descendant  (** space: ancestor descendant *)
  | Child  (** >: parent > child *)
[@@deriving yojson]

(** A complete selector (chain of simple selectors with combinators) *)
type t = {
  parts : (simple_selector * combinator option) list;
      (** List of (selector, combinator_to_next) pairs.
      Last element should have [None] combinator. *)
}
[@@deriving yojson]

(** Context for matching selectors against widgets *)
type match_context = {
  widget_name : string;  (** Name of the widget being styled *)
  focused : bool;  (** Whether widget has focus *)
  selected : bool;  (** Whether widget/item is selected *)
  hover : bool;  (** Whether mouse is hovering *)
  disabled : bool;  (** Whether widget is disabled *)
  child_index : int option;  (** Index among siblings (0-based) *)
  child_count : int option;  (** Total number of siblings *)
  ancestors : string list;  (** Ancestor widget names (nearest first) *)
}

(** Default match context *)
val empty_context : match_context

(** Create a simple context with just widget name *)
val context_of_widget : string -> match_context

(** {2 Selector parsing} *)

(** Parse a selector string.
    
    Examples:
    - ["table"] -> matches widget named "table"
    - ["table:focus"] -> matches focused table
    - [":first-child"] -> matches first child of any parent
    - ["flex > :nth-child(even)"] -> even children of flex
    - ["modal .button"] -> button inside modal (any depth)
    
    Returns [None] if parsing fails. *)
val parse : string -> t option

(** Parse a selector string, raising [Invalid_argument] on failure *)
val parse_exn : string -> t

(** Convert selector back to string representation *)
val to_string : t -> string

(** {2 Selector matching} *)

(** Check if a selector matches the given context *)
val matches : t -> match_context -> bool

(** {2 Selector specificity} *)

(** Specificity for ordering selectors. Higher values are more specific.
    Follows CSS specificity rules: (pseudo-class count, element count) *)
type specificity = int * int

(** Calculate specificity of a selector *)
val specificity : t -> specificity

(** Compare two specificities. Returns positive if first is more specific. *)
val compare_specificity : specificity -> specificity -> int
