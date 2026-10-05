# Homelab design — Vaultwarden over Tailscale

- **Date:** 2026-09-27
- **Status:** Implemented 2026-09-27 (see "As built" below)
- **Repo:** `~/desktop/projects/homelab`

> **Superseded in part (2026-09-28).** This is the original foundation doc; later
> specs moved past it:
> - The reverse proxy is now **Caddy** (`stacks/caddy/`) on the VM, with
>   `tailscale serve` pointing at it — not `serve` straight to one service.
> - The VM serves several apps on **paths**: `/` Homepage, `/navidrome`,
>   `/pairdrop/`, `/files/`, `/metube/` — the rest on their own names/ports.
> - `funnel` is no longer absolutely forbidden: the **`zipline`** node alone is
>   published on purpose (IP-scoped, reversible); everything else stays `serve`.
> - **Tailscale SSH is now deliberately OFF on `docker-host`** (its 12-hour
>   browser `check` breaks unattended jobs) — the "Tailscale SSH available" line
>   under Security posture no longer applies.
> - The homelab **is now the laptop's backup destination** (`/srv/backup`, rclone
>   over SFTP); the "Non-goals: a backup system" line is obsolete.

## Context

A new mini PC (BOSGAME E5, Ryzen 5300U, 16 GB RAM, 1 TB NVMe, dual 2.5G NIC)
arrived. The goal is a personal service platform starting with Vaultwarden, and
it must be reachable "across the whole internet" without exposing the home
network.

Current home network: a **consumer router** with a flat LAN. No managed switch,
no VLANs, no real firewall rules. This constrains how much network-level
isolation is possible today.

## Goals

- Run Vaultwarden, reachable from any of the owner's devices, anywhere.
- No inbound ports on the router, no public DNS, home IP never exposed.
- A setup that is simple to run but "properly" structured, and easy to extend
  with more services later.
- Pin dependencies; make every change deliberate rather than automatic.

## Non-goals

- Publicly accessible services (rejected in favour of VPN-only).
- Network segmentation / VLANs **for now** — deferred, not forgotten.
- A backup system. The homelab is intended to *become* the backup destination
  for the owner's laptop, not the thing being backed up. Vaultwarden's vault is
  the sole exception, handled with snapshots + manual exports.

## Decision: access model

**Tailscale (WireGuard) VPN-only.** Clients join a private tailnet; the server
is never published. Chosen over a public HTTPS URL (port-forward + Let's Encrypt)
and over self-hosted WireGuard, because it gives a real HTTPS endpoint with
automatic certificates, no port forwarding, and no per-device key wrangling.
`tailscale serve` provides tailnet-only TLS; `tailscale funnel` is explicitly
forbidden as it would make the service public.

## Decision: platform

**Proxmox VE 9** on the mini PC, `ext4` + LVM-thin. Proxmox gives snapshots,
VM lifecycle management, and an obvious growth path, which matches the
"scalable" goal. The lighter alternative (Docker directly on Arch/Debian) was
set aside; LXC-nesting and community helper scripts were also considered and
rejected as either footgun-prone or insufficiently intentional for a foundation.

## Decision: guest topology

**One Debian 13 VM (`docker-host`) running Docker Compose**, with Vaultwarden as
a container on it. Rationale: Docker Compose is the reusable, portable pattern
every future service will follow; VM isolation is clean; a VM snapshot is a
one-click pre-update safety net; and 16 GB of RAM absorbs the VM overhead.

## Architecture

```
Internet ── ISP ──> Consumer Router (NAT, flat LAN 192.168.1.0/24)
                          └── Mini PC "pve": Proxmox VE 9 + Tailscale node
                                  └── Debian 13 VM "docker-host" (192.168.1.60)
                                          └── Vaultwarden 1.37.3 (container, ./data)

Tailnet members (archlinux, s24-de-rahul, …) ── WireGuard ──> tailnet ──>
    Proxmox host ── tailscale serve :443 ──> VM:8080 ──> Vaultwarden
```

Addressing: host `pve` = `192.168.1.50`, VM `docker-host` = `192.168.1.60`,
tailnet `tail91459b.ts.net`; tailnet-only URL `https://pve.tail91459b.ts.net`.

## Components

- **Proxmox host** — Proxmox VE 9, ext4/LVM-thin, Tailscale, no-subscription
  repo, security updates. Also the site of `tailscale serve`.
- **Debian VM `docker-host`** — Debian 13, Docker Engine + Compose plugin,
  2 vCPU / 4 GB / 32 GB (later raised to **6 GB** with MeTube).
- **Vaultwarden** — pinned `vaultwarden/server:1.37.3`, `./data` volume,
  published on `8080`. Configured via `.env` (`DOMAIN`, `ADMIN_TOKEN` as an
  Argon2 hash, `SIGNUPS_ALLOWED`).

## Security posture

- Tailnet-only reachability; HTTPS end to end; no router ports opened.
- Vaultwarden: signups closed after first account, Argon2 admin token, 2FA on
  the account.
- Host: SSH keys preferred; Tailscale SSH available; regular updates.
- **Known limitation:** the flat LAN means other home devices could reach
  `http://192.168.1.60:8080` if they knew to look. Accepted for now; the documented
  upgrade path is a private NAT bridge inside Proxmox.

## Repo layout

```
Makefile                     # help / schemas / clean (mirrors green-electro)
docs/schemas/homelab.dot     # architecture diagram -> tmp/homelab.png
docs/setup.md                # the operating runbook
docs/specs/                  # this document
stacks/vaultwarden/          # compose.yaml, .env.example, README.md
```

## As built (deviations & discoveries)

- **Proxmox VE 9.2 / Debian 13 "trixie".** The design above said VE 8 / Debian
  12; the current release at build time was 9.2 on trixie. The paid repos are
  disabled and `pve-no-subscription` (suite `trixie`) is used.
- **The guest is provisioned with cloud-init, not an interactive ISO install.**
  The VM boots Debian's `debian-13-genericcloud-amd64` image; `qm set` injects
  the user, SSH key, static IP, and disk size. Reproducible and scriptable.
- **The reverse proxy is `tailscale serve`, not Caddy.**
  `tailscale serve --bg http://192.168.1.60:8080` publishes tailnet-only HTTPS
  with an automatic certificate. `funnel` was never used.
- **Two gotchas:** the admin token needs a real TTY to generate
  (`docker run --rm -it … hash`), and `$` must be escaped as `$$` in `.env`
  because Compose interpolates it. Both are documented in `.env.example`.
- **Clients:** `archlinux` (desktop) and `s24-de-rahul` (phone) are on the
  tailnet. A signed-in device reaches the vault from anywhere; a signed-out
  device can only unlock its cached copy.

## Risks

| Risk                                   | Mitigation                                            |
| -------------------------------------- | ----------------------------------------------------- |
| Losing the vault (NVMe failure)        | VM snapshots before changes + periodic vault export   |
| Forgetting to close signups            | Prominent warning in `.env.example` and Phase 8        |
| Accidental public exposure             | Tailscale `serve` only; `funnel` forbidden by policy   |
| Flat LAN lateral movement              | Deferred; upgrade path documented                      |

## Success criteria

- Vaultwarden is reachable at `https://pve.tail91459b.ts.net` from any tailnet
  device, and unreachable with Tailscale off.
- No ports are forwarded on the router.
- `make schemas` renders the diagram; `make clean` removes `tmp/`.
- Adding a future service requires only a compose service + one `serve` route.
