# Homelab design — Caddy + Homepage + PairDrop (Scheme B)

- **Date:** 2026-09-28
- **Status:** Implemented 2026-09-28 (see "As built")
- **Repo:** `~/desktop/projects/homelab`
- **Depends on:** the 2026-09-27 and 2026-09-28 specs

## Context

Services were each exposed on their own tailnet node's port 443 — which only works
once per node. Adding a third web service (`PairDrop`) forced a decision about how
to expose many services from one node. This spec introduces a reverse proxy
(**Caddy**) plus a dashboard (**Homepage**) and **PairDrop**, and moves the VM's
web services onto **paths**.

## Goals

- Many web services on one tailnet node, with clean, memorable URLs.
- A landing page listing every service.
- Add **PairDrop** for device-to-device file sharing.
- Keep Vaultwarden and its clients untouched.

## Decision: Scheme B

Caddy on `docker-host` reverse-proxies by **path**. **Vaultwarden stays on its own
tailnet name** (`pve.tail91459b.ts.net`) because Vaultwarden does **not** support
being served under a subpath (upstream issue #528; community reports of blank
pages/404s). Scheme B = paths for the apps that support it; Vaultwarden keeps its
own name. (Alternative "one tailnet node per service" was considered and rejected
as disproportionate for now.)

## Architecture

```
https://docker-host.tail91459b.ts.net
  │
  tailscale serve :443         (TLS, one hostname)
  ▼
  Caddy 127.0.0.1:8090
    ├─ /pairdrop  → pairdrop:3000   (handle_path — prefix stripped)
    ├─ /navidrome → navidrome:4533  (ND_BASEURL=/navidrome — path kept)
    └─ /          → homepage:3000   (dashboard)

Vaultwarden: unchanged → https://pve.tail91459b.ts.net
```

## Components

| Component | Image (pinned) | Notes |
| --- | --- | --- |
| Caddy | `caddy:2.11.4-alpine` | `stacks/caddy/`; listens `:8080` in-container, published `127.0.0.1:8090`; `auto_https off` (Tailscale does TLS) |
| Homepage | `ghcr.io/gethomepage/homepage:v2.4.0` | `stacks/homepage/`; needs `HOMEPAGE_ALLOWED_HOSTS`; config in `config/` |
| PairDrop | `ghcr.io/schlagmichdoch/pairdrop:v1.11.2` | `stacks/pairdrop/`; port `3000`; `PUID/PGID=1000` |

All three join an **external Docker network `proxy`**; Navidrome joins it too.
Caddy and the services **publish no host ports** (except Caddy on localhost) — so
**there are no LAN doors**: the tailnet is the only way in. This supersedes the
earlier "services reachable on the LAN" behaviour.

## Migration phases

0. Snapshot VM 100 (`qm snapshot 100 pre-caddy`).
1. Create the `proxy` network; attach Navidrome.
2. Deploy Caddy; prove it reaches Navidrome. No cutover yet.
3. Deploy Homepage + dashboard config.
4. Deploy PairDrop; add its route.
5. Navidrome: `ND_BASEURL=/navidrome`; add its route.
6. Cut over `tailscale serve` → Caddy. Verify all paths.
7. **Owner:** re-point the Navidrome app (Yuzic) and saved links to `…/navidrome`.
8. Docs + diagram.

## Risks

| Risk | Mitigation |
| --- | --- |
| Caddy becomes a chokepoint | tiny/stable; snapshot before change; fast to revert `tailscale serve` |
| Navidrome URL change breaks clients | owner re-points the app (phase 7); brief, expected |
| PairDrop PWA `start_url` quirk (iOS "add to home screen") | cosmetic; Android unaffected |
| Homepage needs `HOMEPAGE_ALLOWED_HOSTS` | set explicitly |

## Success criteria

- `https://docker-host.tail91459b.ts.net/` shows the dashboard.
- `/navidrome` serves Navidrome (app works after re-pointing).
- `/pairdrop` works between two devices.
- Vaultwarden unchanged at `https://pve.tail91459b.ts.net`.
- No LAN doors; no router ports opened.

## As built (deviations & discoveries)

- **PairDrop needs a trailing slash.** Its assets are **relative** (`styles/…`),
  so visiting `/pairdrop` made the browser resolve them at `/` (→ Homepage) and
  the page rendered **unstyled**. Fixed with a Caddy redirect
  (`/pairdrop` → `/pairdrop/`) and the dashboard tile now links to `/pairdrop/`.
- **Homepage host validation.** `HOMEPAGE_ALLOWED_HOSTS` must list the hostname,
  or Homepage answers **400**. It includes the tailnet name.
- **Vaultwarden's LAN door remains.** `pve` proxies to Vaultwarden over the LAN,
  so its host port stays reachable on the flat LAN. "No LAN doors" applies to the
  Caddy-managed services only.
- **Navidrome LAN door closed** (`4533` → `127.0.0.1:4533`).
