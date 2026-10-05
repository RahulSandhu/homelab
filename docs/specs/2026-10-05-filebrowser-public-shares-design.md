# Homelab design — Public read-only Filebrowser share links

- **Date:** 2026-10-05
- **Status:** **Implemented 2026-10-05** (see "As built").
- **Repo:** `~/desktop/projects/homelab`
- **Depends on:** `2026-09-28-homelab-backup-destination-design.md` (which
  **parked** off-tailnet sharing as a non-goal), and `2026-09-28-zipline-design.md`
  (the "own tailnet node + scoped funnel" pattern this reuses).
- **Owner decision record:** this design deliberately **amends the "only Zipline
  is public" rule** to allow a *second* public node (`fileshare`). It keeps
  **"never funnel `docker-host`"** intact.

## Context

The backup/park decision said, verbatim:

> **Sharing links with people off the tailnet.** Parked by the owner; it would
> require public exposure and a deliberate change to the "never public" rule.

The owner now wants exactly that: hand an off-tailnet person a **read-only** link
to a folder that lives in `/srv/backup`, so the recipient can browse and download
it in Filebrowser — **without** exposing Filebrowser's login, its admin/API
surface, or the rest of the backup. Filebrowser Quantum already has a share
feature (your config carries a `share:` permission), so the app-side primitive
exists; the missing piece is *controlled public reachability*.

## Goals

- An off-tailnet recipient can open a link and **browse/download a shared folder**
  in Filebrowser, read-only.
- Public reachability is scoped to **share-link routes only** — the login page,
  the admin API and every other route are **not** reachable publicly.
- **No duplicate copy** of data (share the live folder in place).
- **Reversible** exposure: one command turns the public door off.
- The existing internal Filebrowser experience is unchanged.

## Non-goals

- Anonymous uploads, or any write path (the mount stays `ro`).
- Public browsing of the whole `/srv/backup` tree.
- Replacing or duplicating Zipline (which remains the upload/send tool).
- Versioned backup (the mirror remains a mirror).

## Decisions

### 1. Approach A — a route-filtering gate in front of the *existing* instance

Add one small stack containing a **Tailscale sidecar** (its own node,
`fileshare`) plus a **Caddy "gate"** that forwards only share-related routes to
the existing `filebrowser:80` and `404`s everything else. Benefits over a second
Filebrowser instance: same database, no second index, and shares are created in
the UI you already use.

Rejected: a dedicated second Filebrowser instance on the public node (more
isolation, but doubles the app/index and splits share management). Zipline was
rejected as it cannot present a browsable folder tree.

### 2. Source is a live subfolder of `/srv/backup`

The owner accepted the consequence: the recipient sees whatever `rclone` last
wrote, and **deletions/renames propagate** to the shared folder at the next sync
(00:00 / 08:00 / 16:00). No copy is made.

### 3. Its own node — never `docker-host`

The public door is a **new node** (`fileshare`), so the existing hard rule
*"never funnel `docker-host`"* is preserved; only the new node is funneled.

## Architecture

```
off-tailnet recipient
        │  https://fileshare.tail91459b.ts.net/files/public/share/<hash>
        ▼
 Tailscale Funnel  (node: fileshare — the second funneled node)
        ▼
 share-gate  (Caddy, allowlist-only, :8080)
        │  allowed routes only; everything else → 404
        ▼
 filebrowser:80  (existing instance, `proxy` network, unchanged)
        ▼
 /srv/backup  (bind-mounted READ-ONLY)
```

The internal path `https://docker-host.tail91459b.ts.net/files/` is untouched and
stays tailnet-only.

## Proposed stack — `stacks/filebrowser-share/`

| Component | Image (pinned) | Notes |
| --- | --- | --- |
| `fileshare-ts` | `tailscale/tailscale:v1.102.4` | Sidecar → own node `fileshare.tail91459b.ts.net`; `NET_ADMIN` + `/dev/net/tun`; state in `./ts-state`; auth key from a **git-ignored** `.env`; **joins the external `proxy` network** so the gate can resolve `filebrowser` by name |
| `share-gate` | `caddy:2.11.4-alpine` | `network_mode: "service:fileshare-ts"`; listens `:8080`; config `stacks/filebrowser-share/Caddyfile` |

Exposure is one reversible command (mirrors Zipline):

```sh
docker exec fileshare-ts tailscale funnel --bg --https=443 http://127.0.0.1:8080  # on
docker exec fileshare-ts tailscale funnel --https=443 off                        # off
```

### The gate (enforces "share links only")

```caddyfile
:8080 {
    @share path /files/public/*
    handle @share {
        reverse_proxy filebrowser:80
    }
    handle {
        respond 404
    }
}
```

> **Route set — VERIFIED against the running 1.5.6 instance (2026-10-05).** The
> SPA defines the anonymous surface under `/files/public/`:
> `public/share/<hash>` (page), `public/static/*` (assets) and
> `public/api/*` (the `Jr()` wrapper: `share/info`, `share/pinnedItems`, `users`,
> `resources`, `resources/{bulk,download,pause,preview}`,
> `media/{lyrics,metadata,subtitles}`, `office/config`). The authenticated surface
> is `/files/api/*` (returns `401`) and `/files/login`. So the matcher is simply
> **`/files/public/*`** — everything under the app's own public prefix, nothing
> else. Runtime-confirmed: `public/share/*` and `public/static/*` → `200`;
> `/files/login`, `/files/api/*`, `/files/` and `..` / `%2e%2e` traversal → `404`.

## Proposed change to the existing Filebrowser stack

In `stacks/filebrowser/config/config.yaml`, set `share: true` under
`userDefaults.account.permissions` (the real key path — **not** `permissions`).
Everything else is unchanged: `modify`/`create`/`delete` stay `false`, `download`
stays `true`, `baseURL` stays `/files`, and the mount stays `ro`. Read-only is
thus enforced twice (permissions + `ro` mount).

> **CONFIRMED (2026-10-05): `userDefaults` does NOT propagate to an existing
> user.** After the config change and a restart, the stored `admin` record still
> read `"admin":true,…,"share":false` (the DB is **BoltDB**, despite the
> "SQLite" log line). The config change keeps a **fresh** database reproducible
> (a new `-a` admin inherits `share: true`); for the **existing** admin, the owner
> must tick **Share** once in Settings → Users (or the API does it with the admin
> password).

> **Version note (confirmed 2026-10-05):** the pinned **Quantum `1.5.6-stable`**
> share dialog already exposes the controls we need — duration (expiry),
> password, downloads limit, disable-anonymous and per-user download limits.

## Link lifecycle

- **Create:** in the normal Filebrowser UI, share the chosen folder (the account
  needs the **Share** permission; 1.5.6 provides a password and a title).
- **Hand out:** swap the host to `fileshare.tail91459b.ts.net` — e.g.
  `https://fileshare.tail91459b.ts.net/files/public/share/<hash>` — because the
  link is generated against the origin it was created from.
- **Revoke:** delete the share in the UI.
- **Protection:** a share link is a **bearer secret** — anyone holding the URL can
  read that folder. Password/expiry mitigate; availability is version-dependent.

## Policy & documentation changes (applied 2026-10-05)

- **Tailnet policy `nodeAttrs`:** `funnel` granted to the `fileshare` node's IP
  (`100.123.26.36`) alongside Zipline's (`100.78.80.41`), so **two** nodes may funnel.
- **`AGENTS.md` — hard rule amended** to name both funneled nodes (Zipline and
  `fileshare`) while keeping **never funnel `docker-host`**.
- `docs/setup.md` — service section added.
- `docs/access-matrix.md` — public-services section updated.
- `docs/schemas/homelab.dot` — `fileshare` node + funnel edge added.

## Security posture

- Public surface is **only** the allowlisted share routes; login/admin are not
  public.
- Read-only enforced by the `ro` bind mount **and** Filebrowser permissions.
- The home IP stays hidden (Funnel; no router ports, no IP forwarding).
- Exposure is one command and reversible; the node's funnel permission is scoped
  to its IP in the tailnet policy.
- Keep Filebrowser patched; the public node is the one to watch.
- **Accepted residual risk:** the gate shares the external `proxy` network with
  the other `docker-host` services (needed so it can resolve `filebrowser`). The
  upstream is hardcoded to `filebrowser:80`, so the gate cannot proxy elsewhere,
  but a compromise of the sidecar/gate container shares that network. A dedicated
  network is possible future hardening.

## Risks and open questions

| Risk / unknown | Mitigation / next step |
| --- | --- |
| Share route set may be broader than assumed | **Resolved 2026-10-05** — the allowlist is `/files/public/*` (see above). |
| 1.5.6 share options may be limited | **Resolved** — the dialog exposes duration (expiry), password, downloads limit, disable-anonymous and per-user download limits |
| Existing `admin` user lacks `share` | `userDefaults` does not reach existing users — owner ticks **Share** once in the UI (or the API with the admin password) |
| Bearer link leaks to unintended people | Use password/expiry where supported; revoke by deleting the share |
| Shared folder mutates (rclone deletes propagate) | Accepted by the owner; share a stable subfolder, not volatile paths |
| Large downloads are slow through Funnel | Funnel bandwidth limits; warn recipients |
| Second public node widens the trust boundary | IP-scoped `nodeAttrs`; `ro` mount; gate allowlist; update hard rules |
| Public node reachable if policy misconfigured | Verify from a device with Tailscale **off** (a tailnet device proves nothing) |

## Implementation phases (executed)

| Phase | What | Owner |
| --- | --- | --- |
| 1 | Verify the share route set from a running share (browser network log) | agent |
| 2 | Confirm 1.5.6 share options + how to grant `share` | agent |
| 3 | `stacks/filebrowser-share/` (sidecar + gate + Caddyfile) — deploy tailnet-only first | agent |
| 4 | Enable `share`; create a test share; verify the gate tailnet-side | agent |
| 5 | Tailscale auth key for `fileshare`; join the tailnet | **owner** |
| 6 | `nodeAttrs` funnel grant; enable funnel; verify from a non-tailnet device | **owner + agent** |
| 7 | Docs, `AGENTS.md` rule amendment, diagram, access matrix | agent |
| 8 | Commit (deferred until the owner approves) | agent / **owner** |

## Rollback

```sh
docker exec fileshare-ts tailscale funnel --https=443 off   # close the public door
cd /opt/filebrowser-share && sudo docker compose down        # remove the node's stack
```

Reverting the `share:` config change and deleting any created shares restores the
prior state. No data is copied or moved, so rollback has no data implications.

## Documentation changes applied (2026-10-05)

1. `AGENTS.md` — hard rule amended to two funneled nodes.
2. `docs/setup.md` — service section added.
3. `docs/access-matrix.md` — public-services section updated.
4. `docs/schemas/homelab.dot` — `fileshare` node + funnel edge.
5. `README.md` / `stacks/filebrowser/README.md` — sharing noted.

## As built

- **Node:** `fileshare` = **`100.123.26.36`**, own Tailscale sidecar
  (`stacks/filebrowser-share/`), state in git-ignored `ts-state/`. Key expiry
  disabled; tailnet policy `nodeAttrs` grants `funnel` to this IP and Zipline's.
- **Gate:** Caddy `share-gate` (same netns as the sidecar) allows only
  `/files/public/*` and `404`s everything else. The public surface was discovered
  from the 1.5.6 SPA bundle: page `public/share/<hash>`, assets `public/static/*`,
  API `public/api/*` (the `Jr()` wrapper). The authenticated `/files/api/*` (401)
  and `/files/login` are *not* exposed.
- **Config:** `share: true` under `userDefaults.account.permissions`. **Gotcha
  confirmed:** `userDefaults` does **not** reach the existing `admin` — the DB
  (BoltDB, not SQLite despite the log line) kept `"share":false` until the owner
  ticked **Share** in the UI. The config change therefore only helps a *fresh* DB.
- **Tailnet vs public:** a bare sidecar listens on nothing until `tailscale serve`
  is configured; `serve --https=443` gives the tailnet-only HTTPS URL, then
  `funnel --https=443` publishes it. Funnel propagation lagged ~1 min (a few
  external nodes saw `Broken pipe` before consistently `200`).
- **Verified externally** (check-host.net + r.jina.ai, off-tailnet):
  `public/share/*` → `200`; `/files/login` and `/files/api/*` → `404`;
  `docker-host.tail91459b.ts.net` → **NXDOMAIN** (still private); Zipline unaffected.
- **End-to-end:** a password-protected single-file test share
  (`/files/public/share/<hash>`) listed and downloaded through the
  gate (`200`, file content returned). **Delete the test share.**
- Image tags unchanged (`tailscale/tailscale:v1.102.4`, `caddy:2.11.4-alpine`).
