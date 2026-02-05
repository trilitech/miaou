# Miaou Web Driver

Web backend for Miaou TUI applications. Serves an xterm.js-based terminal
over HTTP/WebSocket so the TUI can run in a browser.

## Architecture

- **Controller**: The first WebSocket connection on `/ws` becomes the controller.
  It receives keyboard/mouse input and drives the TUI main loop.
- **Viewers**: Connections on `/ws/viewer` are read-only viewers that receive
  the same ANSI frames as the controller in real time.

When the controller disconnects, all viewer connections are closed and the
controller slot becomes available again.

## URL Scheme

| Path | Purpose |
|------|---------|
| `/` | Controller HTML page |
| `/viewer` | Viewer HTML page |
| `/client.js` | Composable JS factory |
| `/ws?password=...` | Controller WebSocket |
| `/ws/viewer?password=...` | Viewer WebSocket |
| `/*` | Extra assets (e.g. `/logo.png`) |

### HTTP status codes

- `/ws` when controller slot is already taken: **409 Conflict**
- `/ws/viewer` when no controller is connected yet: **409 Conflict**
- Wrong or missing password: **403 Forbidden**

## Authentication

Password-based authentication can be configured via the `?auth` parameter
on `Web_driver.run`. Passwords gate the WebSocket upgrade only -- the HTML
page and JavaScript are served without authentication.

```ocaml
type auth = {
  controller_password : string option;  (* None = no auth required *)
  viewer_password : string option;      (* None = no auth required *)
}
```

- `controller_password` gates `/ws`
- `viewer_password` gates `/ws/viewer`

The browser client handles this automatically: it first attempts to connect
without a password. If the server rejects the connection, a password form
overlay is shown. The entered password is saved in `sessionStorage` (scoped
by WebSocket path) for reconnects within the same browser tab.

### Example: separate passwords

```ocaml
let auth = {
  controller_password = Some "ctrl_secret";
  viewer_password = Some "view_secret";
} in
Web_driver.run ~auth page
```

### Example: environment variables (gallery demo)

```sh
MIAOU_WEB_PASSWORD=ctrl MIAOU_WEB_VIEWER_PASSWORD=view \
  MIAOU_DRIVER=web ./_build/default/example/gallery/main_web.exe
```

If `MIAOU_WEB_VIEWER_PASSWORD` is not set, it falls back to `MIAOU_WEB_PASSWORD`.

## Composable Client

`client.js` exports a `MiaouTerminal(container, options)` factory:

```javascript
var mt = MiaouTerminal(document.getElementById('terminal'), {
  wsPath: '/ws',              // or '/ws/viewer'
  password: null,             // pre-set password (optional)
  onRole: function(role) {},  // called when role is assigned
  onStatusChange: function(cls, msg) {},  // status bar updates
  onAuthRequired: function(hadPassword, retryCb) {}  // password prompt
});
// Returns: { term, fitAddon, reconnect(pw), getRole() }
```

## Custom Pages and Extra Assets

Override the default HTML pages or serve additional static assets:

```ocaml
type extra_asset = {
  path : string;         (* e.g. "/logo.png" *)
  content_type : string; (* e.g. "image/png" *)
  body : string;         (* raw file content *)
}

Web_driver.run
  ~controller_html:my_html
  ~viewer_html:my_viewer_html
  ~extra_assets:[{path = "/logo.png"; content_type = "image/png"; body = logo}]
  page
```

## Wiring

The web driver is selected via `Runner_web.run` (or automatically via
`MIAOU_DRIVER=web`). The runner accepts the same optional parameters and
forwards them to `Web_driver.run`.

```ocaml
Runner_web.run ~port:8080 ~auth ~controller_html ~viewer_html ~extra_assets page
```
