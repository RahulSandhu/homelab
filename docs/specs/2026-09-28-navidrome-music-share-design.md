# Homelab design — Navidrome + music share

- **Date:** 2026-09-28
- **Status:** Implemented 2026-09-28 (see "As built")
- **Repo:** `~/desktop/projects/homelab`
- **Depends on:** `docs/specs/2026-09-27-homelab-design.md` (Vaultwarden, tailnet)

> **Superseded in part (2026-09-28).** The VM no longer joins with `--ssh`
> (Tailscale SSH is **off** on `docker-host` — its 12-hour browser `check` breaks
> unattended jobs), and Navidrome is now served at **`/navidrome`** through
> **Caddy**, not at the VM's root. See `docs/setup.md`.

## Context

Vaultwarden is live on a Proxmox host with a single Debian 13 VM (`docker-host`).
The owner wants their music library to live on the homelab instead of the laptop,
streamed from anywhere, with the laptop's `~/music` acting as a **network mount**
into the server so that "adding music" is just dropping files into `~/music`.

Today: `~/music` = 202 MB, 47 files, flat.

## Goals

- The library physically lives on the homelab.
- `~/music` on the laptop is a live mount into the server, usable **at home and away**.
- Navidrome serves the library; streamable from anywhere over the tailnet.
- Grow-friendly storage. **No new hardware. No new VM.**

## Non-goals

- Video / Jellyfin (future; would likely own its own VM for transcoding).
- Public internet exposure (still tailnet-only).
- Backups (unchanged policy: the homelab is the backup _destination_).

## Decisions

| Decision     | Choice                                                    | Rationale                                                 |
| ------------ | --------------------------------------------------------- | --------------------------------------------------------- |
| Service      | **Navidrome**                                             | Subsonic-compatible; many clients                         |
| Placement    | Container on the **existing `docker-host` VM**            | Tiny (~100–200 MB RAM); reuses Docker; one VM to snapshot |
| Storage      | **50 GB thin virtual disk** on `local-lvm` → `/srv/music` | Costs nothing until used; live-growable                   |
| Filesystem   | `ext4` on the **whole device** (no partition table)       | Growth = `qm resize` + `resize2fs /dev/sdb`, nothing else |
| Share        | **Samba (SMB)**, user `rahul`                             | Cross-platform; the owner's request                       |
| Tailnet      | **The VM joins as `docker-host`** (`--ssh`)               | Share + SSH reachable anywhere; fixes the remote-SSH gap  |
| Exposure     | `tailscale serve` **on the VM**                           | Clean per-service name                                    |
| Laptop mount | **CIFS, manual** (`sudo mount -t cifs … ~/music`)         | On demand; no automount state to go stale                 |

## Architecture

```
Laptop ~/music ── SMB over Tailscale ──▶ docker-host VM  /srv/music
                                              │  (50 GB virtual disk)
                                              └─ Navidrome (read-only mount)
                                                   └─ https://docker-host.tail91459b.ts.net
```

The Proxmox host keeps serving Vaultwarden at `pve.tail91459b.ts.net`; the VM
serves Navidrome at `docker-host.tail91459b.ts.net`. Two nodes, two clean names.

## Components

- **Data disk** — VM 100 `scsi1`, 50 GB thin, `/dev/sdb`, `ext4`, mounted
  `/srv/music` by UUID in fstab.
- **Samba** — native on the VM; minimal `smb.conf` exporting `[music]`
  (writable, `valid users = rahul`, `force user = rahul`).
- **Tailscale** — on the VM, `--ssh --hostname=docker-host`, key expiry disabled.
- **Navidrome** — `stacks/navidrome/` (pinned image), `/srv/music:/music:ro`,
  `./data:/data`, port `4533`.
- **Laptop** — `~/music` mounted **on demand** from `//docker-host/music`:
  `sudo mount -t cifs … -o credentials=…,soft,echo_interval=5`. No automount.

## Security

- Share restricted to `192.168.1.0/24` (LAN) and `100.64.0.0/10` (tailnet).
- SMB password auth (separate from the Linux password).
- Off-LAN traffic encrypted by WireGuard; Navidrome over HTTPS via `tailscale serve`.
- **No ports are opened on the router.**
- New secret: `~/.smbcredentials` on the laptop (chmod 600).

## Migration

1. Build storage, Samba, Tailscale, and Navidrome on the server.
2. `rsync -a ~/music/ rahul@docker-host:/srv/music/` — verify 47 files.
3. **Then** add the fstab mount at `~/music` (mounting first would hide the files).

## As built (deviations & discoveries)

- **CIFS options, take two.** The first attempt used `timeo`/`retrans` — these
  are **NFS** options, and cifs rejects them with `mount error(22): Invalid
  argument`, leaving the mount **failed**. Corrected to `soft,echo_interval=5`.
- **Automount removed; mounting is manual.** The `x-systemd.automount` + fstab
  approach was dropped. With Tailscale off, every mount attempt fails instantly
  (the name won't resolve), so systemd's mount **start-limit** trips after ~5
  rapid failures, marks the automount *failed*, and leaves `~/music` empty until
  a manual reset — including after reconnecting. Mounting on demand
  (`sudo mount -t cifs …`) carries no such state. **Samba and
  `~/.smbcredentials` are retained.**
- **The VM is now a tailnet node** — `docker-host` at `100.74.164.49`; the
  earlier "the VM is not on the tailnet" note is superseded.
- **Local originals removed** after verifying the server copy, so an unmounted
  `~/music` is empty rather than showing stale duplicates.

## Risks

| Risk                                                        | Mitigation                                               |
| ----------------------------------------------------------- | -------------------------------------------------------- |
| `~/music` is network-only (manual mount)                    | Mount on demand; the library is safe on the server       |
| Can't shrink the data disk                                  | Start at 50 GB                                           |
| VM joining the tailnet enlarges the surface                 | Still tailnet-only; key expiry disabled, updates applied |
| Writes while the share is down fail                         | Mount only when the server is reachable; accepted        |

## Success criteria

- `https://docker-host.tail91459b.ts.net` serves Navidrome; it streams on a phone
  over 5G.
- `~/music` shows the library after a manual `mount` command, at home or away
  (over the tailnet). **Nothing mounts automatically.**
- Dropping a file into `~/music` appears in Navidrome after a scan.
- No router ports opened; `ssh rahul@docker-host` works from anywhere.
