# Access matrix — what works from where

Quick reference for **which door into the homelab works in which situation**.

**Legend:** 🏠 = on the home network · 🌍 = away from home (mobile data, café) ·
VPN = Tailscale connected.

> The two rules that explain everything:
>
> 1. `192.168.1.x` addresses exist **only on the home network**.
> 2. `*.tail91459b.ts.net` names exist **only while Tailscale is up**.

## Proxmox host & SSH

| | 🏠 no VPN | 🏠 with VPN | 🌍 no VPN | 🌍 with VPN |
| --- | --- | --- | --- | --- |
| Proxmox UI — `192.168.1.50:8006` | ✅ | ✅ | ❌ | ❌ |
| Proxmox UI — `pve.tail91459b.ts.net:8006` | ❌ | ✅ | ❌ | ✅ |
| SSH `root@192.168.1.50` (LAN) | ✅ | ✅ | ❌ | ❌ |
| SSH `root@pve` (tailnet) | ❌ | ✅ | ❌ | ✅ |
| SSH `rahul@192.168.1.60` (LAN) | ✅ | ✅ | ❌ | ❌ |
| SSH `rahul@docker-host` (tailnet) | ❌ | ✅ | ❌ | ✅ |

## Services

| | 🏠 no VPN | 🏠 with VPN | 🌍 no VPN | 🌍 with VPN |
| --- | --- | --- | --- | --- |
| **Vaultwarden** — `pve.tail91459b.ts.net` | ❌ | ✅ | ❌ | ✅ |
| **Homepage** — `docker-host.tail91459b.ts.net/` | ❌ | ✅ | ❌ | ✅ |
| **Navidrome** — `docker-host.tail91459b.ts.net/navidrome` | ❌ | ✅ | ❌ | ✅ |
| **PairDrop** — `docker-host.tail91459b.ts.net/pairdrop/` | ❌ | ✅ | ❌ | ✅ |
| **Filebrowser** — `docker-host.tail91459b.ts.net/files/` | ❌ | ✅ | ❌ | ✅ |
| **AdGuard Home** (admin) — `docker-host.tail91459b.ts.net:8443` | ❌ | ✅ | ❌ | ✅ |
| **Stirling PDF** — `docker-host.tail91459b.ts.net:10000/` | ❌ | ✅ | ❌ | ✅ |
| **MeTube** — `docker-host.tail91459b.ts.net/metube/` | ❌ | ✅ | ❌ | ✅ |
| Bitwarden offline cache (read/copy only) | ✅ | ✅ | ✅ | ✅ |

## Laptop backup (mirror → the homelab)

The laptop's `$HOME` is mirrored one-way to `/srv/backup` on the VM over **SFTP on
the tailnet** (rclone, 3×/day: 00:00, 08:00, 16:00). It is a **mirror, not a history**:
deletions propagate.

| | 🏠 no VPN | 🏠 with VPN | 🌍 no VPN | 🌍 with VPN |
| --- | --- | --- | --- | --- |
| `rclone sync` to `homelab:/srv/backup` | ❌ | ✅ | ❌ | ✅ |
| Browse it — `docker-host.tail91459b.ts.net/files/` | ❌ | ✅ | ❌ | ✅ |
| A restored copy of your files, if the laptop dies | — | ✅ | — | ✅ |

> Requires **Tailscale SSH to be off on `docker-host`** (its `check` action asks a
> human to re-authenticate every 12 h; a timer can't). See
> [`setup.md`](setup.md#laptop-backup-destination-2026-09-28).

## DNS ad-blocking (tailnet only)

AdGuard Home filters DNS for **tailnet devices only**. The home LAN is **not**
filtered — the router's DNS is operator-locked and we deliberately did not take
over DHCP. Family devices keep using the ISP's DNS, exactly as before.

| | 🏠 no VPN | 🏠 with VPN | 🌍 no VPN | 🌍 with VPN |
| --- | --- | --- | --- | --- |
| DNS filtering (AdGuard) | ❌ | ✅ | ❌ | ✅ * |
| LAN devices (TV, IoT, family phones) | ❌ | ❌ | ❌ | ❌ — by design |

\* once the tailnet's global nameserver is set to `100.74.164.49` (admin console).

## Public services (the deliberate exceptions)

Everything else is tailnet-only. Two services are published with `tailscale
funnel`, each on **its own tailnet node**:

| | 🏠 no VPN | 🏠 with VPN | 🌍 no VPN | 🌍 with VPN |
| --- | --- | --- | --- | --- |
| **Zipline** — `zipline.tail91459b.ts.net` (file sharing) | ✅ | ✅ | ✅ | ✅ |
| **Filebrowser share link** — `fileshare.tail91459b.ts.net/files/public/share/<hash>` | ✅ | ✅ | ✅ | ✅ |
| Filebrowser login/tree — `docker-host.tail91459b.ts.net/files/` | ❌ | ✅ | ❌ | ❌ |

**Zipline:** uploading requires the owner's login; recipients need only the link
(and cannot upload or browse). **Filebrowser shares:** read-only, served live from
`/srv/backup`; only the public share surface (`/files/public/*`) is exposed, so
`/files/login` and `/files/api/*` return `404` even publicly.

Verified: the `docker-host` mappings all still read *(tailnet only)*.

## Music share (manual mount)

| | 🏠 no VPN | 🏠 with VPN | 🌍 no VPN | 🌍 with VPN |
| --- | --- | --- | --- | --- |
| `sudo mount … //192.168.1.60/music` (LAN) | ✅ | ✅ | ❌ | ❌ |
| `sudo mount … //docker-host/music` (tailnet) | ❌ | ✅ | ❌ | ✅ |

## Windows VM (on-demand)

Cold by default — `qm start 101` first. Access is via the **Proxmox Console**
(served by `pve`), so it follows Proxmox's reachability.

| | 🏠 no VPN | 🏠 with VPN | 🌍 no VPN | 🌍 with VPN |
| --- | --- | --- | --- | --- |
| Console — `192.168.1.50:8006` → `windows` | ✅ | ✅ | ❌ | ❌ |
| Console — `pve.tail91459b.ts.net:8006` → `windows` | ❌ | ✅ | ❌ | ✅ |
| RDP `windows` *(optional — needs RDP + Tailscale inside Windows)* | ❌ | ✅ | ❌ | ✅ |

## Subtleties worth knowing

- **LAN doors are closed** (2026-09-28): Caddy and the VM's web services bind
  `127.0.0.1` only, so the **tailnet is the only way in**. *(Vaultwarden is the
  exception — `pve` proxies to it over the LAN, so its port remains on the flat
  LAN.)*
- **Dashboard at `/`**, services under paths: `/navidrome`, `/pairdrop/`,
  `/files/`, `/metube/`. Vaultwarden, AdGuard and Stirling keep their own
  name/port (they don't support subpaths).
- **`ssh rahul@docker-host` works from anywhere** — the VM joined the tailnet on
  2026-09-28.
- **Tailscale SSH is ON for `pve`, OFF for `docker-host`.** Over the tailnet,
  `ssh root@pve` may ask you to confirm in a browser every 12 h (Tailscale's
  `check` action), while `ssh rahul@docker-host` just uses your key. The VM's is
  off on purpose: unattended jobs (the backup) can't click a link.
- The **music share is mounted manually** (no automount) — see
  [`setup.md`](setup.md#mounting-the-library-on-the-laptop-manual-on-demand).
