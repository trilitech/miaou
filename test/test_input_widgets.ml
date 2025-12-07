open Alcotest

module Checkbox = Miaou_widgets_input.Checkbox_widget
module Radio = Miaou_widgets_input.Radio_button_widget
module Switch = Miaou_widgets_input.Switch_widget
module Button = Miaou_widgets_input.Button_widget

let test_checkbox_disabled () =
  let cb = Checkbox.create ~checked_:false ~disabled:true () in
  let cb' = Checkbox.handle_key cb ~key:"Space" in
  check bool "unchanged when disabled" false (Checkbox.is_checked cb')

let test_radio_disabled () =
  let r = Radio.create ~selected:false ~disabled:true () in
  let r' = Radio.handle_key r ~key:"Enter" in
  check bool "no select when disabled" false (Radio.is_selected r')

let test_switch_disabled () =
  let sw = Switch.create ~on:false ~disabled:true () in
  let sw' = Switch.handle_key sw ~key:"Enter" in
  check bool "no toggle when disabled" false (Switch.is_on sw')

let test_button_disabled () =
  let fired = ref 0 in
  let b, pressed =
    Button.create ~disabled:true ~label:"Save" ~on_click:(fun () -> incr fired)
      ()
    |> fun b -> Button.handle_key b ~key:"Enter"
  in
  check bool "no fire when disabled" false pressed ;
  check int "callback untouched" 0 !fired ;
  (* ensure render still works with focus and returns dimmed string *)
  ignore (Button.render b ~focus:true)

let () =
  run
    "input_widgets"
    [
      ( "disabled",
        [ test_case "checkbox disabled" `Quick test_checkbox_disabled;
          test_case "radio disabled" `Quick test_radio_disabled;
          test_case "switch disabled" `Quick test_switch_disabled;
          test_case "button disabled" `Quick test_button_disabled ] );
    ]
