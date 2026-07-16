# `miaou serve` — network deployment guide

`miaou serve` exposes a MIAOU app over HTTP/WebSocket (rendered client-side
with xterm.js). This document covers the two things an operator needs
before exposing it beyond `localhost`: the bind-policy the CLI enforces
(FR-003/FR-060), and how to put TLS in front of it (FR-060/FR-061).

## 1. TLS is not built in — put a reverse proxy in front (v1 default)

`miaou serve`'s own listener speaks **plaintext** HTTP/WebSocket only.
There is no in-process TLS in v1: **native in-process TLS is an explicit
non-goal for v1** (FR-061, deferred) — maintaining an in-tree TLS stack
(e.g. `ocaml-tls`) is not worth the cost for a first release when a
reverse proxy already solves the problem well, and every flagship
consumer (mdcat, octez-manager) already expects to run behind one.

**v1's default and only documented deployment path (FR-060)** is:

1. Bind `miaou serve` itself to `127.0.0.1` (loopback) or another
   interface not reachable from the public internet.
2. Put a TLS-terminating reverse proxy (nginx or Caddy) in front of it,
   listening on the public interface, forwarding to the loopback bind.
3. Never pass `--insecure-allow-plaintext-external` in this topology —
   it exists only for the operator who has *chosen*, with eyes open, to
   expose `miaou serve`'s plaintext listener directly (see §3).

This "loopback-bind-behind-proxy" topology is the recommended default
for every deployment, not just an option: it keeps TLS termination,
certificate rotation, and HTTP hardening (rate limiting, request size
caps, etc.) in a proxy that's already built for it, and it keeps
`miaou serve` itself simple — a single trust boundary the fail-closed
bind policy below is built around.

### nginx

```nginx
server {
    listen 443 ssl;
    server_name serve.example.com;

    ssl_certificate     /etc/letsencrypt/live/serve.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/serve.example.com/privkey.pem;

    # REDACT the session token from access logs (FR-030's session id is
    # the `/s/<token>/` path segment — nginx's default log format records
    # the full request URI, which would otherwise leak the live
    # capability token into plaintext log files). Replace the default
    # combined format with one that truncates the path after `/s/`.
    log_format serve_redacted
        '$remote_addr - $remote_user [$time_local] '
        '"$request_method $uri_redacted HTTP/$http_protocol" '
        '$status $body_bytes_sent "$http_referer" "$http_user_agent"';

    # $uri_redacted: everything up to and including "/s/", then a fixed
    # placeholder instead of the real token.
    set $uri_redacted $uri;
    if ($uri ~ ^(/s/)[^/]+(.*)$) {
        set $uri_redacted "$1<redacted>$2";
    }
    access_log /var/log/nginx/miaou-serve.access.log serve_redacted;

    location / {
        proxy_pass http://127.0.0.1:8080;

        # Forward Host/Origin unmodified so the supervisor's Origin
        # allow-list (FR-045, --allowed-origin) can validate the
        # WebSocket upgrade against the *public* origin, not the proxy's
        # internal one — pass --allowed-origin https://serve.example.com
        # to `miaou serve` when the public origin differs from --bind.
        proxy_set_header Host $host;
        proxy_set_header Origin $http_origin;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # WebSocket upgrade: nginx does not proxy the Upgrade/Connection
        # headers by default — both MUST be forwarded explicitly, or
        # every WS connection falls back to (and fails as) plain HTTP.
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";

        # A live TUI session is long-lived; don't let the proxy time out
        # an idle-but-connected WebSocket before miaou serve's own
        # --idle-timeout (FR-013) does.
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }
}
```

### Caddy

Caddy proxies WebSocket upgrades and forwards `Host`/`Origin` by default
(no special-casing needed, unlike nginx), which keeps the Caddyfile much
shorter — but the access-log redaction still needs an explicit filter,
since Caddy's default `access_log` also records the full request URI.

```caddyfile
serve.example.com {
    reverse_proxy 127.0.0.1:8080 {
        # Forward Host/Origin unmodified (Caddy's default already does
        # this) so the supervisor's Origin allow-list (FR-045) sees the
        # real public origin — pass
        # --allowed-origin https://serve.example.com to `miaou serve`
        # when it differs from --bind.
        header_up Host {host}
        header_up Origin {header.Origin}
        header_up X-Real-IP {remote_host}
        # header_up Upgrade/Connection are forwarded automatically by
        # reverse_proxy for a detected WebSocket upgrade request —
        # no extra directive is required here (unlike nginx).
    }

    # REDACT the session token (the `/s/<token>/` path segment, FR-030)
    # from access logs: replace the raw request field with one that
    # stops right after the literal "/s/" segment.
    log {
        output file /var/log/caddy/miaou-serve.access.log
        format filter {
            wrap json
            fields {
                request>uri query {
                    delete
                }
                request>uri path replace ^(/s/)[^/]+(.*)$ ${1}<redacted>${2}
            }
        }
    }
}
```

Both snippets terminate TLS at the proxy, keep `miaou serve` bound to
loopback behind it, forward `Host`/`Origin` so `--allowed-origin` can be
validated against the public origin, proxy the WebSocket upgrade
correctly, and strip the live session token out of the access log —
covering every row FR-060's threat-table entry calls for (see
`briefs/miaou-serve-spec.md` §5, "Plaintext traffic ... sniffed on the
wire" and "Session-id-in-URL-path ... leaks into server access logs").

## 2. The fail-closed bind policy (FR-003/FR-060)

If `miaou serve` is asked to bind a non-loopback address (i.e. not
`127.0.0.1`/`::1`/`localhost` — the topology in §1 never needs this),
it refuses by default unless an auth mechanism or the explicit override
below is present:

| `--bind` | `--auth-token`/`--auth-file` | `--insecure-allow-plaintext-external` | Result |
|---|---|---|---|
| loopback | either | either | **allowed** (always trusted) |
| non-loopback | absent | absent | **refused** — fails closed, `Bind_refused` before any socket opens |
| non-loopback | present | absent | allowed |
| non-loopback | absent | present | allowed, with a loud warning (below) |

`--auth-token`/`--auth-file` are bind-policy gates only — they satisfy
"an auth mechanism is configured" for this table, not per-request
credentials. The actual per-request authentication is the CSPRNG session
token embedded in each session's `/s/<token>/` URL (FR-030-FR-033); see
`docs/serve-architecture.md` §4 for the full reconciliation of the two.

### `--insecure-allow-plaintext-external`

This flag exists for an operator who has decided, knowingly, to expose
`miaou serve`'s plaintext listener directly — without a TLS-terminating
proxy in front of it — and accepts the wire-sniffing risk that implies.
Every single invocation with the flag set prints a warning to stderr
before the listener opens:

```
[miaou serve] WARNING: --insecure-allow-plaintext-external set; binding
0.0.0.0 without a reverse proxy. See docs/serve.md.
```

This warning is **never persisted** anywhere (no config file, no
suppressible "seen once" state) — it is re-emitted on every process
start for as long as the flag is passed, precisely so the operator can
never silently forget the risk they accepted.

## 3. Non-goal: native in-process TLS (FR-061)

`miaou serve` will not gain a built-in TLS listener in v1. The
reverse-proxy path in §1 is the only supported way to put TLS in front
of it. This is revisited only if operator feedback from the flagship
consumers (mdcat, octez-manager) shows the reverse-proxy requirement is
a real adoption blocker — not a default assumption for this release.
