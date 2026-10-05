# Homelab design — Laptop backup destination + Filebrowser

- **Date:** 2026-09-28
- **Status:** Implemented 2026-09-28 (see "As built")
- **Repo:** `~/desktop/projects/homelab`
- **Depends on:** the 2026-09-27 and 2026-09-28 specs (Caddy/Homepage/PairDrop, Navidrome/music share)

## Context

The laptop's `$HOME` has been mirrored **one-way to Google Drive** by
`~/.config/rclone/scripts/sync-drive.sh`, run by `sync-drive.timer` every 8 hours,
with `filters.txt` excluding caches, `.git`, `node_modules`, language
environments (`.venv`, `.renv`), etc. `rclone size "google drive:framework12"`
reports **211.870 GiB in 117,164 objects** — i.e. the filtered set is far smaller
than the ~470 GB of on-disk `$HOME`.

The homelab was always intended to **become the laptop's backup destination**
(see the rules in `AGENTS.md`). This spec retires Google Drive, moves the mirror
onto the mini PC, and adds a browsable GUI — all tailnet-only, consistent with
the existing reverse-proxy and "no LAN doors" decisions.

## Goals

- One-way mirror of `$HOME` → the homelab, with **the existing filters** (plus one
  addition, below).
- Storage on a dedicated **350 GB** disk at `/srv/backup` on `docker-host`.
- A **browsable, read-only GUI** at `/files` (**Filebrowser**) behind Caddy,
  tailnet-only, with a dashboard tile.
- **No new exposed port**: transport is **SFTP** over the existing tailnet SSH
  (Filebrowser runs internal-only, behind Caddy, with no host port).
- Retire Google Drive.

## Non-goals

- Versioned / chunked / deduplicating backup (restic, Kopia, Borg). This is a
  **mirror**, deliberately: one current copy that keeps updating.
- **Sharing links with people off the tailnet.** Parked by the owner; it would
  require public exposure and a deliberate change to the "never public" rule.
- Backing up the backup destination itself.

## Decisions

### 1. rclone + SFTP + Filebrowser, not Nextcloud

| | rclone→SFTP + Filebrowser | Nextcloud (+ rclone via WebDAV) |
| --- | --- | --- |
| Filters | `filters.txt` used **verbatim** | n/a (destination side) |
| Transport for 117k objects | SFTP — fast listing | WebDAV/PROPFIND — markedly slower |
| Server state | a directory (+ ~50 MB GUI) | database + config + app data |
| RAM on the VM | ~50 MB | ~1.5–2.5 GB (would need a 4→6 GB bump) |
| Maintenance | minimal | frequent release/upgrade cadence |

Nextcloud was considered (GUI **and** share links) and rejected on weight,
maintenance and the fact that **share links depend on exposure, not the app** —
so it bought nothing for the parked sharing goal.

### 2. Plaintext mirror, read-only GUI

End-to-end encryption would make the GUI show opaque blobs. The mirror is
**plaintext on disk** (as Google Drive was), protected by the tailnet and
Filebrowser's own login. The GUI binds `/srv/backup` **read-only**, because any
write through the GUI would be silently reverted by the next `sync --delete`
(and would confuse the operator).

### 3. Filter scope unchanged, plus `/music`

`~/.config` (which contains tokens such as `rclone.conf` and `gh/hosts.yml`)
**remains in scope** — the owner's explicit call; to be revisited later.
`- **/.env/**` stays as-is (owner's call). The one addition is `- /music/**`:
the Samba mount is redundant on the same server, and an unmounted `~/music` is
indistinguishable from the mounted share at scan time.

## Architecture

```
laptop  $HOME  (filters.txt)
  │   rclone sync --delete-during --delete-excluded   (systemd timer, 00/08/16)
  │   SFTP over the tailnet
  ▼
docker-host   /srv/backup        ext4, 350 GB thin disk, label "backup"
  │   bind-mounted READ-ONLY
  ▼
filebrowser container ── proxy network ── Caddy /files ── tailscale serve :443
  └────────────► https://docker-host.tail91459b.ts.net/files   (tailnet only)

Google Drive: retired.
```

## Components

| Component | Image (pinned) | Notes |
| --- | --- | --- |
| Filebrowser | `gtstef/filebrowser:1.5.6-stable` (FileBrowser Quantum) | `stacks/filebrowser/`; `baseURL: /files` in `config/config.yaml` (`FILEBROWSER_CONFIG`); joins external `proxy`; mounts `/srv/backup` **ro**; state in `./data` |
| Caddy (existing) | `caddy:2.11.4-alpine` | add `handle /files* { reverse_proxy filebrowser:80 }` (no strip — base URL kept) |

Storage: `qm set 100 -scsi2 local-lvm:350` → guest `/dev/sdc` → `mkfs.ext4 -L backup`
(whole device, no partition table) → `/srv/backup`, mounted from `/etc/fstab` by UUID,
owned `rahul:rahul`, mode `750`.

## Backup semantics

- **Mirror, not history:** `--delete-during --delete-excluded` — deletions and
  renames propagate. `--filter-from` unchanged.
- **Restore:** browse/download through Filebrowser, or
  `rclone copy homelab:/srv/backup/<path> ~/<path>`.
- **Health:** `notify-send` on success/failure (existing behaviour);
  `rclone size homelab:/srv/backup` to compare against the source.

## Risks and open notes

- A mirror **on the same premises** as the laptop is not off-site protection.
- The destination is a **single disk** (no RAID) — one more reason the Google
  copy is only retired *after* the mirror is verified good.
- The **first sync moves ~212 GiB / ~117k objects** (the later `.rustup`
  exclusion cut the object count to **51.4k** — see As built); it runs at home
  over the LAN.
- `--delete-excluded` means **later filter edits purge the destination** — hence
  the filter decision is taken *before* the first sync.
- `~/.config/rclone/rclone.log` grows unbounded (pre-existing); worth revisiting.
- **Dotfiles changes are made but not committed** (owner's standing rule).

## Migration phases

| Phase | What | Owner |
| --- | --- | --- |
| 0 | Snapshot VM 100 (`pre-backup`); apply the `/music` filter | agent |
| 1 | 350 GB disk → `mkfs` → fstab → mount `/srv/backup` | agent |
| 2 | `stacks/filebrowser/` + deploy + Caddy route; verify `/files` → 200 | agent |
| 3 | Filebrowser first run: set the admin password | **owner** |
| 4 | `[homelab]` SFTP remote; `rclone lsd`; **dry-run review** | agent / **owner** |
| 5 | First real sync (~212 GiB) + verify with `rclone size` | agent |
| 6 | `sync-homelab.{sh,service,timer}`; 00/08/16 cadence; disable the Drive timer | agent |
| 7 | Dashboard tile for `/files` | agent |
| 8 | Retire Google: remove the remote; revoke/delete in the Google account | agent / **owner** |
| 9 | Docs + diagram + `AGENTS.md` rule rewrite + commit | agent |

## As built

Deviations and discoveries during the build:

- **The original Filebrowser was archived (2026-09-01)** mid-build, so the GUI uses
  **FileBrowser Quantum** (`gtstef/filebrowser:1.5.6-stable`) instead. Its config is
  `config/config.yaml`, mounted at `/config/config.yaml` via `FILEBROWSER_CONFIG`.
  Gotcha: on a **brand-new database the first user command fails** with a misleading
  *"password must be at least 8 characters long"* — run it a second time.
- **Tailscale SSH had to be turned OFF on the VM.** The tailnet's SSH policy uses the
  `check` action, which demands a **browser re-auth every 12 h** — impossible for an
  unattended timer. `sudo tailscale set --ssh=false` on `docker-host` makes tailnet
  SSH use the VM's own sshd and the operator's key.
- **Filters gained `/music` and `/.rustup`.** The former is redundant on the same
  server; `.rustup` alone was **65,696 files — 56% of the whole set** — of regenerable
  Rust toolchain docs.
- **`lost+found`** (created by `mkfs`) failed the first dry run with a permission
  error, which also aborted deletions; making it `rahul`-owned let the sync prune it.

Verified on completion:

```
rclone size homelab:/srv/backup --human-readable
  Total objects: 51.416k        (dry-run prediction: 51,404)
  Total size:    215.792 GiB    (dry-run prediction: 215.8 GiB)
```

`sync-homelab.timer` is enabled (00:00, 08:00 and 16:00, `Persistent=true`) and active.
Google Drive was retired: the `[google drive]` remote was removed from
`rclone.conf` and the old `sync-drive.*` script/units deleted.
