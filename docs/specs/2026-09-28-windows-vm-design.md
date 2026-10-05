# Homelab design — Windows 10 VM (on-demand)

- **Date:** 2026-09-28
- **Status:** Implemented 2026-09-28 (see "As built")
- **Repo:** `~/desktop/projects/homelab`

## Context

The homelab runs one VM (`docker-host`, 100) with Vaultwarden + Navidrome. The
owner occasionally needs a Windows app and already has a **Windows 10 22H2** ISO.
The VM should be **cold by default** (started only when needed), reachable
graphically from the laptop, and reachable from anywhere over the tailnet.

## Goals

- A Windows 10 VM on Proxmox, **off by default** (0 GB RAM when stopped).
- Graphical access from the laptop — install via the Proxmox console, use via RDP.
- Reachable from **anywhere** over the tailnet.
- Small footprint; no help scripts (owner is happy with `qm start 101`).

## Non-goals

- Gaming / 3D (no GPU passthrough).
- 24/7 operation.
- Windows 11 (different TPM/Secure-Boot requirements).

## Decisions

| Decision | Choice | Rationale |
| --- | --- | --- |
| OS | **Windows 10 22H2** (existing ISO) | already downloaded; no TPM/Secure Boot needed |
| Edition | **Windows 10 Pro** | ⚠️ Home **cannot host RDP** |
| CPU / RAM | **2 vCPU / 4 GB** | small; shares the 4c/8t host |
| Disk | **40 GB** thin on `local-lvm` | plenty; thin |
| Machine / BIOS | `q35` + **OVMF (UEFI)** + EFI disk | modern default |
| Disk bus | **SATA** | zero driver-loading during setup |
| NIC | **e1000** | works out of the box (no virtio driver) |
| Start at boot | **No** | on-demand only |
| Remote desktop | **RDP** + Tailscale inside Windows | smooth, anywhere |
| Console | Proxmox noVNC | install + fallback, works from anywhere |

## Architecture

```
Proxmox ── VM 101 "windows" (off by default)
              ├─ install/configure via Proxmox Console (browser, noVNC)
              ├─ Tailscale inside Windows → tailnet node "windows"
              └─ RDP ← laptop (Remmina), at home or on 5G
```

## Access

- **Install / fallback:** `https://pve.tail91459b.ts.net:8006` → VM `windows` → Console.
- **Daily use:** Remmina → `windows` (tailnet) or the VM's LAN IP (home).

## Caveats (accepted)

- **Windows 10 is EOL** — no security updates; isolated, occasional use.
- **RDP needs the Pro edition** (choose Pro at install).
- **No GPU** — fine for apps/browsing.
- **~1 min boot** each start (no VM hibernation).
- **LAN door exists** (same flat-network caveat as Navidrome).

## Repo artifacts

- `vms/windows/create.sh` — the exact `qm create` (reproducible)
- `vms/windows/README.md` — install + RDP/Tailscale wiring
- `docs/setup.md` — "Adding a VM: Windows" section
- `docs/access-matrix.md` — Windows row

## Success criteria

- `qm start 101` → Windows boots → RDP from the laptop works at home **and** on 5G.
- `qm shutdown 101` → RAM released.
- No router ports opened.

## As built (deviations & discoveries)

- **RDP + Tailscale-in-Windows were downgraded to *optional*.** The owner found
  the **Proxmox Console** (noVNC) good enough for occasional use, and the console
  is already reachable from anywhere because `pve` is on the tailnet — no setup
  inside the guest required. RDP remains available as an upgrade path.
- **Boot-order gotcha:** with the CD first (`ide2;sata0`), the reboot after Setup
  booted the installer again. Fixed with `qm set 101 --boot order=sata0`. The ISO
  is ejected after install.
- **Windows 10 was installed and shut down cleanly** (ACPI `qm shutdown` works
  without a guest agent).
- **SATA disk + e1000 NIC** chosen over virtio: no driver-loading during Setup.
