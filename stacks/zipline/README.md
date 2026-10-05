# Zipline — file sharing (a PUBLIC service)

Upload a file → get a short link you can send to anyone. Recipients need **no
account**. This is one of the **two public services** (the other is Filebrowser
share links); the rest of the homelab stays tailnet-only.

Model:

| Action | Who |
| --- | --- |
| **Upload** | **only the owner** (uploading needs a logged-in account; registration is OFF) |
| **Download** | anyone **with the link you hand out** — nothing is browsable |

Links can expire, be password-protected, and be limited to N downloads (set it to
**1** for a true one-time link). Zipline deletes expired/over-viewed files.

## Where things live

| | |
| --- | --- |
| Node | its **own** Tailscale node `zipline`, via the `zipline-ts` sidecar |
| URL | `https://zipline.tail91459b.ts.net` (tailnet first; public via funnel) |
| Uploads / DB / themes | **`/srv/zipline`** — a dedicated 50 GB disk (never the root disk) |
| Secrets | `.env` (git-ignored) — `CORE_SECRET`, `POSTGRESQL_PASSWORD`, `TS_AUTHKEY` |

## Deploy

```sh
# on the VM
sudo mkdir -p /opt/zipline
# (scp this stack across, then)
cd /opt/zipline
cp .env.example .env
# fill in CORE_SECRET + POSTGRESQL_PASSWORD:
#   openssl rand -base64 42 | tr -dc A-Za-z0-9 | cut -c -32
# and the Tailscale auth key (TS_AUTHKEY)
sudo mkdir -p ts-state
sudo docker compose up -d
```

First run serves a **setup page** — create the super-admin there (pick `admin`).

> **Access it over HTTPS**, i.e. `https://zipline.tail91459b.ts.net`. The stack sets
> `CORE_TRUST_PROXY` + `CORE_RETURN_HTTPS_URLS` (TLS terminates at Tailscale's funnel
> edge, so the app must be told it's behind a proxy): links come out as `https://`
> and cookies are marked `Secure`. Plain-HTTP access via `…:3000` will therefore
> break login — use the HTTPS URL.

## Going public (and only this)

The exposure is **one command, scoped to this node alone**:

```sh
docker exec zipline-ts tailscale funnel --bg --https=443 http://127.0.0.1:3000
docker exec zipline-ts tailscale funnel status     # verify
```

> **Never** funnel the other node (`docker-host`) — that would publish the
> dashboard, Navidrome, AdGuard, Filebrowser and Vaultwarden.

Turn it back off at any time:

```sh
docker exec zipline-ts tailscale funnel --https=443 off
```

**Verify from outside the tailnet** (e.g. phone on mobile data, Tailscale off):
the Zipline URL must work, and `docker-host.tail91459b.ts.net` must **not**.

## Hardening (set in `compose.yaml`, not the UI)

These are enforced as **environment variables**, which take precedence over the
dashboard — so they're managed in the repo and can't be toggled away by accident:

| Setting | Value | Why |
| --- | --- | --- |
| `FEATURES_USER_REGISTRATION` | `false` | **no signups** — only the owner can ever upload |
| `FEATURES_OAUTH_REGISTRATION` | `false` | same, via OAuth |
| `FEATURES_DELETE_ON_MAX_VIEWS` | `true` | makes **one-time links** possible |
| `FILES_DEFAULT_EXPIRATION` | `30d` | links expire by default |
| `FILES_MAX_FILE_SIZE` | `1gb` | upload ceiling |
| `FILES_MAX_FILES_PER_UPLOAD` | `10` | |
| `FILES_ASSUME_MIMETYPES` | `true` | classify by real content, not the browser's claim |
| `FILES_DISABLED_TYPES` / `..._DEFAULT` | `text/html,application/javascript` → `application/octet-stream` | uploaded HTML/JS is **served as a download**, never rendered on our domain |
| `RATELIMIT_ENABLED/MAX/WINDOW` | `true` / `10` / `60` | rate-limit the upload + shorten APIs |
| `CORE_TRUST_PROXY` + `CORE_TRUSTED_PROXIES` | `true` / `127.0.0.1,::1` | trust the funnel's `X-Forwarded-*` (protocol + client IP) |
| `CORE_RETURN_HTTPS_URLS` | `true` | emit `https://` links and mark cookies **Secure** |

Cookies are `Secure` (see the note under *Deploy*), so **use the HTTPS URL**
(`https://zipline.tail91459b.ts.net`) — plain-HTTP access over `…:3000` breaks login.

## Operate

```sh
docker compose ps
docker compose logs -f
docker compose restart
```

## Notes

- The `zipline` node keeps the tailnet's **node key expiry** (tags are off) —
  **disable key expiry** for it in the admin console, or it will drop off after
  ~180 days.
- The auth key lives in `.env`; revoke it in the console if it ever leaks.
- `CORE_SECRET` changing logs everyone out.
