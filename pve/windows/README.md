# Windows 10 VM

On-demand Windows VM on `pve` (cold by default; `qm start 101`). Reached through
the Proxmox console, so nothing needs setting up inside Windows.

Create: put the ISO in `local:iso/` on `pve`, then `ISO=... bash create.sh`.
