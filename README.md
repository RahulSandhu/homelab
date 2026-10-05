# homelab

Personal homelab on a mini PC, built to be simple, private, and easy to grow.

It runs **Vaultwarden** (a Bitwarden-compatible password manager), **Navidrome**
(music), **PairDrop** (device-to-device sharing), **Filebrowser** (a read-only
view of the laptop's backups), **AdGuard Home** (tailnet DNS ad-blocking),
**Stirling PDF** (a stateless PDF toolbox), **MeTube** (`yt-dlp` downloads) and a
**Homepage** dashboard — all reachable from anywhere over a private **Tailscale**
tailnet and from nowhere else. No ports are opened on the router and the home IP
is never published. The two deliberate exceptions are **Zipline** (file sharing)
and **read-only Filebrowser share links**, each public through its own scoped
funnel.

> **Status: live.** Proxmox VE 9 on the mini PC, one Debian 13 VM (`docker-host`)
> running the services behind **Caddy**: a dashboard at
> <https://docker-host.tail91459b.ts.net/>, Navidrome, PairDrop, Filebrowser and
> MeTube, with AdGuard DNS (`:8443`) and Stirling PDF (`:10000`) on ports of their
> own, plus **Vaultwarden** on its own name at <https://pve.tail91459b.ts.net> and
> **Zipline** at <https://zipline.tail91459b.ts.net> and **read-only Filebrowser
> share links** at <https://fileshare.tail91459b.ts.net> (two scoped funnels). The
> VM is also the **laptop's backup destination** (`/srv/backup`, rclone over SFTP).
> See [`docs/setup.md`](docs/setup.md).

## Architecture at a glance

```
Internet ──> Consumer Router (NAT, flat LAN 192.168.1.0/24)
                 └── Mini PC "pve" · Proxmox VE 9 · Tailscale
                         └── Debian 13 VM "docker-host" (192.168.1.60)
                                 ├── Caddy ── / · /navidrome · /pairdrop/ · /files/ · /metube/
                                 ├── AdGuard DNS (:8443 UI) · Stirling PDF (:10000)
                                 ├── Vaultwarden ← https://pve.tail91459b.ts.net (served by pve)
                                 ├── Zipline (own node) ── public via funnel
                                 ├── Filebrowser share links (own node) ── public, read-only
                                 └── /srv/backup ← rclone mirror of the laptop

Tailnet members ──WireGuard──> docker-host.tail91459b.ts.net
  (archlinux · s24-de-rahul · any future device)
```

Full diagram: `docs/schemas/homelab.dot` (rendered to `tmp/homelab.png`).

## Contents

| Path                          | What it is                                        |
| ----------------------------- | ------------------------------------------------- |
| `docs/access-matrix.md`       | **What works from where** (home/away × VPN).      |
| `docs/schemas/homelab.dot`    | Architecture diagram (Graphviz).                  |
| `docs/setup.md`               | Step-by-step runbook (Proxmox → services → backup). |
| `docs/specs/`                 | Design documents.                                 |
| `docs/plans/`                 | Implementation plans.                             |
| `stacks/vaultwarden/`         | Vaultwarden Compose stack.                        |
| `stacks/navidrome/`           | Navidrome Compose stack.                          |
| `stacks/caddy/`               | Reverse proxy (path routing).                     |
| `stacks/homepage/`            | Hero dashboard at `/`.                            |
| `stacks/pairdrop/`            | PairDrop file sharing.                            |
| `stacks/filebrowser/`         | Read-only web GUI over the backup mirror.         |
| `stacks/adguard/`             | DNS ad-blocking for tailnet devices.              |
| `stacks/stirling-pdf/`        | PDF toolbox (stateless).                          |
| `stacks/zipline/`             | File sharing — public via funnel.                 |
| `stacks/filebrowser-share/`   | Read-only **public** Filebrowser share links.     |
| `stacks/metube/`              | Video downloads (yt-dlp) to a staging disk.       |
| `stacks/music-share/`         | Samba config for the music share.                 |
| `vms/windows/`                | Windows 10 VM (on-demand) — create script + notes. |

## Diagram

```sh
make schemas      # docs/schemas/*.dot -> tmp/*.png
make clean        # remove tmp/
```

## Deploying the stack

See [`docs/setup.md`](docs/setup.md) for the full runbook, and
[`stacks/vaultwarden/README.md`](stacks/vaultwarden/README.md) for the
service-specific steps.

## Principles

- **VPN-only, with two exceptions.** Tailscale is the only door for everything —
  except **Zipline** (`stacks/zipline/`) and **Filebrowser share links**
  (`stacks/filebrowser-share/`): deliberate, reversible, funnel-scoped decisions.
- **Deliberate updates.** Images are pinned; changes are intentional.
- **Snapshot before change.** Proxmox snapshots are the safety net.
- **The homelab is the laptop's backup destination** — a one-way rclone mirror
  at `/srv/backup` (a mirror, not a history: deletions propagate).
  Vaultwarden keeps snapshots plus manual exports.
