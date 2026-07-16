# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **New `miaou serve` command and `Miaou_serve.run` library entry point (Slice 1 of a multi-slice build)**: an app can now be exposed over HTTP/WebSocket via a CSPRNG-generated, constant-time-compared session token instead of today's plain shared password, and the server refuses to bind a non-loopback address unless an auth mechanism (or an explicit override flag) is configured. This slice proves the CLI/token/fail-closed-default surface only — process-per-session isolation (separate worker processes, multi-session support, viewer read-only enforcement, reconnect) lands in later slices.
- **`miaou serve` now runs each session in its own worker process (Slice 2)**: the server is a lightweight supervisor that spawns one isolated worker process per session (in a private, permission-locked directory), proxies raw bytes to it once the session's token is validated in constant time, and always reaps the worker on exit — whether it quit cleanly, was explicitly stopped, or crashed — leaving no leftover processes. The printed session URL is now the intended `/s/<token>/` path form, and the terminal page's script/WebSocket references now resolve relative to that URL so a real browser opening it actually works end to end (previously they pointed at the server root and would fail once served under a session prefix). The web server's listen address is also honored precisely now (previously a loopback-only bind could still accept connections from any network interface), `--bind localhost` is accepted consistently instead of crashing, the printed URL never shows an unconnectable "all interfaces" address, and the supervisor's private per-session directory is now cleaned up on exit (and any left behind by a previous crashed run is swept on the next startup) instead of accumulating indefinitely.
- **`miaou serve` sessions now carry two independently-issued tokens with a role bound at creation, and a viewer link is now printed alongside the controller link (Slice 3)**: a session's worker process is spawned lazily on the first request that carries the controller token, instead of eagerly at startup; a second connection attempt with the controller token while a controller is already attached is now transparently offered the read-only viewer role instead of being handed a second controller slot; and a viewer-scoped token can never attach as controller, regardless of which path it requests. A viewer connection's input is now classified at the server, before it could ever reach the app's input pipeline, and any key/resize/mouse frame from a viewer is explicitly rejected and recorded in an audit counter/log line instead of being silently dropped as before — closing a gap where a future refactor could have quietly reintroduced viewer input with nothing to catch it.
- **`miaou serve` now reaps idle sessions and enforces a session cap and per-worker resource limits (Slice 4)**: a session with no controller attached for longer than `--idle-timeout` is now killed (its worker terminated, escalating to a forced kill if it does not exit promptly) and both its tokens are permanently invalidated — a previously-valid session link can never be reused after this happens. Attempting to open more concurrent sessions than `--max-sessions` allows is now rejected with a uniform, bounded response instead of spawning an unbounded number of worker processes; sessions already running are entirely unaffected by another session's rejection. Each worker process can also be launched with a self-applied memory/CPU ceiling via environment variables, as a defense-in-depth backstop against a single session's runaway app.
- **`miaou serve` now validates the WebSocket handshake's `Origin` header and closes the remaining auth-negative gaps (Slice 5)**: a WebSocket upgrade request whose `Origin` doesn't match the server's own address (or an explicitly configured `--allowed-origin`, repeatable, for reverse-proxy setups) is now refused even when it carries an otherwise-valid session link — a request with no `Origin` header at all (typical of non-browser/CLI clients) is still allowed, since `Origin` guards against browser-mediated hijack rather than being the actual credential. A guessed/nonexistent session link, a valid link used with the wrong role, and a link whose session has since been closed now always produce byte-for-byte identical responses (no more information leaks from timing or response-shape differences than before, and this is now asserted by an automated test rather than left implicit). The `--auth-token`/`--auth-file` flags are confirmed and documented as governing only whether a non-loopback bind is allowed at all — the per-session link itself remains the sole thing a client must present on each request.
- **`miaou serve` sessions now survive a dropped connection and can be resumed (Slice 6)**: closing the browser tab, a network drop, or any other disconnect — clean or abrupt — no longer ends the app; the running page and all its state stay alive in the same worker process, and reconnecting to the same session link resumes it with a full-screen repaint reflecting exactly where you left off, rather than starting over. Quitting the app for real still ends the session for good and its link can no longer be reused afterward — and the same applies to any genuine terminal outcome, i.e. navigating back past the last screen or into a page that doesn't exist, not just an explicit quit. A request whose `Origin` header would be refused now never spawns a worker process in the first place (previously it could spawn one that was then never used).
- **Text-first agent protocol (v1) for driving MIAOU apps headlessly**: every JSON-over-stdio response now carries a versioned envelope (`schema_version`), a closed error-code taxonomy (`E_BAD_REQUEST`/`E_UNSUPPORTED_COMMAND`/`E_TIMEOUT`/`E_READ_ONLY`/`E_INTERNAL`), and two new commands — `wait_for` (a single blocking server-side poll for a modal/text/page condition, with a `Workflow`-shaped timeout error) and `assert_screen` (a one-shot text-predicate check). The command dispatcher is now shared, transport-agnostic code reused by both the existing JSON-over-stdio runner and a new MCP server binary (`miaou-mcp`, stdio transport, optional build requiring a pinned MCP server-kit dependency) that exposes the same commands as MCP tools plus `--read-only` enforcement and page-list/protocol-version resources. Every headless/MCP session is now recorded by default (frame + keystroke JSONL, deduplicated, `--no-record`/`MIAOU_NO_RECORD=1` to opt out) instead of requiring explicit debug env vars. A malformed `wait_for`/`assert_screen` regex now returns a normal `E_BAD_REQUEST` response instead of crashing the runner/server process, and any other unanticipated dispatch failure now surfaces as `E_INTERNAL` instead of an uncaught exception. See `docs/agent-protocol.md`.
- Build now guarded against wrong-opam-switch environments via Makefile
  targets and setup docs.
- **CI now runs the real-terminal runtime scenarios on every build**: Ctrl-C/mouse-tracking cleanup and multi-line modal rendering were previously only checkable by hand; a tmux-driven scenario suite (`test/tmux/run_all.sh`) now runs in CI after the test suite, polling for expected output instead of relying on fixed sleeps, so a regression in these interactive paths is caught automatically instead of requiring a human to notice.

### Fixed

- **Grid layout no longer raises on degenerate sizes**: rendering a grid whose padding exceeds the available terminal area (or into a zero-size viewport) used to raise an exception instead of rendering something sensible; the inner content area is now clamped to zero instead of going negative. A negative padding or column-gap value is now also clamped instead of reaching the same crash further down in rendering.
- **Selection widget accessors are now total**: reading the current selection or its display label after the underlying item list shrinks (a stale cursor position) used to raise instead of reporting "no selection"; a new `value_opt` accessor also lets callers distinguish "no selection" unambiguously. A new `set_items` lets callers replace a widget's items in place (e.g. for a live-filtered list) without losing the cursor position.
- **File browser caching no longer cross-contaminates instances**: two file-browser widgets browsing different paths, or the same path with different directory-only filters, could previously see each other's cached listing; the cache is now keyed per path/filter combination. Long, multi-byte filenames are also truncated at a safe character boundary instead of potentially producing corrupted text.
- **Headless test runs stay quiet on stderr by default**: internal driver tracing is now gated behind `MIAOU_DEBUG` instead of always printing.
- **Modal background dimming now respects the caller's choice**: requesting an undimmed modal background was previously silently ignored and the background was always dimmed.
- **Terminal restored after a crashing page**: if a page raised an exception while the terminal (Matrix) driver was running, the terminal could be left in raw/alternate-screen/mouse-tracking mode; cleanup now always runs before the error propagates, and the original error/backtrace is preserved.
- **Signal handling in the terminal driver is safer and more responsive**: the exit-signal handler now only sets a flag and wakes a dedicated fiber (instead of doing terminal I/O directly inside the signal handler), fixing a case where an idle session could be slow to react to Ctrl-C/SIGTERM. A second signal while already shutting down now always attempts a minimal, lock-free terminal restore and force-exits immediately, rather than potentially blocking on the same lock the first signal's normal shutdown path might be stuck on; the conventional exit code for a signal-triggered quit is preserved either way.
- **The alternate (non-Matrix) terminal backend now shares this same safer signal handling**: it previously ran its own, older exit-signal path that could block if a second signal arrived mid-shutdown; it now uses the same flag-and-wake design, with Ctrl-C/SIGTERM reacted to promptly (immediately on the next input-poll tick) and the conventional exit code preserved. A resize while the terminal is narrow now reliably redraws the narrow-terminal warning banner on this backend too — previously a second, independent resize-detection path could silently take over and drop the banner refresh. The one-time "terminal too narrow" warning (banner plus dismissible notice) is now implemented once and shared by both terminal backends instead of two separately-maintained copies.
- **Removed ~800 lines of unused, unreachable rendering/setup code from the alternate terminal backend**: several modules (an old size-detection helper, a renderer, an event reader, and their supporting setup code) were fully superseded by the backend's current implementation and were never wired into it; deleting them is a pure cleanup with no behavior change.
- **Service lifecycle capability no longer risks a crash when only the lower-level interface implementation is registered**: the two representations (this module's and the underlying interface's) previously shared a capability slot via an unsound low-level cast; a lookup now explicitly translates between them, and the accessor functions for starting/stopping/restarting/querying status (previously implemented but not exposed) are now part of the public interface.
- **SDL chart rendering no longer smuggles renderer/font/texture handles through an untyped cast**: the handoff between the SDL backend and chart widgets is now a compile-time-checked capability instead of an unsafe generic-object round-trip; no behavior change for the SDL demo.
- **Terminal and Matrix driver entry points are now documented, narrower public interfaces**: only the `available`/`run` selection API (plus a couple of already-used test/cleanup helpers) is exposed; a handful of unused internal re-exports were removed as dead code.
- Removed a further ~15 confirmed-unused private declarations (values, record fields) across core, widget, and driver modules, surfaced by tightening per-file warning suppression; no behavior change.

## [0.5.2] - 2026-05-05

### Fixed

- **Opam publication metadata**: generated package files no longer include
  development `pin-depends` for `ppx_forbid` or `ppx_enforce`, so the release
  archive can be submitted to opam-repository as normal packages.

## [0.5.1] - 2026-05-05

### Fixed

- **Opam publication metadata**: release metadata no longer requires local pins for `ppx_forbid` or `ppx_enforce`. Miaou now depends on the normal opam packages for those GPL build-time PPX tools, allowing the package set to be submitted cleanly to opam-repository.

## [0.5.0] - 2026-05-05

### Added

- **Runtime version information (`Miaou_core.Version`)**: the OCaml API now exposes the release version as `Version.version` plus `major`, `minor`, and `patch` components. The bundled `miaou-runner-tui` / `miaou-runner-native` CLI parser also accepts `--version`, so installed binaries can report the same version as `dune-project` and the opam packages.
- **Clipboard demo (`example/demos/clipboard/`)**: a gallery entry demonstrating copy-to-clipboard flows with both direct actions and modal confirmation, backed by the shared clipboard capability path and tests.
- **MIAOU Links demo (`example/demos/miaou_links/`)**: a top-down golf game registered in the gallery `Games` group, with an 18-hole classic tour plus a roguelite run mode with stamina, shop perks, persistent coins, and per-run score tracking. It demonstrates framebuffer golf rendering, continuous ball physics over terrain-specific friction, wind/gust effects, pre-shot previews, and persistent demo state via `Arcade_kit.Score_store` (`miaou_links` and `miaou_links_coins`). Existing simpler golf or physics demos can use it as the richer reference for tile-map courses, shot state machines, and Octant-first pixel output (`MIAOU_LINKS_PIXEL_MODE` override). No public library API is removed or changed.
- **MIAOU Crypt demo (`example/demos/miaou_crypt/`)**: a pseudo-3-D dungeon crawler registered in the gallery `Games` group, with seven hand-authored floors, raycast walls, billboarded enemies, boss encounters, pickups, minimap support, and deterministic debug stepping via `MIAOU_CRYPT_DEBUG=1`. It demonstrates how to build a first-person game on top of `Framebuffer_widget`, `Arcade_kit.Particles`, and `Arcade_kit.Score_store` while bounding framebuffer size and raycast work for terminal performance (`MIAOU_CRYPT_PIXEL_MODE` override). Existing raycast or dungeon experiments can use it as the maintained reference implementation. No public library API is removed or changed.
- **Shared `Arcade_kit` (`example/shared/arcade_kit.{ml,mli}`)**: small toolkit used by the gallery's arcade-style demos. `Arcade_kit.Particles` is a pre-allocated ring-buffer particle pool with `spawn` / `spawn_burst` / `tick ~dt ~ax ~ay` / `iter` and zero per-frame allocation in the hot path. `Arcade_kit.Hue` ships seven hand-snapped 12-stop xterm-256 ramps (cyan / magenta / amber / sand / lava / ice / grass) plus matching `(r,g,b)` approximations for pixel-buffer rendering, dodging the smooth-gradient banding that hits Octant render mode. `Arcade_kit.Screen_fx` exposes `flash` and `shake` overlays decaying over a duration. `Arcade_kit.Score_store` reads/writes per-demo high scores under `$XDG_STATE_HOME/miaou/<demo>.score` (best-effort, silent on IO error). `Arcade_kit.Pixel_mode.resolve` returns `Caps.Octant` by default with env-var override — never auto-detects, since auto-Sixel produces fragmented output on Konsole.
- **MIAOU Force demo (`example/demos/miaou_force/`)**: a three-level R-Type-style horizontal shooter registered in the gallery's `Games` group. It demonstrates framebuffer-based arcade rendering, persistent high scores through `Arcade_kit.Score_store`, deterministic turn-based stepping via `MIAOU_FORCE_TURN_BASED=1`, and a dockable Force pod (`d` detach/recall, `f` flip front/back while attached). Existing one-off shooter demos can use this as the richer reference for scroll-driven levels, reusable particle pools, capped entity arrays, and Octant-first pixel output (`MIAOU_FORCE_PIXEL_MODE` override). No public library API is removed or changed.
- **Solar System demo (`example/demos/solar_system/`)**: an animated visual of the Sun and the eight planets at their real orbital and rotational periods (Mercury 88 d / Earth 365.25 d / Neptune 60 190 d for orbits; Earth 1 d / Jupiter 0.41 d / Venus 243 d for axial spin). Distances are square-root-compressed and radii cube-root-compressed so even Mercury stays visible while Jupiter still feels imposing. The Sun has a quadratic radial glow over a white-hot core, every planet is filled with smooth Lambert shading from the Sun's direction (with rim light + a small bright spin marker that orbits the limb to show rotation), Saturn carries a thin ring, orbit rings are dimmed so they don't fight the planets, and a deterministic sparse star field sits behind everything. A right-side panel (toggleable with `Tab`) shows simulated time, the speed multiplier (`1`–`5` set ×1 / ×10 / ×100 / ×1000 / ×10 000 days per real second), each planet's current orbital phase in degrees, and inline help. `Space`/`p` pauses, `o` toggles orbit rings, `l` toggles labels, `r` resets time. The pixel mode is auto-detected (`Sixel` on capable terminals, `Octant` otherwise) and overridable via `MIAOU_SOLAR_PIXEL_MODE`. Registered under the gallery's `Showcases` group.
- **Geo Quiz demo (`example/demos/geo_quiz/`)**: a city-locator showcase game registered in the gallery's `Games` group. The menu mode features a colour-shaded rotating 3-D globe with filled continents and Lambert shading anchored to a fixed-screen sun (Octant 2×4 sub-cell rendering — sand-toned land, navy ocean, paler limb), a five-tier difficulty selector (capitals of large countries → all capitals → cities >1 M → cities >100 K → cities >15 K), and embedded `coastline.bin` (Natural Earth `ne_50m`, 60 K points), `landmask.bin` (rasterised `ne_50m_land` polygons at 720×360, 32 KB) and `cities.bin` (filtered GeoNames cities15000, 33 K cities) blobs. Round mode draws a colour, aspect-corrected equirectangular world map (Octant sub-pixels via `Framebuffer_widget`); the player moves a crosshair with arrow keys, `Shift+arrow` for big jumps, or a mouse click, and presses `Enter` to lock in the guess. A 30 s `Timer.set_timeout` auto-locks a zero-score guess on expiry. Scoring combines a haversine distance score (`max 0 (1000·(1 − d/max_d))`, with `max_d = 5000 km` for tiers 1–3 and `2500 km` for tiers 4–5) and a remaining-time bonus capped at 300, with the round-end map showing both the truth and guess pins; the game-over screen renders a per-round bar chart. Two-tier caching (a per-resolution background-bytes cache plus a final-ANSI string cache keyed on cursor + truth + size) keeps input latency low even on large terminals; map and globe sizes are capped to bound encoding work, and the layout adapts to compact / standard / wide breakpoints.
- **Reusable `Globe_widget` (`Miaou_widgets_display.Globe_widget`)**: standalone rotating-globe widget used by the Geo Quiz menu. Public API: `create ?is_land ~coastline ()`, `advance ~dt`, `set_rotation ~yaw ~pitch`, `yaw`, `render ~cols ~rows`. Renders into an `Octant_canvas`, fills the inscribed disc by inverting the camera-space rotation per cell, looking up a caller-supplied land/sea classifier, and applying separate sand and ocean Lambert ramps to a fixed screen-space sun. Overlays equator and meridian graticule, then projects coastline points with backface culling (z < 0). Also exposes `latlon_to_xyz` and `haversine_km` helpers for callers that need the same sphere math. Self-registers via `Miaou_registry`.
- **Reusable `Prompt` helpers (`Miaou_core.Prompt`)**: thin wrappers over `Modal_manager.confirm_with_extract` exposing `Prompt.confirm`, `Prompt.input`, and `Prompt.select` so application code no longer has to assemble the modal-page boilerplate by hand. Each helper takes an `on_result` callback receiving the user's choice (or `None`/`false` for cancellation) and renders the matching widget centred. Pure result-mapping helpers (`confirm_outcome`, `input_result`, `select_result`) are exposed for unit testing.
- **Gallery demos for `Responsive`, `Select_widget`, inline mode, and inline + responsive composition**: four new entries under `example/demos/` exercising recently-added building blocks. `responsive/` swaps between 4-column / 2×2-grid / stacked layouts as the terminal narrows. `inline_select/` puts a `Select_widget` inline on a page rather than as a centred dialog. `inline_cli/` is a tiny "list current directory" page that, when launched via its `run.sh` (`MIAOU_INLINE_MODE=1 dune exec …`), runs without taking over the alternate screen — its output stays in scrollback after quit. `inline_color_picker/` combines both: a 16-colour swatch grid that adapts to width and runs in inline mode via its own `run.sh`.
- **User keymap overrides (`Miaou_core.Keymap_config`)**: optional line-based config file letting end users rebind page actions without touching application code. Parses entries of the form `page=<name|*>  key=<key>  action=<id>` (with `#` comments and blank lines), folds key spellings (`ctrl+x`, `Ctrl-X`, `c-x` → `C-x`; `shift+tab` → `Shift-Tab`) so configs are case-insensitive, and resolves `page=*` as a global fallback after page-specific rules. Default lookup path is `$MIAOU_KEYMAP_FILE`, then `$XDG_CONFIG_HOME/miaou/keymap.conf`, then `~/.config/miaou/keymap.conf`; a missing file yields an empty keymap silently. The dispatch wiring (consulting overrides before each page's keymap) is intentionally deferred to a follow-up so pages can opt in by exposing named actions.
- **File browser icons + filetype colours**: `File_browser_widget` now prefixes each entry with a Unicode glyph keyed by file extension (📁 for directories, 🐫 for OCaml, 🦀 for Rust, 🐍 for Python, 📦 for archives, 📝 for markdown, etc.) and applies a per-extension 256-colour foreground. Setting `MIAOU_NERD_FONT=1` switches to a Nerd Font glyph set for terminals using a Nerd-patched font. The icon table lives in the new `Miaou_widgets_layout.File_icons` module and is reusable from any custom widget that lists files.
- **`Responsive`**: a tiny utility for picking among layouts based on terminal width. `Responsive.pick` walks an ascending list of `{max_width; layout}` breakpoints and returns the first match (mobile-first ordering). Layouts can be `Flex_layout.t`, `Grid_layout.t`, or anything else — the module is fully polymorphic.
- **Inline mode (`MIAOU_INLINE_MODE=1`)**: a new run mode for the matrix driver in which the TUI does not switch to the alternate screen. The rendered frame stays in the terminal scrollback after exit, making it easy to review what a short-running TUI produced. Mouse tracking is suppressed in this mode (since copy/paste matters more than mouse interaction for inline tools). Programmatic configuration via the new `Matrix_config.inline_mode` field and `Matrix_terminal.set_alt_screen` / `Terminal_raw.set_alt_screen`. *Note: this minimum-viable mode renders starting from the top of the viewport; an anchored partial-row mode (rendering only N rows below the current cursor) is planned as a follow-up.*
- **`Wizard_widget`**: a generic multi-step wizard, polymorphic over user state. Each step provides its own `render`, `validate`, and `on_key`; the wizard owns navigation (Enter advances when validation passes, Shift+Tab returns, Esc cancels), breadcrumb chrome, and finished/cancelled state. Adds `example/demos/wizard/` with a 3-step "pick backend → name it → review" flow.
- **`Textarea_widget` undo / redo**: the multi-line editor now supports `Ctrl+Z` (undo) and `Ctrl+Y` / `Ctrl+Shift+Z` (redo). Consecutive character inserts are coalesced into a single undo step so a typed word is reverted in one go; backspace, delete and newline get individual steps. The undo/redo stacks are capped at 200 entries each. New API: `Textarea_widget.undo`, `redo`, `can_undo`, `can_redo`.
- **`Tree_widget` keyboard navigation**: the tree widget now responds to `Up`/`Down`/`Left`/`Right`/`Enter`/`Home`/`End`, tracks expansion state per path, renders an expand marker (▾/▸ with ASCII fallback) and highlights the cursor row via the theme's selection style. Previously the widget rendered statically. New helpers `Tree_widget.expand_all`, `collapse_all`, `is_expanded`, and `flatten_visible` are exposed.
- **Web Viewer for headless sessions** (`Web_viewer`): standalone HTTP+WebSocket server that runs alongside the headless driver, letting a human observe an AI agent's TUI session in real time via a browser. Serves the existing xterm.js viewer page, broadcasts ANSI frames to all connected viewers, and tracks terminal dimensions so xterm.js resizes to match the headless render size. New viewers receive the current dimensions and last frame on connect (no blank screen).
- **`on_frame` callback in headless runner**: `Headless_json_runner.run` and `Runner_tui.run` accept an optional `?on_frame:(rows:int -> cols:int -> string -> unit)` callback invoked with the raw ANSI frame and terminal dimensions on every frame emit. This enables external consumers (like `Web_viewer`) to observe frames without modifying the headless protocol.
- **Viewer auto-reconnect**: the xterm.js client (`client.js`) now automatically reconnects with a 2-second retry when a viewer WebSocket disconnects, surviving server restarts without requiring a manual browser refresh.
- **Viewer dimension sync**: when the headless driver's terminal size changes, a `{"type":"dimensions","rows":R,"cols":C}` JSON message is sent to all viewers. The client resizes xterm.js to match; FitAddon auto-fit is disabled for viewers so the terminal size is controlled by the server.
- **Octant rendering mode** (`Octant_canvas`): high-resolution chart rendering using Unicode 16 octant block characters (2×4 sub-cell pixels per character cell). Gives 8× resolution compared to ASCII mode with per-cell color support. Octant mode is available on `Sparkline_widget`, `Line_chart_widget`, and `Bar_chart_widget` via a new `~mode:Octant` parameter.
- **Framebuffer widget** (`Framebuffer_widget`): direct pixel/cell-based drawing surface embeddable in any layout slot. Supports both character-cell and sub-cell (Octant) pixel addressing, making it easy to build custom visualisations, games, or image renderers.
- **Terminal capabilities detection** (`Terminal_caps`): detects whether the connected terminal supports Unicode 16 octant characters. Used internally by the Octant rendering mode to fall back gracefully on older terminals.
- **Periodic viewer refresh daemon** (headless runner): when an `on_frame` callback is registered (e.g. by `Web_viewer`), a background Eio daemon fiber re-renders the screen every 200 ms and broadcasts the updated frame. This keeps live viewers up-to-date during agent idle periods (timers, async I/O, spinners) without requiring a key press or tick.
- **"Framebuffer & Octant Charts" demo** added to the gallery, showcasing both the `Framebuffer_widget` and Octant chart modes side-by-side.

### Changed

- **Framebuffer rendering**: Sixel rendering, transparent backgrounds, truecolor handling, adaptive Braille thresholding, and per-cell color averaging improve image/chart fidelity across capable terminals.
- **Sixel performance**: band encoding is now single-pass with an index map and run-length compression, reducing encoder work substantially for large framebuffer scenes.

### Fixed

- **`Input_parser`: recognise PageUp / PageDown / Home / End CSI sequences**: `parse_key` and `peek_key` now handle `ESC[5~`, `ESC[6~`, `ESC[H` / `ESCOH` / `ESC[1~` / `ESC[7~`, and `ESC[F` / `ESCOF` / `ESC[4~` / `ESC[8~` instead of returning `Unknown`; `key_to_string` and `is_nav_key` are updated accordingly. This documents the already-merged #132 navigation-key fix for users relying on paging or home/end movement in widgets.
- **Matrix full redraw invalidation**: forced redraws now invalidate previously-drawn cells so stale characters cannot survive a clear or scrub frame.
- **Matrix wide Unicode rendering**: wide glyphs now reserve and clear their continuation cells, including at the right edge, preventing leftover fragments when content changes.
- **UTF-8 input editing**: text input widgets preserve multibyte characters across insert, delete, cursor movement, and masked rendering paths.
- **Terminal write serialization**: terminal writes are serialized so concurrent render/log paths cannot interleave escape sequences.
- **OSC8 hyperlink sanitization**: generated terminal hyperlinks strip unsafe control characters before emitting OSC8 sequences.
- **OSC52 clipboard fallback**: clipboard support restores the terminal OSC52 fallback when no application clipboard capability is installed.
- **Viewer daemon race condition**: the periodic viewer-refresh fiber previously called `idle_wait` each iteration, which allowed it to interleave with the command handler's own `idle_wait` and concurrently mutate shared page-state (double-ticking clocks/timers). The daemon now reads the cached screen content directly via `HD.Screen.get` without advancing any state.
- **Web driver Tab key**: `ev.preventDefault()` is now called for all recognized keys in the web client's keyboard handler. Previously, Tab (and other browser-reserved keys like F5) were forwarded to the server but also processed by the browser for focus navigation / page reload. Tab now reaches the Miaou application correctly.
- **Headless/Web viewer reliability**: stdin reads now run in a system thread, idle waits yield to the Eio scheduler, LF is converted to CRLF for xterm.js, and new viewers receive dimensions plus the last frame on connect.
- **Framebuffer/widget rendering edge cases**: pixel protocol escape sequences are skipped by themed foreground handling, DCS/APC sequences are skipped by background fill/theme application, and truecolor SGR parsing is preserved when applying themed foregrounds.

## [0.4.2] - 2026-02-26

### Fixed

- **Canvas ANSI row isolation**: `Canvas.to_ansi_with_defaults` now always emits an SGR sequence at column 0 of every row, making each row self-contained. Previously, style was carried across row boundaries as an optimisation; this caused `apply_bg_fill` to bleed the wrong background into the first character of rows where style happened to carry unchanged from the previous row.
- **Canvas widget fills full terminal height**: Miaou Invaders (and any `Canvas_widget` page) no longer shows black bars below the canvas on tall terminals. The 36-row cap on the canvas height has been removed so the game scales to the full terminal height.
- **Matrix driver scrub flicker**: `force_render` is no longer called from the main loop (neither on modal transitions nor during periodic scrub). Both cases now only call `mark_all_dirty`, letting the render domain (the sole terminal writer) pick up the change within one frame. This eliminates the interleaved-write race that caused visible flicker.
- **Miaou Invaders background**: All `draw_text` calls in the Invaders demo now carry an explicit `bg` matching the current game or HUD background. Previously, entities drawn with `bg=-1` clobbered the `fill_rect`-painted background, producing black horizontal bars wherever sprites appeared.
- **Periodic scrub interval**: Default `scrub_interval_frames` reduced from 30 frames (0.5 s at 60 fps) to 300 frames (5 s), making the occasional full-refresh nearly imperceptible.

## [0.4.1] - 2026-02-23

### Fixed

- **Table row selection highlighting**: Full row background now displays correctly when `selection_mode = Row`. Previously, only border characters (vertical separators) showed the selection color due to ANSI reset codes from `themed_border` clearing the selection background. Now, border styling is skipped for selected rows, allowing the full row to inherit the selection background color.

## [0.4.0] - 2026-02-18

### Breaking Changes

- **Box_widget border style**: added `None_` to `Box_widget.border_style` for borderless containers. Pattern matches on `border_style` may need a new case.

### Added

- **Cascading style system** (`miaou_style`): semantic styles + CSS-like selectors with effect-based context (`Style_context`).
- **Theme JSON support** with discovery/merge rules and optional validation for low-contrast fg/bg combinations.
- **Built-in themes** (`Builtin_themes`): 11 popular themes included directly in the library:
  - Dark: catppuccin-mocha, dracula, nord, gruvbox-dark, tokyonight, opencode, oled
  - Light: catppuccin-latte, nord-light, gruvbox-light, tokyonight-day
  - `opencode` and `oled` themes use borderless style for a clean, minimal look
  - `oled` theme features true black background (#000000) with soft pastel colors for OLED screens
- **Theme registry API**: `Builtin_themes.list_builtin()`, `get_builtin(id)`, `is_builtin(id)` for discovering and loading built-in themes.
- **Smart theme loading**: `Theme_loader.load_any(name)` checks built-in themes first, then user themes; `list_all_themes()` returns combined list.
- **Style system demo** (`miaou.style_system-demo`) with runtime theme switching and contextual styling.

### Changed

- **Widget theming**: widgets now use semantic themed styles; containers fill contextual backgrounds across full line width.

### Fixed

- **Theme JSON parsing**: tolerant parsing for partial style objects, multiple color formats, and string border styles.

## [0.3.2] - 2026-02-17

### Added

- **Textarea widget** (`miaou_widgets_input.Textarea_widget`): multiline text input with cursor navigation, line joining, and scroll support. Use Alt+Enter to insert newlines.
- **Left-bordered box** (`Widgets.render_left_border_box`): display helper for context/quote blocks with colored left border and optional background.
- **Blocks spinner style** (`Spinner_widget.Blocks`): animated spinner with size+color gradient progression trail, configurable direction and block count.
- **Alt+Enter key parsing** (`Input_parser.AltEnter`): universally-supported newline insertion key for textarea widgets.
- **Mouse helper module** (`Miaou_helpers.Mouse`): utilities for parsing mouse events (clicks, drags, wheel) in widgets.
- **Mouse support for widgets**: wheel scrolling and click handling added to:
  - Pager: wheel scroll, click to position cursor (in cursor mode)
  - Select: wheel scroll, click to select item
  - File Browser: wheel scroll, click to select entry
  - Textbox: click to position cursor
  - Textarea: wheel scroll, click to position cursor
  - Tabs: click to select tab
  - Breadcrumbs: click on crumb to navigate
  - Button: click to activate
  - Link: click to navigate
  - Checkbox/Radio/Switch: click to toggle

- **Signal handling control**: optional SIGINT handling via `install_signals'` and `Runner_tui.run` `handle_sigint` option.
- **Per-side border colors** for `Box_widget` to style each edge independently.

### Changed

- **Input parser**: added `AltEnter` key variant for Alt+Enter detection (ESC followed by newline).

### Fixed

- **Matrix driver scrub**: avoid screen clear during periodic scrub to reduce flicker.
- **Terminal raw mode**: disable `c_isig` and ignore SIGINT when not handling it.
- **Mouse interactions**: consistent enable sequence via `/dev/tty`, improved click handling, and double-click support.
- **Pager**: add ANSI reset and wrap-aware scrolling.

## [0.3.0] - 2026-02-11

### Breaking Changes

- **Navigation API hardening**: `Navigation.pending` now returns `Navigation.nav option` (`Goto of string | Back | Quit`) instead of `string option`, replacing magic strings (`"__BACK__"`, `"__QUIT__"`).
- **Modal navigation callback API**: `Modal_manager.set_pending_navigation` now takes `Navigation.nav` instead of `string`.
- **Page transition hooks**: page transition handler records now expose an explicit `on_back` callback.
- **Matrix IO internals**: `Matrix_io.t` removes legacy polling/drain fields (`poll`, `drain_nav_keys`, `drain_esc_keys`) in favor of a decoupled event queue reader model.

### Added

- **Clock capability** (`miaou_interfaces.Clock`) exposing `dt`, `now`, and `elapsed` thunks to pages/widgets.
- **Page-scoped timers** (`miaou_interfaces.Timer`) with `set_interval`, `set_timeout`, `clear`, and fired-event draining.
- **Animation module** (`miaou_helpers.Animation`) with easing, repeat modes, sequencing, delay, and lerp helpers.
- **Canvas abstraction** (`miaou-core.canvas`) with drawing primitives, border styles, composition, and ANSI rendering.
- **Canvas layers**: `Canvas.compose` and `Canvas.compose_new` for ordered transparent/opaque overlay compositing.
- **Canvas widget** (`miaou_widgets_layout.Canvas_widget`) for embeddable mutable drawing surfaces in layout slots.
- **Runner CLI snapshot mode**: `--cli-output` (plus `--cols`, `--rows`, `--ticks`) for non-interactive stdout rendering.
- **Color documentation**: new `docs/colors.md` plus widget interface docs clarifying ANSI payload formats and precedence rules.

### Changed

- **Matrix driver input architecture**: dedicated Eio reader fiber + mutexed queue; tick loop drains full event batches.
- **Default matrix tick rate** increased to **60 TPS**.
- **Matrix artifact scrubbing** is now configurable via `MIAOU_MATRIX_SCRUB_FRAMES` (set `0` to disable).
- **Example gallery** now includes the renamed **Miaou Invaders** demo, with richer gameplay systems and modularized demo code.

### Fixed

- **ESC parsing robustness**: avoid out-of-bounds exceptions on unknown ESC-prefixed pairs while preserving Escape semantics.
- **Demo overlay/collision consistency** in Miaou Invaders: gameplay coordinate handling stays aligned with canvas size and reserved HUD rows.

## [0.2.7] - 2026-02-07

### Fixed

- **Esc key repeat quitting app after modal close** — Matrix driver now applies a 200ms cooldown after closing a modal with Esc, suppressing spurious Esc events from terminal key repeat that would otherwise reach the page and trigger app exit
- **Footer hints not rendering in Matrix driver** — `key_hints` from pages are now correctly rendered in the footer bar

## [0.2.6] - 2026-02-06

### Added

- **Unified key handling architecture** with `Key_event.result` type:
  - New `on_key` / `on_modal_key` methods return `Handled | Bubble` for composable key dispatch
  - `key_hints` for display-only footer hints (replaces action-bearing `keymap`)
  - All input widgets (`Button`, `Checkbox`, `Radio`, `Switch`, `Textbox`, `Select`, `ValidatedTextbox`) expose `on_key`
  - `Keys.of_string` now accepts aliases: `"S-Tab"`, `"BackTab"` → `ShiftTab`; `"Esc"` → `Escape`

### Fixed

- **Keymap dispatch bypassing `handle_key`** — Drivers now always route keys through `on_key`, fixing Focus_ring Tab navigation when Tab was in page keymap
- **Lambda-term driver Enter key** — Enter now goes through `on_key` like other keys

### Changed

- **BREAKING**: `PAGE_SIG` now requires `on_key`, `on_modal_key`, and `key_hints` methods
- `Demo_page.MakeSimple` functor for demos without explicit `key_hints`
- Legacy `handle_key`, `handle_modal_key`, `keymap` deprecated but still functional

## [0.2.5] - 2026-02-05

### Added

- **Focus Ring widget** (`Miaou_internals.Focus_ring`) for named-slot focus hierarchy:
  - Type-safe focus management with string-keyed slots
  - Automatic wrap-around navigation (next/prev)
  - `handle_key` returns `Handled | `Bubble` for composable key dispatch
  - Ideal for forms, toolbars, and multi-widget layouts

- **Focus Container widget** (`Miaou_internals.Focus_container`) for GADT-based focus management:
  - Type-safe heterogeneous widget containers using extensible GADTs
  - No `Obj.magic` - full type safety with witness pattern
  - Nested container support for complex UI hierarchies
  - Generic focus traversal across different widget types

- **Box Widget** (`Miaou_widgets_layout.Box_widget`) for border-decorated containers:
  - Five border styles: `Single`, `Double`, `Rounded`, `Heavy`, `Ascii`
  - Optional colored borders with 256-color support
  - Configurable padding (top, bottom, left, right)
  - Nested box support for complex layouts
  - Automatic ASCII fallback via `MIAOU_TUI_UNICODE_BORDERS=false`

- **Direct_page** (`Miaou.Core.Direct_page`) for simplified page development:
  - Only 3 required functions vs 13 in PAGE_SIG: `init`, `view`, `on_key`
  - Navigation via OCaml 5 effects: `Direct_page.navigate`, `go_back`, `quit`
  - `With_defaults` functor provides sensible defaults for optional functions
  - Reduces boilerplate significantly for simple pages

- **Grid Layout** (`Miaou_widgets_layout.Grid_layout`) for CSS-grid-like layouts:
  - Row and column track definitions with `Fr`, `Px`, `Auto` sizing
  - `grid_area` placement for precise cell positioning
  - Gap support (row_gap, column_gap)
  - Span support for multi-cell items
  - Automatic content fitting

### Fixed

- **Flex layout column alignment** - Short/empty lines in row layouts now properly padded to allocated width, preventing subsequent columns from bleeding into earlier column areas

## [0.2.0] - 2026-02-05

### Added

- **Web driver** (`miaou-driver-web`) for browser-based terminal rendering:
  - xterm.js terminal emulation over WebSocket
  - Controller/viewer architecture for shared sessions
  - Password authentication support
  - 60 FPS configurable refresh rate

- **Path-based roles for web driver** with explicit URL routing:
  - `/ws` — controller WebSocket (returns 409 if slot already taken)
  - `/ws/viewer` — viewer WebSocket (returns 409 if no controller connected)
  - `/viewer` — dedicated viewer HTML page
  - Separate `controller_password` and `viewer_password` authentication
- **Composable `MiaouTerminal(container, options)` JS factory** replacing the IIFE in `client.js`:
  - `wsPath` option (`/ws` or `/ws/viewer`)
  - `onRole`, `onStatusChange`, `onAuthRequired` callbacks
  - `sessionStorage` keys scoped by `wsPath`
  - Returns `{ term, fitAddon, reconnect(pw), getRole() }`
- **Custom HTML pages and extra assets** for the web driver:
  - `~controller_html` and `~viewer_html` optional parameters on `Web_driver.run`
  - `extra_asset` type for serving additional static files (e.g. logos)
  - Both parameters forwarded through `Runner_web.run`
- **Branded gallery pages** with Miaou logo header and role badges:
  - `MIAOU_WEB_VIEWER_PASSWORD` environment variable (falls back to `MIAOU_WEB_PASSWORD`)

### Changed

- Web driver routing refactored: `/ws` always creates controller, `/ws/viewer` always creates viewer (previously role was assigned by connection order on single `/ws` endpoint)

## [0.1.4] - 2026-01-22

### Fixed

- **Modal title rendering** with multiline text
  - Modal titles containing newlines no longer corrupt the layout
  - First line is displayed in the colored title bar with blue background
  - Additional lines are prepended to the modal content body
  - Fixes misaligned borders and improper blue background spanning

## [0.1.3] - 2026-01-16

### Added

- **`enable_mouse` parameter** for `Runner_tui.run` to programmatically control mouse tracking
  ```ocaml
  (* Disable mouse tracking from code *)
  Runner_tui.run ~enable_mouse:false my_page
  ```

### Changed

- Version bump to 0.1.3

## [0.1.2] - 2026-01-16

### Added

- **Optional mouse tracking** via environment variable `MIAOU_ENABLE_MOUSE`
  - Set `MIAOU_ENABLE_MOUSE=0` or `MIAOU_ENABLE_MOUSE=no` to disable mouse tracking
  - Allows traditional terminal copy/paste when mouse tracking interferes
  - See [`docs/MOUSE_CONTROL.md`](./docs/MOUSE_CONTROL.md) for details
- **`Matrix_config.with_mouse_disabled`** helper for programmatic mouse control

### Changed

- Version bump to 0.1.2

## [0.1.1] - 2026-01-16

### Fixed

- **Matrix driver race condition** in dirty flag handling that caused intermittent render artifacts
  - `clear_dirty` was called outside the buffer lock, allowing new UI writes to be skipped
  - Now cleared atomically inside `compute_atomic` while holding the lock
- **Lambda-term `split_lines_preserve`** incorrectly added an extra empty element
  - `String.split_on_char` already handles trailing delimiters correctly

### Changed

- File browser fixes for edit mode (Space key handling, selection highlight)
- Version bump to 0.1.1

## [Unreleased]

### API

- Rename `Vsection.render` parameter `~footer` to `~content_footer` to clarify it is for page content, not driver-generated keymap footers.
- Clarify `PAGE_SIG` docs: keymap footers are auto-generated by drivers, `?` is reserved but may appear in keymaps for display, and `handled_keys` is only for conflict detection.
- Add `display_only` flag to keymap bindings so reserved keys (e.g., `?`) can be shown in footers/help without being dispatched; drivers and the key handler stack respect this.
- Add `File_browser_modal` helper plus `File_browser_widget.key_hints` to avoid re-wrapping the widget for modals and to surface consistent key hints.

### Breaking Changes (2026-01-08)

#### ⚠️ PAGE_SIG Navigation API Rewrite

**Impact:** All page implementations must be updated. This is a significant API change.

**What changed:**

The `next_page` field and `enter` function have been removed from `PAGE_SIG`. Instead, pages now use the `Navigation` module for all navigation, and all handlers work with `pstate` (which wraps state in `Navigation.t`).

**Old API (removed):**
```ocaml
module type PAGE_SIG = sig
  type state
  type msg

  val init : unit -> state
  val next_page : state -> string option  (* REMOVED *)
  val enter : state -> state               (* REMOVED *)

  val update : state -> msg -> state
  val view : state -> focus:bool -> size:LTerm_geom.size -> string
  val move : state -> int -> state
  val refresh : state -> state
  val service_select : state -> int -> state
  val service_cycle : state -> int -> state
  val back : state -> state
  val keymap : state -> (string * (state -> state) * string) list
  val handled_keys : unit -> Keys.t list
  val handle_modal_key : state -> string -> size:LTerm_geom.size -> state
  val handle_key : state -> string -> size:LTerm_geom.size -> state
  val has_modal : state -> bool
end
```

**New API:**
```ocaml
module type PAGE_SIG = sig
  type state  (* Your page's own state - no next_page field needed *)
  type msg
  type pstate = state Navigation.t  (* Wrapped state with navigation *)

  val init : unit -> pstate
  val update : pstate -> msg -> pstate
  val view : pstate -> focus:bool -> size:LTerm_geom.size -> string
  val move : pstate -> int -> pstate
  val refresh : pstate -> pstate
  val service_select : pstate -> int -> pstate
  val service_cycle : pstate -> int -> pstate
  val back : pstate -> pstate
  val keymap : pstate -> (string * (pstate -> pstate) * string) list
  val handled_keys : unit -> Keys.t list
  val handle_modal_key : pstate -> string -> size:LTerm_geom.size -> pstate
  val handle_key : pstate -> string -> size:LTerm_geom.size -> pstate
  val has_modal : pstate -> bool
end
```

**Migration guide:**

1. **Remove `next_page` from your state type:**
```ocaml
(* Before *)
type state = {
  items : string list;
  cursor : int;
  next_page : string option;  (* REMOVE THIS *)
}

(* After *)
type state = {
  items : string list;
  cursor : int;
}
```

2. **Add the `pstate` type alias:**
```ocaml
type pstate = state Navigation.t
```

3. **Update `init` to wrap state:**
```ocaml
(* Before *)
let init () = { items = []; cursor = 0; next_page = None }

(* After *)
let init () = Navigation.make { items = []; cursor = 0 }
```

4. **Remove `next_page` and `enter` functions** (they no longer exist).

5. **Update all handlers to use `pstate` and Navigation functions:**
```ocaml
(* Before *)
let handle_key s key ~size =
  match key with
  | "q" -> { s with next_page = Some "__QUIT__" }
  | "Esc" -> { s with next_page = Some "__BACK__" }
  | "Enter" -> { s with next_page = Some "details" }
  | "j" -> { s with cursor = s.cursor + 1 }
  | _ -> s

(* After *)
let handle_key ps key ~size =
  match key with
  | "q" -> Navigation.quit ps
  | "Esc" -> Navigation.back ps
  | "Enter" -> Navigation.goto "details" ps
  | "j" -> Navigation.update (fun s -> { s with cursor = s.cursor + 1 }) ps
  | _ -> ps
```

6. **Update state transformations to use `Navigation.update`:**
```ocaml
(* Before *)
let refresh s = { s with items = load_items () }

(* After *)
let refresh ps = Navigation.update (fun s -> { s with items = load_items () }) ps
```

7. **Update `view` to access inner state:**
```ocaml
(* Before *)
let view s ~focus ~size = render_items s.items s.cursor

(* After *)
let view ps ~focus ~size =
  let s = ps.s in  (* Access inner state via .s field *)
  render_items s.items s.cursor
```

**Navigation module reference:**
- `Navigation.make : 'a -> 'a t` - Wrap state with no pending navigation
- `Navigation.goto : string -> 'a t -> 'a t` - Navigate to a named page
- `Navigation.back : 'a t -> 'a t` - Go back (equivalent to `goto "__BACK__"`)
- `Navigation.quit : 'a t -> 'a t` - Quit application (equivalent to `goto "__QUIT__"`)
- `Navigation.update : ('a -> 'a) -> 'a t -> 'a t` - Modify inner state
- `Navigation.pending : 'a t -> string option` - Check pending navigation (used by framework)

**Compiler errors you'll see:**
```
Error: This expression has type state but an expression was expected of type
         state Navigation.t

Error: Unbound value next_page

Error: Unbound value enter
```

**Why this change?**
- Eliminates the error-prone `next_page` field that LLM agents frequently forgot to propagate
- Clear, named navigation functions instead of magic strings in a field
- Pure functional style with no hidden side effects
- Framework handles navigation automatically - pages just call `Navigation.goto`

### Added (2026-01-08)

#### Modal Navigation Helpers

Modal `on_close` callbacks can now request navigation without using refs or checking state in `service_cycle`:

```ocaml
(* Before - error-prone pattern requiring manual ref and service_cycle check *)
let nav_ref = ref None in
Modal_manager.push
  (module My_modal)
  ~init:(My_modal.init ())
  ~ui:{ title = "Choose"; ... }
  ~commit_on:["Enter"]
  ~cancel_on:["Esc"]
  ~on_close:(fun state outcome ->
    match outcome with
    | `Commit -> nav_ref := Some "next_page"
    | `Cancel -> ()) ;

(* Then in service_cycle: *)
let service_cycle ps _ =
  match !nav_ref with
  | Some page ->
      nav_ref := None ;
      Navigation.goto page ps
  | None -> ps

(* After - direct API call *)
Modal_manager.push
  (module My_modal)
  ~init:(My_modal.init ())
  ~ui:{ title = "Choose"; ... }
  ~commit_on:["Enter"]
  ~cancel_on:["Esc"]
  ~on_close:(fun _state outcome ->
    match outcome with
    | `Commit -> Modal_manager.set_pending_navigation "next_page"
    | `Cancel -> ())

(* No service_cycle code needed - framework handles it automatically *)
```

New functions:
- `Modal_manager.set_pending_navigation : string -> unit` - Request navigation from modal callback
- `Modal_manager.take_pending_navigation : unit -> string option` - Used by framework

#### Auto-Refresh Before Service Cycle

Drivers now automatically call `Page.refresh` before `Page.service_cycle`. This means:

- Pages no longer need to manually call `refresh` in `service_cycle`
- Consistent behavior across all drivers (Matrix, Lambda-term, SDL)
- The pattern `Page.service_cycle (Page.refresh ps) 0` is now handled by the framework

```ocaml
(* Before - manual refresh in service_cycle *)
let service_cycle ps _ =
  let ps = refresh ps in  (* Manual refresh call *)
  (* ... check refs, etc. *)
  ps

(* After - just handle service logic *)
let service_cycle ps _ =
  (* refresh is already called by the driver *)
  ps
```

#### Pager Widget Enhancements

- **Wrap toggle**: Press **`w`** to toggle word wrap on/off in the pager
- **Line truncation**: Long lines are truncated with visual indicator when wrap is off
- Default behavior changed to wrap=on for better readability

#### Narrow Terminal Warning

Both Matrix and Lambda-term drivers now show consistent narrow terminal warnings:

- **Warning banner** displayed when terminal width < 80 columns
- **One-time modal** appears on first detection (auto-dismisses after 5 seconds)
- **Any key dismisses** the modal immediately
- Warning only shown once per session (not repeatedly on resize)

### Changed (2026-01-08)

#### Driver Architecture Improvements

- **Periodic partial refresh**: Matrix driver performs full buffer refresh every ~2 seconds to catch rendering artifacts
- **Region-based dirty marking**: More efficient partial updates in Matrix driver
- **Terminal cleanup reliability**: Improved cleanup on exit to restore terminal state
- **Screen content preservation**: Exit screen content saved for debugging

#### Shared Driver Modules

Common functionality extracted into shared modules:
- `terminal_raw.ml` - Raw terminal mode handling
- `input_parser.ml` - ANSI escape sequence parsing

This reduces code duplication between Matrix and Lambda-term drivers.

### Fixed (2026-01-08)

- Modal close no longer causes double-navigation with Esc key
- Matrix driver now drains pending Esc keys after modal close
- Fiber scheduling improved in Matrix driver (uses `Eio.Time.sleep`)
- File pager uses proper Eio-based fiber scheduling

### Added (2026-01-05)

#### High-Performance Matrix Terminal Driver

- **`miaou-driver-matrix`** package with diff-based cell rendering
- **Two-domain architecture** using OCaml 5 Domains for true parallelism:
  - Render Domain: 60 FPS, handles diff computation and terminal output
  - Main Domain: 30 TPS, handles input and state updates
- **Cell-based double buffering** with O(1) pointer swap
- **Diff-based rendering**: only changed cells are written to terminal (no flicker)
- **Thread-safe buffer** with mutex synchronization and atomic dirty flag
- Pure ANSI output (no lambda-term dependency)
- Matrix is now the **default driver** (priority: Matrix > SDL > Lambda-term)
- Configuration via environment variables:
  - `MIAOU_DRIVER=matrix` (default) or `term` or `sdl`
  - `MIAOU_MATRIX_FPS=60` - Render domain frame rate cap
  - `MIAOU_MATRIX_TPS=30` - Main domain tick rate

#### Debug Overlay for Performance Monitoring

- **`MIAOU_OVERLAY=1`** environment variable enables real-time performance metrics
- Displays in top-right corner with dim styling:
  - **L** (Loop FPS): Render loop iteration rate (the cap)
  - **R** (Render FPS): Actual frames rendered per second
  - **T** (TPS): Ticks per second (main loop rate)
- Available in both Matrix and Lambda-term drivers
- Useful for diagnosing performance issues and verifying frame rates

### Added (2025-12-19)

#### Debounced Validation for Validated Textbox Widget

- **`debounce_ms` parameter** for `Validated_textbox_widget.create` (default: 250ms)
- Validation now defers during rapid typing, running after the debounce period elapses
- Text input remains immediate for responsive UX
- New functions:
  - `tick` - Check and run pending validation (call in `service_cycle`)
  - `flush_validation` - Force immediate validation (useful before form submission)
  - `has_pending_validation` - Check if validation is pending
- Set `debounce_ms=0` to disable debouncing (legacy immediate behavior)

#### Global Render Notification System

- **`Miaou_helpers.Render_notify`** module for widgets to request async UI updates
- `request_render()` - Request a re-render from any widget
- `should_render()` - Check if a render was requested (called by driver)
- Used by validated textbox to trigger validation after debounce period

#### Generic Debounce Module

- **`Miaou_helpers.Debounce`** module for generic debounce timing
- Thread-safe implementation using `Atomic` operations
- Functions: `create`, `mark`, `is_ready`, `clear`, `has_pending`, `check_and_clear`
- Configurable debounce period in milliseconds (default: 250ms)

#### File Browser Performance Optimization

- **Caching for directory listings** - `list_entries_with_parent` now caches results
- **Caching for writable status** - `is_writable` checks are cached per-directory
- Cache automatically invalidates when navigating to a different directory
- Cache manually invalidated after directory creation (`mkdir_and_cd`, inline mkdir)
- New `invalidate_cache()` function for manual cache clearing
- Significantly reduces filesystem calls during rapid Up/Down navigation
- **Note**: Cache is shared globally across all file browser instances

#### File Browser Hidden Files Toggle

- Press **`h`** to toggle visibility of hidden files/directories (starting with `.`)
- New `show_hidden` parameter in `open_centered` (default: `false`)
- Tab completion always includes hidden files for convenience (allows completing `.config/` etc.)
- Header hint updates dynamically to show current state

#### Textbox Input Draining for Typing Responsiveness

- **`Miaou_helpers.Input_drain`** module for draining buffered input characters
- Textbox widgets now process all pending printable characters at once
- Prevents typing lag when entering text quickly
- Driver registers drain function, widgets call `drain_pending_chars()`

### Added (2025-12-17)

- Modal sizing supports dynamic width specs (`Fixed`, `Ratio`, `Clamped`) resolved at render time, including fallback terminal size detection via `/dev/tty` so modals resize with the terminal even when `System` is mocked.

### Changed (2025-12-17)

#### Opam package restructuring for optional SDL

Restructured opam packages to allow terminal-only builds without SDL2 dependency:

- **`miaou-core`**: Standalone core package with all widgets, no SDL dependencies
- **`miaou-driver-term`**: Terminal driver, depends only on `miaou-core`
- **`miaou-driver-sdl`**: SDL driver with SDL2 dependencies (`tsdl`, `tsdl-ttf`, `tsdl-image`)
- **`miaou-widgets-display-sdl`**: SDL-specific widget implementations
- **`miaou-runner`**: Runner with `miaou-driver-sdl` as optional dependency
- **`miaou-tui`**: Meta-package for terminal-only installs (no SDL)
- **`miaou`**: Meta-package for full install (includes SDL)
- **`miaou-core.lib`**: The convenience `Miaou` module (re-exporting Core, Widgets, etc.) is now part of `miaou-core`, available to terminal-only users

Terminal-only users can now: `opam install miaou-tui`

### Breaking Changes (2025-12-17)

- Library public names changed to use package prefixes:
  - `miaou.lib` → `miaou-core.lib`
  - `miaou.core` → `miaou-core.core`
  - `miaou.widgets.display` → `miaou-core.widgets.display`
  - `miaou.driver.term` → `miaou-driver-term.driver`
  - `miaou.driver.sdl` → `miaou-driver-sdl.driver`
  - And similar for other libraries
- `Miaou_widgets_display.Sparkline_widget_sdl` moved to `Miaou_widgets_display_sdl.Sparkline_widget_sdl` (and similar for other SDL widgets)
- `Modal_manager.ui.max_width` (and related helpers) now expects `max_width_spec option` instead of `int option`; wrap existing fixed widths with `Fixed n` or switch to ratio/clamped specs.

### Changed (2025-12-15)

- File pager tail fibers are now scoped to per-page switches and auto-cancel on navigation; terminal, SDL, and headless drivers wrap pages in `Fiber_runtime.with_page_switch` for structured cleanup; `Fiber_runtime` exposes page switch helpers. Adds regression coverage for pager cleanup.
- Pager UX fixes: follow hint only shown when streaming, static pager test added, markdown renderer hides inline backticks and underlines H1 titles.
- Service lifecycle: removing instance files no longer requires a role value.
- File browser navigation: canonicalize paths so parent navigation works from relative paths, scroll the viewport earlier, and tighten Enter navigation checks; demo uses the real filesystem so Enter now changes directories.
- Modal sizing: modal pages now receive the actual modal content geometry (rows/cols) so list widgets don’t scroll into invisible items due to modal height clipping.

### Added (2025-12-11)

#### Input Buffer Draining for Navigation Keys
- **Navigation key coalescing** to prevent scroll lag in list widgets
- When arrow keys are held down and released, consecutive identical navigation events are automatically drained from the input buffer
- Only the final navigation event is processed, making the UI feel more responsive
- Debug logging available with `MIAOU_DEBUG=1` to track drain operations
- Fixes issue where selection continues scrolling for ~0.5s after releasing arrow keys

#### Braille Rendering Mode
- **Unicode Braille patterns** for high-resolution chart rendering (2×4 dots per character cell)
- Braille mode support for `Line_chart_widget`, `Bar_chart_widget`, and `Sparkline_widget`
- `Braille_canvas` module for efficient braille dot manipulation
- 8x higher resolution compared to ASCII mode with only 2x performance cost
- Colored braille output with ANSI styling support
- Performance: 9,259 renders/second for line charts in braille mode

#### Global Keys API
- **Type-safe keyboard handling system** with variant-based key definitions
- Extended `Keys.t` with new key types: `PageUp`, `PageDown`, `Home`, `End`, `Escape`, `Delete`, `Function of int`
- Global key reservations for application-wide actions: `Settings`, `Help`, `Menu`, `Quit`
- Registry validation to prevent key conflicts at page registration time
- `Registry.check_all_conflicts()` for detecting inter-page key conflicts
- `Registry.conflict_report()` for human-readable conflict summaries
- Helper functions: `Keys.is_global_key`, `Keys.get_global_action`, `Keys.show_global_keys`

### Changed (2025-12-10)

#### Performance Optimizations
- **Significant performance improvements** across all widgets (8-24x faster in some cases)
- Replaced `String.concat` with buffer-based rendering throughout codebase
- Introduced `Helpers.pad_to_width` eliminating O(n²) padding allocations
- Optimized pager widget: 9.1s → 1.2s (8x faster)
- Optimized layout widget: 9.0s → 0.8s (12x faster)
- Optimized card_sidebar: 15.1s → 1.0s (15x faster)
- All other widgets show 20-40% performance improvements

### Breaking Changes (2025-12-12)

#### ⚠️ Runtime Migrated from Lwt to Eio

**Impact:** Applications must initialize the Eio runtime before using Miaou.

**What changed:**
- All async/concurrency now uses Eio instead of Lwt
- `cohttp-lwt-unix` replaced with `cohttp-eio`
- Terminal driver uses `Eio_unix.await_readable` for input polling
- Background tasks use `Eio.Fiber` instead of `Thread.create`

**Migration guide:**

1. Wrap your main function in `Eio_main.run` and initialize the runtime:
```ocaml
(* Before *)
let () =
  let page = ... in
  Miaou_runner_tui.Runner_tui.run page

(* After *)
let () =
  Eio_main.run @@ fun env ->
  Eio.Switch.run @@ fun sw ->
  Miaou_helpers.Fiber_runtime.init ~env ~sw;
  let page = ... in
  Miaou_runner_tui.Runner_tui.run page
```

2. Update opam dependencies:
```
- lwt
- cohttp-lwt-unix
+ eio
+ eio_main
+ cohttp-eio
```

**New modules:**
- `Miaou_helpers.Fiber_runtime` — shared Eio runtime management
- `Miaou_widgets_display.File_pager` — Eio-based file tailing pager

#### ⚠️ Pager Widget: Notification Callback Now Per-Instance

**Impact:** Code using `Pager_widget.set_notify_render` must be updated.

**What changed:**
```ocaml
(* OLD - Global callback (removed) *)
Pager_widget.set_notify_render (Some callback);
let pager = Pager_widget.open_lines ~title:"Log" lines in

(* NEW - Per-instance callback *)
let pager = Pager_widget.open_lines ~title:"Log" ~notify_render:callback lines in
```

**Migration guide:**

1. Remove calls to `set_notify_render`
2. Pass `~notify_render` parameter to `open_lines`/`open_text`

**Before:**
```ocaml
let pager = Pager_widget.open_lines ~title:"My Pager" [] in
Pager_widget.set_notify_render (Some render_callback);
```

**After:**
```ocaml
let pager = Pager_widget.open_lines ~title:"My Pager"
              ~notify_render:render_callback [] in
```

**Why this change?**
- Eliminates global mutable state
- Enables multiple independent pagers with different callbacks
- Makes callback lifetime explicit (tied to pager instance)
- Better composability and testability

**Type signature changes:**
- `open_lines : ?title:string -> ?notify_render:(unit -> unit) -> string list -> t`
- `open_text : ?title:string -> ?notify_render:(unit -> unit) -> string -> t`
- `set_notify_render` function removed

**Compiler error you'll see:**
```
Error: Unbound value Pager_widget.set_notify_render
```

### Breaking Changes (2025-12-11)

#### ⚠️ PAGE_SIG Requires `handled_keys` Function

**Impact:** All page implementations must be updated.

**What changed:**
```ocaml
module type PAGE_SIG = sig
  (* ... existing fields ... *)
  
  (* NEW - REQUIRED *)
  val handled_keys : unit -> Keys.t list
end
```

**Migration guide:**

For **minimal migration**, add this to every page:
```ocaml
let handled_keys () = []
```

For **proper key declaration** (recommended):
```ocaml
let handled_keys () = [
  Keys.Char "a";      (* Declare all keys your page handles *)
  Keys.Enter;
  Keys.Up;
  Keys.Down;
  (* ... *)
]
```

**Why this change?**
- Enables compile-time key conflict detection
- Self-documents key bindings
- Foundation for auto-generated help system
- Enables future page registry and navigation features

**Compiler error you'll see:**
```
Error: Signature mismatch:
       The value `handled_keys' is required but not provided
       File "src/miaou_core/tui_page.mli", line 38, characters 2-40:
         Expected declaration
```

**Benefits:**
- ✅ Type-safe key handling (variants, not strings)
- ✅ Prevents global key conflicts automatically
- ✅ Runtime validation catches inter-page conflicts
- ✅ Clear error messages when conflicts occur

## [Previous Releases]

<!-- Previous changelog entries would go here -->
