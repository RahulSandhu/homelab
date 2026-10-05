# Homelab design — Zipline (the first PUBLIC service)

- **Date:** 2026-09-28
- **Status:** Implemented 2026-09-28 (see "As built")
- **Repo:** `~/desktop/projects/homelab`
- **Depends on:** the 2026-09-28 specs

## Context

Everything in the homelab so far is **tailnet-only**. The owner wants to send files
to people **who are not on the tailnet** — a link, nothing more. This is the first
deliberately **public** service, so the design is built around *containing* that
exposure.

The model wanted:

- **uploads: only the owner** — no anonymous uploads, no public signup;
- **downloads: only through links the owner hands out** — nothing browsable;
- links **expire**, can be **password-protected**, and can be limited to N
  downloads (including **one**).

## Goals

- Upload a file → get a short link that anyone can open.
- Public reachability for **that link only** — no home IP, no other service.
- Storage bounded and separate.

## Non-goals

- Guest/anonymous uploads. **Registration stays OFF** (invites only).
- A browsable public gallery.
- Being a backup or archive (links are meant to expire). **Never** mix this with
  `/srv/backup`.

## Decision: Zipline (`ghcr.io/diced/zipline:4.8.0`)

A ShareX-style upload server: per-file **expiry**, **max-view limits**, password
protection, folders, tags, URL shortening, and an API for ShareX/scripts. Needs
**PostgreSQL 16** and a CPU with **AVX** (Ryzen 5300U / Zen 2 qualifies).
Sibling projects (Pingvin Share, Send) were considered; Zipline won on maturity,
API and per-file controls.

## Decision: its own tailnet node (Tailscale sidecar)

Zipline is a Next.js app that expects a URL **root**, and the `serve` ports are
exhausted (443 Caddy, 8443 AdGuard, 10000 Stirling). So a **Tailscale sidecar**
gives it its own node:

```
zipline + postgres ──┐
                     ├── tailscale sidecar (node "zipline", 100.78.80.41)
        funnel ──────┘        └──► https://zipline.tail91459b.ts.net
```

**Why this is the safest possible scoping:** the public `funnel` applies to *that
node only*. The dashboard, Navidrome, AdGuard, Filebrowser and Vaultwarden live on
`docker-host` (a different node) and are all still `(tailnet only)` — verified.

## Decision: a dedicated 50 GB disk

Uploads **and** the database live on `/srv/zipline` (a dedicated thin disk), never on
the VM's root disk — so uploads can never fill the system and take the rest down.

## Components

| Component | Image (pinned) | Notes |
| --- | --- | --- |
| Zipline | `ghcr.io/diced/zipline:4.8.0` | shares the sidecar's netns; uploads in `/srv/zipline` |
| PostgreSQL | `postgres:16` | internal network only; `pgdata` on `/srv/zipline` |
| Tailscale | `tailscale/tailscale:v1.102.4` | node `zipline`; the only funneled node |

Secrets (`CORE_SECRET`, `POSTGRESQL_PASSWORD`, `TS_AUTHKEY`) live in a git-ignored
`.env`.

## Security posture

- **Registration OFF**, **anonymous uploads OFF**, **no public gallery**; upload
  size limits and default expiry are enforced as **environment variables** in
  `compose.yaml` (not dashboard toggles — see the stack README).
- The tailnet policy allows `funnel` for **`100.78.80.41`** only (`nodeAttrs`), so
  no other node can ever be published.
- Public exposure is a **single command**, reversible with
  `tailscale funnel --https=443 off`.
- No IP forwarding, no ports opened on the router; the home IP stays hidden.

## Risks

| Risk | Mitigation |
| --- | --- |
| A public app with an auth surface | registration off; strong admin password; prompt updates |
| Uploads filling the disk | dedicated 50 GB disk; quotas; expiry; manual delete |
| The wrong node getting exposed | the ACL targets one IP; verified `docker-host` is tailnet-only |
| Auth key leak | git-ignored `.env`; revoke in the console |

## Phases

| Phase | What | Owner |
| --- | --- | --- |
| 1 | 50 GB disk → `/srv/zipline`; write the stack | agent |
| 2 | Tailscale auth key | owner |
| 3 | Deploy tailnet-only; verify the scoping | agent |
| 4 | First-run setup (super-admin) | owner |
| 5 | `nodeAttrs` funnel permission; enable the funnel; verify | owner + agent |
| 6 | Dashboard tile, docs, diagram, commit | agent |

## As built

- 50 GB thin disk → `/dev/sdd` → ext4 label `zipline` → **`/srv/zipline`** (fstab by
  UUID). Uploads, `public`, `themes` and `pgdata` all live there.
- Three containers: `zipline` (4.8.0), `zipline-db` (postgres:16, healthy) and
  `zipline-ts` (tailscale v1.102.4) which joined as its **own node**:
  `zipline → 100.78.80.41`.
- Zipline binds `0.0.0.0:3000` **inside the sidecar's netns**; the tailnet reaches it
  at `http://zipline.tail91459b.ts.net:3000`.
- **Funnel enabled for that node only** —
  `tailscale funnel --bg --https=443 http://127.0.0.1:3000` →
  `https://zipline.tail91459b.ts.net` (verified `{"pass":true}` on
  `/api/healthcheck`).
- **Scoping verified server-side:** `docker-host`'s three HTTPS mappings all read
  `(tailnet only)` and its funnel status shows **no** funnel. The tailnet policy's
  `nodeAttrs` targets `100.78.80.41` alone.
- **Read-only links:** the first sanitisation pass reported the dashboard as
  reachable, but that fetcher shares the laptop's tailnet connection — an invalid
  vantage point. The authoritative check is the server-side `serve/funnel status`
  above (and a phone with Tailscale off).