(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(** Tree widget for displaying hierarchical data structures.

    The widget renders a node tree with one row per visible node, indents
    descendants, and shows a marker (▾ for expanded internal nodes, ▸ for
    collapsed; ASCII fallback {b v} / {b >}). Leaves render with no marker.
    Keyboard input drives a single-cursor path through the visible rows.

    {b Typical usage}:
    {[
      (* Create a tree from JSON *)
      let json = Yojson.Safe.from_string {|
        {
          "name": "root",
          "children": [
            {"type": "leaf", "value": 42}
          ]
        }
      |}
      in
      let tree = Tree_widget.of_json json in
      let widget = Tree_widget.open_root tree in

      (* Render *)
      let output = Tree_widget.render widget ~focus:true in

      (* Or build a tree manually *)
      let tree = {
        Tree_widget.label = "Root";
        children = [
          {label = "Child 1"; children = []};
          {label = "Child 2"; children = [
            {label = "Grandchild"; children = []}
          ]}
        ]
      }
      in
      let widget = Tree_widget.open_root tree in
    ]}
*)

(** Tree node with label and children. *)
type node = {
  label : string;  (** Display text for this node *)
  children : node list;  (** Child nodes *)
}

(** Tree widget state.

    Path semantics: every node has a path from the root. The root's path is
    [\[0\]]. The {i n}th child of a node with path [p] has path [p @ \[n\]].
    The [expanded] field is the list of paths whose children are currently
    visible. After [open_root], no path is expanded — the root is the only
    visible row. Use {!handle_key} with ["Enter"] (or {!expand_all}) to reveal
    children. *)
type t = {
  root : node;  (** Root node of the tree *)
  cursor_path : int list;  (** Path of the highlighted row *)
  expanded : int list list;  (** Paths whose children are currently visible *)
}

(** {1 Construction} *)

(** Convert JSON value to tree node.

    Creates a tree structure from Yojson data:
    - Objects become nodes with label "obj" and children for each key
    - Lists become nodes with label "list" and children for each element
    - Primitives become leaf nodes with their string representation

    @param json Yojson value to convert
    @return Root node of the tree
*)
val of_json : Yojson.Safe.t -> node

(** Create a tree widget from a root node.

    The cursor starts on the root and no node is expanded — child rows are
    hidden until the user (or {!expand_all}) reveals them.

    @param node Root node of the tree
    @return Tree widget with cursor at [\[0\]] and [expanded = \[\]]
*)
val open_root : node -> t

(** {1 Mutation} *)

(** Expand every internal node — every node with at least one child becomes
    visible. Cursor is not moved. *)
val expand_all : t -> t

(** Collapse every node and reset the cursor to the root. *)
val collapse_all : t -> t

(** {1 Inspection} *)

(** Whether the node at [path] is currently expanded — i.e. its children are
    visible in the rendered output. *)
val is_expanded : int list -> t -> bool

(** Flatten the tree into the ordered sequence of visible rows, each tagged
    with its path and depth. The first element is always the root. Useful for
    custom rendering or for asserting visibility in tests. *)
val flatten_visible : t -> (node * int list * int) list

(** {1 Rendering} *)

(** Render the visible rows.

    Each visible node is rendered on its own line as
    [<indent><marker><label>]:
    - [<indent>] is two spaces per depth level
    - [<marker>] is [▾ ] for expanded internal nodes, [▸ ] for collapsed ones,
      and two spaces for leaves (kept for column alignment with internal
      siblings). When {!Widgets.prefer_ascii} is true, [v ] / [> ] are used.
    - The row at [cursor_path] is wrapped in {!Widgets.themed_selection}.

    @param focus Whether the widget has focus (currently not used to alter
                 rendering — selection is always shown).
    @return Rendered tree as a single newline-separated string.
*)
val render : t -> focus:bool -> string

(** {1 Input Handling} *)

(** Handle a keyboard event identified by its string name (matching
    {!Miaou_core.Keys.to_string}: [Up], [Down], [Left], [Right], [Enter],
    [Home], [End]).

    Behaviors:
    - [Down] / [Up] — move the cursor to the next / previous visible row,
      clamped at the ends.
    - [Home] / [End] — jump to the first / last visible row.
    - [Right] — if the current node has children and is collapsed, expand it
      in place; if it is already expanded, descend to its first child;
      otherwise no-op.
    - [Left] — if the current node is expanded, collapse it (cursor stays);
      otherwise move the cursor to its parent (if any).
    - [Enter] — toggle expansion at [cursor_path]. If the toggle hides the
      previous cursor (e.g. [collapse_all] or a stale path), the cursor falls
      back to the nearest visible ancestor.
    - Any other key — return [t] unchanged.

    @param key Key string ([Up], [Down], …)
    @return Updated tree widget. *)
val handle_key : t -> key:string -> t

(** {1 Internal Rendering} *)

(** Render a node with given indentation level.

    This function is kept for backward compatibility — it produces a plain
    indented dump without markers or selection styling. New code should use
    {!render} instead.

    @param indent Number of spaces to indent
    @param node Node to render
    @return Rendered string
*)
val render_node : int -> node -> string
