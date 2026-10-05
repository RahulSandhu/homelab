# Filebrowser share links — read-only PUBLIC folder links

Give someone **off the tailnet** a read-only link to a folder in `/srv/backup`,
served by the **existing** Filebrowser instance through a share-only gate. No data
is copied: the folder is served in place, read-only.

Model:

| Action | Who |
| --- | --- |
| **Create a share** | **only the owner** (Filebrowser login, over the tailnet) |
| **Browse / download** | anyone **with the link you hand out** — read-only |

## Where things live

| | |
| --- | --- |
| Node | its **own** Tailscale node `fileshare`, via the `fileshare-ts` sidecar |
| URL | `https://fileshare.tail91459b.ts.net/files/public/share/<hash>` |
| Gate | `share-gate` (Caddy) — allows **only** `/files/public/*`, `404` otherwise |
| Upstream | the existing `filebrowser:80`, over the external `proxy` network |
| Secret | `.env` (git-ignored) — `TS_AUTHKEY` |

The internal Filebrowser (`https://docker-host.tail91459b.ts.net/files/`) is
unchanged and stays tailnet-only.

## Why a gate

The public funnel points at the gate, never at Filebrowser directly. The gate
forwards only the **public share surface** — `/files/public/*` (share pages,
static assets, and the anonymous share API) — and returns `404` for everything
else. So `/files/login` and the authenticated `/files/api/*` are never public.

## Deploy

```sh
# on the VM
sudo mkdir -p /opt/filebrowser-share
# (scp this stack across, then)
cd /opt/filebrowser-share
cp .env.example .env          # fill TS_AUTHKEY
sudo mkdir -p ts-state
sudo docker compose up -d
```

## Going public (and only this)

The exposure is **one command, scoped to this node alone**:

```sh
docker exec fileshare-ts tailscale funnel --bg --https=443 http://127.0.0.1:8080
docker exec fileshare-ts tailscale funnel status     # verify
```

> **Never** funnel the other node (`docker-host`) — that would publish the
> dashboard, Navidrome, AdGuard, Filebrowser and Vaultwarden.

Turn it back off at any time:

```sh
docker exec fileshare-ts tailscale funnel --https=443 off
```

**Verify from outside the tailnet** (e.g. phone on mobile data, Tailscale off):
the share URL must work and `docker-host.tail91459b.ts.net` must **not**.

## Create a share (owner)

1. Sign in to Filebrowser over the tailnet at
   `https://docker-host.tail91459b.ts.net/files/`.
2. Share the folder you want (the account needs the **Share** permission — see
   the note below).
3. Hand out the link with the host swapped to `fileshare.tail91459b.ts.net`,
   e.g. `https://fileshare.tail91459b.ts.net/files/public/share/<hash>`.

The folder is served **live** from `/srv/backup`, read-only. `rclone sync`
deletions/renames propagate to what the recipient sees (the mirror is not a
history).

## Notes

- The node keeps the tailnet's **node key expiry** unless disabled — disable it
  for `fileshare` in the admin console, as for `zipline`.
- The **funnel policy** (`nodeAttrs`) must include this node's tailnet IP; the
  headscale/tailnet admin change is recorded in `docs/setup.md`.
- Enable the **Share** permission for the Filebrowser account (a fresh database
  gets it from `share: true` in `config/config.yaml`; an existing one needs the
  toggle in Settings → Users).
