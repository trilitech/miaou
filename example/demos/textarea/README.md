# Textarea Widget

A multiline text input widget with cursor navigation and scroll support.

## Features

- **Alt+Enter** to insert newlines (Enter reserved for form submission)
- Arrow key navigation between lines
- Home/End for start/end of line
- Automatic line joining on backspace/delete at boundaries
- Scroll support when content exceeds visible height
- Line indicator showing current position

## Usage

```ocaml
let textarea = Textarea_widget.open_centered
  ~title:"Description"
  ~width:60
  ~height:8
  ~placeholder:"Enter description..."
  ()

(* In view *)
Textarea_widget.render textarea ~focus:true

(* Handle keys *)
let textarea' = Textarea_widget.handle_key textarea ~key

(* Get final text *)
let text = Textarea_widget.get_text textarea'
```

## Keys

- **Alt+Enter**: Insert newline
- **Backspace**: Delete before cursor (joins lines at boundary)
- **Delete**: Delete at cursor (joins lines at boundary)
- **Arrow keys**: Navigate
- **Home/End**: Start/end of line
- **Esc**: Mark as cancelled
