# Mouse Control in MIAOU

By default, MIAOU enables mouse tracking in terminal applications. This allows for mouse-based interaction but interferes with traditional terminal copy/paste operations.

## Disabling Mouse Tracking

### Option 1: Environment Variable (Recommended for end users)

The simplest way is to set the `MIAOU_ENABLE_MOUSE` environment variable:

```sh
# Disable mouse tracking
MIAOU_ENABLE_MOUSE=0 ./your_app

# Alternative syntaxes
MIAOU_ENABLE_MOUSE=false ./your_app
MIAOU_ENABLE_MOUSE=no ./your_app
```

### Option 2: Programmatic Configuration (For library authors)

If you're building a library or application on top of MIAOU and want to disable mouse tracking programmatically:

#### Direct driver usage (Matrix driver)

```ocaml
(* Method 1: Use a custom config *)
let config = 
  Miaou_driver_matrix.Matrix_config.load () 
  |> Miaou_driver_matrix.Matrix_config.with_mouse_disabled
in
let _outcome = Miaou_driver_matrix.Matrix_driver.run ~config:(Some config) my_page in
()

(* Method 2: Create config from scratch *)
let config = {
  Miaou_driver_matrix.Matrix_config.default with
  enable_mouse = false
} in
let _outcome = Miaou_driver_matrix.Matrix_driver.run ~config:(Some config) my_page in
()
```

#### Using the runner (multi-driver support)

If you're using the `miaou-runner` package which supports multiple backends, you'll need to set the environment variable before calling the runner, as the runner doesn't expose config parameters:

```ocaml
(* Set environment variable before starting *)
Unix.putenv "MIAOU_ENABLE_MOUSE" "0";

(* Then run normally *)
let outcome = Miaou_runner.Runner_native.run my_page in
()
```

## Why Disable Mouse Tracking?

- **Copy/Paste**: In many terminals, mouse selection is used for copying text. When mouse tracking is enabled, the terminal sends mouse events to the application instead of handling selection locally.
- **Terminal Compatibility**: Some terminals or terminal emulators may have issues with mouse tracking.
- **User Preference**: Some users prefer keyboard-only interaction and want to use their terminal's native copy/paste features.

## Implementation Details

Mouse tracking is implemented using ANSI escape sequences:
- Enable: `\027[?1000h\027[?1006h` (SGR mouse mode)
- Disable: `\027[?1006l\027[?1015l\027[?1005l\027[?1003l\027[?1002l\027[?1000l`

The disable sequence is always sent during cleanup to ensure the terminal is restored to its original state.
