(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

type pseudo_class =
  | Focus
  | Selected
  | Hover
  | Disabled
  | First_child
  | Last_child
  | Nth_child_even
  | Nth_child_odd
  | Nth_child of int
[@@deriving yojson]

type simple_selector = {
  element : string option;
  pseudo_classes : pseudo_class list;
}
[@@deriving yojson]

type combinator = Descendant | Child [@@deriving yojson]

type t = {parts : (simple_selector * combinator option) list}
[@@deriving yojson]

type match_context = {
  widget_name : string;
  focused : bool;
  selected : bool;
  hover : bool;
  disabled : bool;
  child_index : int option;
  child_count : int option;
  ancestors : string list;
}

let empty_context =
  {
    widget_name = "";
    focused = false;
    selected = false;
    hover = false;
    disabled = false;
    child_index = None;
    child_count = None;
    ancestors = [];
  }

let context_of_widget name = {empty_context with widget_name = name}

(* Parsing helpers *)

let is_ident_char c =
  (c >= 'a' && c <= 'z')
  || (c >= 'A' && c <= 'Z')
  || (c >= '0' && c <= '9')
  || c = '_' || c = '-'

let skip_whitespace s i =
  let len = String.length s in
  let rec loop i =
    if i < len && (s.[i] = ' ' || s.[i] = '\t') then loop (i + 1) else i
  in
  loop i

let parse_ident s i =
  let len = String.length s in
  let start = i in
  let rec loop i = if i < len && is_ident_char s.[i] then loop (i + 1) else i in
  let end_i = loop i in
  if end_i > start then Some (String.sub s start (end_i - start), end_i)
  else None

let parse_pseudo_class s i =
  (* Expects to start after ':' *)
  match parse_ident s i with
  | None -> None
  | Some (name, i) -> (
      let name_lower = String.lowercase_ascii name in
      match name_lower with
      | "focus" -> Some (Focus, i)
      | "selected" -> Some (Selected, i)
      | "hover" -> Some (Hover, i)
      | "disabled" -> Some (Disabled, i)
      | "first-child" -> Some (First_child, i)
      | "last-child" -> Some (Last_child, i)
      | "nth-child" ->
          (* Parse (even), (odd), or (n) *)
          let len = String.length s in
          if i < len && s.[i] = '(' then
            let i = i + 1 in
            let i = skip_whitespace s i in
            match parse_ident s i with
            | Some ("even", i) ->
                let i = skip_whitespace s i in
                if i < len && s.[i] = ')' then Some (Nth_child_even, i + 1)
                else None
            | Some ("odd", i) ->
                let i = skip_whitespace s i in
                if i < len && s.[i] = ')' then Some (Nth_child_odd, i + 1)
                else None
            | _ ->
                (* Try parsing a number *)
                let start = i in
                let rec parse_num i =
                  if i < len && s.[i] >= '0' && s.[i] <= '9' then
                    parse_num (i + 1)
                  else i
                in
                let end_i = parse_num i in
                if end_i > start then
                  let n = int_of_string (String.sub s start (end_i - start)) in
                  let i = skip_whitespace s end_i in
                  if i < len && s.[i] = ')' then Some (Nth_child n, i + 1)
                  else None
                else None
          else None
      | _ -> None)

let parse_simple_selector s i =
  let len = String.length s in
  let i = skip_whitespace s i in

  (* Parse element name (optional) *)
  let element, i =
    if i < len && s.[i] = '*' then (None, i + 1) (* Universal selector *)
    else
      match parse_ident s i with
      | Some (name, i) -> (Some name, i)
      | None -> (None, i)
    (* No element, will have pseudo-classes *)
  in

  (* Parse pseudo-classes *)
  let rec parse_pseudo_classes i acc =
    if i < len && s.[i] = ':' then
      match parse_pseudo_class s (i + 1) with
      | Some (pc, i) -> parse_pseudo_classes i (pc :: acc)
      | None -> (List.rev acc, i)
    else (List.rev acc, i)
  in
  let pseudo_classes, i = parse_pseudo_classes i [] in

  (* Must have at least element or pseudo-class *)
  if element = None && pseudo_classes = [] then None
  else Some ({element; pseudo_classes}, i)

let parse s =
  let len = String.length s in
  let rec loop i acc =
    let i = skip_whitespace s i in
    if i >= len then
      (* End of string - finalize last part with no combinator *)
      match acc with
      | [] -> None
      | (sel, _) :: rest -> Some {parts = List.rev ((sel, None) :: rest)}
    else
      match parse_simple_selector s i with
      | None -> None
      | Some (sel, i) ->
          let i = skip_whitespace s i in
          if i >= len then Some {parts = List.rev ((sel, None) :: acc)}
          else
            (* Check for combinator *)
            let comb, i =
              if s.[i] = '>' then (Some Child, skip_whitespace s (i + 1))
              else
                (* Space = descendant combinator *)
                (Some Descendant, i)
            in
            loop i ((sel, comb) :: acc)
  in
  loop 0 []

let parse_exn s =
  match parse s with
  | Some sel -> sel
  | None -> invalid_arg ("Invalid selector: " ^ s)

(* Convert to string *)

let pseudo_class_to_string = function
  | Focus -> ":focus"
  | Selected -> ":selected"
  | Hover -> ":hover"
  | Disabled -> ":disabled"
  | First_child -> ":first-child"
  | Last_child -> ":last-child"
  | Nth_child_even -> ":nth-child(even)"
  | Nth_child_odd -> ":nth-child(odd)"
  | Nth_child n -> Printf.sprintf ":nth-child(%d)" n

let simple_selector_to_string sel =
  let elem = match sel.element with Some e -> e | None -> "" in
  let pseudos =
    String.concat "" (List.map pseudo_class_to_string sel.pseudo_classes)
  in
  elem ^ pseudos

let to_string t =
  let rec loop = function
    | [] -> ""
    | [(sel, _)] -> simple_selector_to_string sel
    | (sel, Some Child) :: rest ->
        simple_selector_to_string sel ^ " > " ^ loop rest
    | (sel, Some Descendant) :: rest ->
        simple_selector_to_string sel ^ " " ^ loop rest
    | (sel, None) :: rest -> simple_selector_to_string sel ^ " " ^ loop rest
  in
  loop t.parts

(* Matching *)

let matches_pseudo_class pc ctx =
  match pc with
  | Focus -> ctx.focused
  | Selected -> ctx.selected
  | Hover -> ctx.hover
  | Disabled -> ctx.disabled
  | First_child -> ( match ctx.child_index with Some 0 -> true | _ -> false)
  | Last_child -> (
      match (ctx.child_index, ctx.child_count) with
      | Some i, Some c -> i = c - 1
      | _ -> false)
  | Nth_child_even -> (
      match ctx.child_index with Some i -> i mod 2 = 0 | None -> false)
  | Nth_child_odd -> (
      match ctx.child_index with Some i -> i mod 2 = 1 | None -> false)
  | Nth_child n -> (
      match ctx.child_index with Some i -> i = n - 1 | None -> false)

let matches_simple_selector sel ctx =
  (* Element must match (or be None for universal) *)
  let elem_matches =
    match sel.element with
    | None -> true
    | Some e ->
        String.lowercase_ascii e = String.lowercase_ascii ctx.widget_name
  in
  elem_matches
  && List.for_all (fun pc -> matches_pseudo_class pc ctx) sel.pseudo_classes

let rec matches_with_ancestors parts ancestors ctx =
  match parts with
  | [] -> true
  | [(sel, _)] -> matches_simple_selector sel ctx
  | (sel, Some Child) :: rest ->
      (* Direct child: must match current, then parent must match rest *)
      if not (matches_simple_selector sel ctx) then false
      else begin
        match ancestors with
        | [] -> false
        | parent :: grandparents ->
            let parent_ctx =
              {ctx with widget_name = parent; ancestors = grandparents}
            in
            matches_with_ancestors rest grandparents parent_ctx
      end
  | (sel, Some Descendant) :: rest ->
      (* Descendant: must match current, then some ancestor must match rest *)
      if not (matches_simple_selector sel ctx) then false
      else begin
        let rec try_ancestors anc =
          match anc with
          | [] -> List.length rest = 0 (* Only valid if nothing left to match *)
          | parent :: grandparents ->
              let parent_ctx =
                {ctx with widget_name = parent; ancestors = grandparents}
              in
              matches_with_ancestors rest grandparents parent_ctx
              || try_ancestors grandparents
        in
        try_ancestors ancestors
      end
  | (sel, None) :: rest ->
      matches_simple_selector sel ctx
      && matches_with_ancestors rest ctx.ancestors ctx

let matches t ctx =
  (* Reverse parts to match from the target (rightmost) first *)
  let reversed_parts = List.rev t.parts in
  matches_with_ancestors reversed_parts ctx.ancestors ctx

(* Specificity *)

type specificity = int * int

let specificity t =
  let pseudo_count = ref 0 in
  let elem_count = ref 0 in
  List.iter
    (fun (sel, _) ->
      if sel.element <> None then incr elem_count ;
      pseudo_count := !pseudo_count + List.length sel.pseudo_classes)
    t.parts ;
  (!pseudo_count, !elem_count)

let compare_specificity (p1, e1) (p2, e2) =
  match compare p1 p2 with 0 -> compare e1 e2 | c -> c
