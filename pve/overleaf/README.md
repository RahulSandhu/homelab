# Overleaf (Community Edition)

Collaborative LaTeX editor for the owner and a few invited collaborators.

- **Served at:** `https://overleaf.tail91459b.ts.net/` — public.
- **Deploy:** on `pve`, `bash create.sh`; then inside the VM
  `TS_AUTHKEY=tskey-... sudo -E bash setup-host.sh` and `sudo bash bootstrap.sh`.

## Notes

- Its own VM (VMID 102), not `docker-host`: Overleaf CE has no sandboxed
  compiles, so a compile must not reach Vaultwarden or the backup mirror.
- No SMTP — the owner creates each account (`create-user`) and shares the
  printed URL. Anonymous link editing is off (CE 6.3.0 mis-flush bug).
- `overleaf-backup.timer` runs daily into `/srv/overleaf/backups` (7-day
  prune).
