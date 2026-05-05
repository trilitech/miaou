open Alcotest
module Demo = Clipboard_demo.Page.Inner
module Clipboard = Miaou_interfaces.Clipboard
module Toast = Miaou_widgets_layout.Toast_widget

let register_clipboard ~available ~copied =
  Clipboard.set
    {
      Clipboard.copy = (fun text -> copied := text :: !copied);
      copy_available = (fun () -> available);
    }

let toast_messages s =
  s.Demo.toasts |> Toast.to_list |> List.map (fun t -> t.Toast.message)

let reset_pending () = Demo.pending_modal_copy := None

let test_quick_copy_records_success () =
  reset_pending () ;
  let copied = ref [] in
  register_clipboard ~available:true ~copied ;
  let s = Demo.copy_text (Demo.init ()) "hello" in
  check (list string) "copied text" ["hello"] (List.rev !copied) ;
  check int "copy count" 1 s.copy_count ;
  check (option string) "last copied" (Some "hello") s.last_copied ;
  check (list string) "success toast" ["Copied: hello"] (toast_messages s)

let test_disabled_quick_copy_does_not_report_success () =
  reset_pending () ;
  let copied = ref [] in
  register_clipboard ~available:false ~copied ;
  let s = Demo.copy_text (Demo.init ()) "hello" in
  check (list string) "nothing copied" [] !copied ;
  check int "copy count unchanged" 0 s.copy_count ;
  check (option string) "no last copied" None s.last_copied ;
  check
    (list string)
    "disabled warning"
    ["Clipboard disabled in driver"]
    (toast_messages s)

let test_modal_pending_copy_uses_same_disabled_path () =
  reset_pending () ;
  let copied = ref [] in
  register_clipboard ~available:false ~copied ;
  Demo.queue_modal_copy "modal text" ;
  let s = Demo.refresh (Demo.init ()) in
  check (list string) "nothing copied" [] !copied ;
  check int "copy count unchanged" 0 s.copy_count ;
  check (option string) "no last copied" None s.last_copied ;
  check
    (list string)
    "disabled warning"
    ["Clipboard disabled in driver"]
    (toast_messages s)

let () =
  run
    "clipboard_demo"
    [
      ( "copy",
        [
          test_case
            "quick copy records success"
            `Quick
            test_quick_copy_records_success;
          test_case
            "disabled quick copy does not report success"
            `Quick
            test_disabled_quick_copy_does_not_report_success;
          test_case
            "modal pending copy uses disabled path"
            `Quick
            test_modal_pending_copy_uses_same_disabled_path;
        ] );
    ]
