# Homelab Backup Destination — Implementation Plan

> **As built (2026-09-28) — deviations from this plan.**
> 1. The original `filebrowser/filebrowser` was **archived 2026-09-01** (no
>    security fixes), so Tasks 3–4 use **FileBrowser Quantum**
>    (`gtstef/filebrowser:1.5.6-stable`). Its config lives in
>    `config/config.yaml`, mounted at `/config/config.yaml` via
>    `FILEBROWSER_CONFIG`. **On a brand-new database the first `set` command
>    fails** with a misleading *"password must be at least 8 characters"* — the
>    second run succeeds.
> 2. Unattended SFTP required **disabling Tailscale SSH on the VM**
>    (`sudo tailscale set --ssh=false`) — a new **Task 0**. Its `check` action
>    demands a browser re-auth every 12 h, which a timer cannot do.
> 3. Added `- /.rustup/**` to `filters.txt` (Rust toolchain docs: 65,696 files —
>    56% of the set). The backup's admin user is **`root`**.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Retire Google Drive and mirror the laptop's `$HOME` (existing `rclone` filters) onto the homelab at `/srv/backup`, with a read-only **Filebrowser** GUI at `/files` — tailnet-only.

**Architecture:** A 350 GB thin virtual disk on the existing `docker-host` VM is formatted ext4 and mounted at `/srv/backup`. The laptop's `rclone sync` writes to it over **SFTP** on the tailnet (no new server-side daemon or port). A **Filebrowser** container binds the directory read-only and is published through **Caddy** at `/files` (same `proxy` network, same `tailscale serve` front door).

**Tech Stack:** Proxmox VE 9 (`qm`), Debian 13 VM, LVM-thin, ext4, rclone (sftp remote), systemd user timer, Docker Compose (Filebrowser), Caddy, Tailscale.

**Spec:** `docs/specs/2026-09-28-homelab-backup-destination-design.md`

## Global Constraints

- **Never `tailscale funnel`** — `serve` only. **No ports opened on the router.**
- **Images pinned.** Filebrowser `gtstef/filebrowser:1.5.6-stable` (the original `filebrowser/filebrowser` was archived — see the As-built note). Never `:latest`.
- **Dotfiles changes are NOT committed** (owner's standing rule); homelab repo commits are fine.
- **Verify the mkfs target.** VM 100 already has `/dev/sda` (OS) and `/dev/sdb` (music). The new disk must be `/dev/sdc` — a wrong target destroys the VM.
- **`/srv/backup` is mounted read-only into the GUI.** Any write there is reverted by the next `rclone sync`.
- **Filters are decided before the first sync** — `--delete-excluded` purges the destination when filters change.
- **No backup-of-the-backup.**
- **Values:** host `pve` `192.168.1.50`; VM `docker-host` `192.168.1.60` (tailnet `100.74.164.49`); tailnet `tail91459b.ts.net`.

## Review Focus

- **`mkfs` target must be `/dev/sdc`, never `/dev/sda`/`/dev/sdb`** — pinned by Task 2 Step 3.
- **`/srv/backup` must be read-only in Filebrowser** — pinned by Task 3 Step 1 and the Task 3 verification.
- **No LAN door for Filebrowser** — no host ports; only Caddy reaches it on the `proxy` network.
- **`/files` must render** (base-url + trailing-slash) — pinned by Task 3 Step 4.
- **The mirror matches the source** — pinned by Task 6 Step 2 (`rclone size`) and the dry-run review in Task 5.
- **Google is only retired after the mirror is verified** — Task 9 comes last.

---

## Task 1: Pre-flight

**Produces:** a rollback point on VM 100; the final filter set.

- [ ] **Step 1 — Snapshot the VM**

```sh
ssh root@192.168.1.50 'qm snapshot 100 pre-backup --description "before backup destination" && qm listsnapshot 100'
```
Expected: `pre-backup` listed.

- [ ] **Step 2 — Add the `/music` exclusion**

Append to `~/.config/rclone/scripts/filters.txt`:

```
- /music/**
```

(Rationale: the Samba mount is redundant on the same server; an unmounted
`~/music` is indistinguishable from the mounted share at scan time.)

- [ ] **Step 3 — Verify the filter file**

```sh
tail -5 ~/.config/rclone/scripts/filters.txt
```
Expected: the `- /music/**` line is present.

---

## Task 2: Data disk + `/srv/backup`

**Interfaces:** produces `/srv/backup` (ext4, 350 GB) on the VM, mounted persistently by UUID.

- [ ] **Step 1 — Create the disk on the host**

```sh
ssh root@192.168.1.50 'qm set 100 --scsi2 local-lvm:350,discard=on,ssd=1,iothread=1 && qm config 100 | grep scsi2'
```
Expected: a line like `scsi2: local-lvm:vm-100-disk-2,discard=on,iothread=1,size=350G,ssd=1`

- [ ] **Step 2 — Confirm the guest sees it**

```sh
ssh rahul@192.168.1.60 'lsblk -o NAME,SIZE,TYPE,MOUNTPOINT'
```
Expected: `sdc  350G  disk` with no mountpoint. If absent: `ssh root@192.168.1.50 'qm reboot 100'`, wait ~30 s, retry.

- [ ] **Step 3 — Safety check (REVIEW FOCUS)**

```sh
ssh rahul@192.168.1.60 'lsblk -no NAME,SIZE,TYPE /dev/sdc; sudo blkid /dev/sdc || echo "no filesystem (correct)"
ssh rahul@192.168.1.60 "lsblk -no NAME,SIZE,TYPE /dev/sda /dev/sdb"'
```
Expected: `/dev/sdc` is a ~350 G blank disk; `/dev/sda`=32 G (OS), `/dev/sdb`=50 G (music). **Stop if the target is not `/dev/sdc`.**

- [ ] **Step 4 — Format**

```sh
ssh rahul@192.168.1.60 'sudo mkfs.ext4 -L backup /dev/sdc'
```

- [ ] **Step 5 — Mount persistently**

```sh
ssh rahul@192.168.1.60 '
  sudo mkdir -p /srv/backup
  UUID=$(sudo blkid -s UUID -o value /dev/sdc)
  echo "UUID=$UUID /srv/backup ext4 defaults,nofail 0 2" | sudo tee -a /etc/fstab
  sudo systemctl daemon-reload && sudo mount -a
  sudo chown rahul:rahul /srv/backup && sudo chmod 750 /srv/backup
  df -h /srv/backup; ls -ld /srv/backup
'
```
Expected: `/srv/backup` shows ~350 G with ~340 G free, owned `rahul:rahul` mode `750`.

---

## Task 3: Filebrowser stack + Caddy route

**Files:** `stacks/filebrowser/compose.yaml`, `stacks/filebrowser/README.md`, `stacks/caddy/Caddyfile`.
**Interfaces:** produces `http://filebrowser:80` on the `proxy` network, and `/files` on the tailnet.

- [ ] **Step 1 — Write the stack**

`stacks/filebrowser/compose.yaml` — pinned image, `restart: unless-stopped`, joins the
external `proxy` network, binds `/srv/backup:/srv:ro`, state in `./data`, base URL `/files`.
No published ports. (Confirm the image's flag/env conventions against the pinned tag.)

- [ ] **Step 2 — Add the Caddy route**

Add to the `:8080` site in `stacks/caddy/Caddyfile`, before the `/` handler:

```caddyfile
    handle /files* {
        reverse_proxy filebrowser:80
    }
```

(No `handle_path`: Filebrowser keeps the `/files` base URL. Add a
`/files` → `/files/` redirect if it doesn't normalise itself — the PairDrop lesson.)

- [ ] **Step 3 — Deploy**

```sh
scp -r stacks/filebrowser rahul@192.168.1.60:/tmp/
scp stacks/caddy/Caddyfile rahul@192.168.1.60:/tmp/Caddyfile
ssh rahul@192.168.1.60 '
  sudo mkdir -p /opt/filebrowser && sudo cp -r /tmp/filebrowser/. /opt/filebrowser/
  sudo cp /tmp/Caddyfile /opt/caddy/Caddyfile
  cd /opt/filebrowser && docker compose up -d
  cd /opt/caddy && docker compose up -d --force-recreate
'
```

- [ ] **Step 4 — Verify (REVIEW FOCUS)**

```sh
curl -sk -o /dev/null -w "%{http_code}\n" https://docker-host.tail91459b.ts.net/files
curl -sk https://docker-host.tail91459b.ts.net/files | head -5
```
Expected: **200** and Filebrowser HTML. Also confirm the LAN door is closed
(`ss -ltn` on the VM shows no `:80`/`:8080` beyond Caddy's `127.0.0.1:8090`).

---

## Task 4: Filebrowser first run *(owner)*

- [ ] **Step 1 — Set the admin password** (owner chooses it; set via the container's
  CLI/state on the VM or through the first-login flow — whichever the pinned image
  supports).
- [ ] **Step 2 — Sign in** at `https://docker-host.tail91459b.ts.net/files` and confirm
  `/srv/backup` is browsable and **read-only** (no upload/delete controls).

---

## Task 5: rclone remote + dry run

**Files:** `~/.config/rclone/rclone.conf` (uncommitted).

- [ ] **Step 1 — Add the remote**

```ini
[homelab]
type = sftp
host = docker-host.tail91459b.ts.net
user = rahul
key_file = ~/.ssh/<key>
```

- [ ] **Step 2 — Prove connectivity**

```sh
rclone lsd homelab:/srv/ ; rclone lsd homelab:/srv/backup
```
Expected: `backup` appears.

- [ ] **Step 3 — Dry run (owner reviews)**

```sh
rclone --config ~/.config/rclone/rclone.conf sync \
  --filter-from ~/.config/rclone/scripts/filters.txt \
  --delete-during --delete-excluded --dry-run --stats-one-line \
  ~/ homelab:/srv/backup
```
Expected: a diff of new/changed files, **no `/music` entries**, and a summary
totalling ~212 GiB / ~117k objects to transfer.

---

## Task 6: First full sync

- [ ] **Step 1 — Run it** (drop `--dry-run`; run at home so it goes over the LAN).
- [ ] **Step 2 — Verify (REVIEW FOCUS)**

```sh
rclone size homelab:/srv/backup --human-readable
```
Expected: ≈ **211.87 GiB / 117,164 objects**.

- [ ] **Step 3 — Spot check** a few files through Filebrowser.

---

## Task 7: Wire the timer (dotfiles)

- [ ] **Step 1** — `sync-drive.sh` → `sync-homelab.sh`: destination `homelab:/srv/backup`,
  drop the Google-only flags, update notifications and log.
- [ ] **Step 2** — `sync-drive.{service,timer}` → `sync-homelab.{service,timer}`:
  cadence at 00:00 / 08:00 / 16:00, `Persistent=true`, small `RandomizedDelaySec`, `Nice=`/idle IO.
- [ ] **Step 3** — `systemctl --user daemon-reload`; disable the Drive timer; enable the new one.
- [ ] **Step 4** — Test: `systemctl --user start sync-homelab.service`; confirm a clean, quick run.

---

## Task 8: Dashboard tile

- [ ] **Step 1** — Add a Filebrowser tile to `stacks/homepage/config/services.yaml`
  (`href: https://docker-host.tail91459b.ts.net/files`), deploy, verify the dashboard.

---

## Task 9: Retire Google *(agent + owner)*

- [ ] **Step 1 (agent)** — Remove `[google drive]` from `rclone.conf`; delete the old
  `sync-drive` script/units.
- [ ] **Step 2 (owner)** — Revoke the app in the Google account and delete the
  `framework12` Drive folder **only after** Task 6 verified the mirror.

---

## Task 10: Docs, diagram, commit

- [ ] **Step 1** — `docs/setup.md`: disk, mount, Filebrowser, rclone remote, **restore procedure**.
- [ ] **Step 2** — `docs/access-matrix.md`: Filebrowser row + backup row.
- [ ] **Step 3** — `docs/schemas/homelab.dot`: add Filebrowser + the backup disk + a
  laptop→SFTP edge; `make schemas`.
- [ ] **Step 4** — `README.md`: add `stacks/filebrowser/`.
- [ ] **Step 5** — `AGENTS.md`: rewrite the "no backup system" rule into the real policy.
- [ ] **Step 6** — Fill in the spec's "As built"; commit.

---

## Self-review

- Every phase in the spec's table maps to a task here (0→1, 1→2, 2→3, 3→4, 4→5, 5→6, 6→7, 7→8, 8→9, 9→10).
- The owner's touchpoints are exactly Tasks 4, 5 Step 3, and 9 Step 2.
- The review-focus items are each pinned to a concrete step.
