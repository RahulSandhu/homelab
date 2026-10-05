# Navidrome + Music Share Implementation Plan

> **Superseded in part (2026-09-28):** Task 7's automount became a **manual
> mount**; Task 5's `tailscale serve → localhost:4533` became the Caddy reverse
> proxy (`serve` → `localhost:8090`); and Task 3's `tailscale up --ssh` was
> **reverted** on the VM (`--ssh=false` — its 12-hour browser check breaks
> unattended jobs). See the specs' "As built" notes and `docs/setup.md`. The rest
> of the plan still reflects the build.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the owner's music onto the homelab, shared via Samba and streamed by Navidrome, with the laptop's `~/music` as a live mount usable at home and away.

**Architecture:** A dedicated 50 GB thin virtual disk on the existing `docker-host` VM is formatted and mounted at `/srv/music`. Samba exports it; the VM joins the tailnet (so the share and SSH are reachable anywhere); Navidrome reads `/srv/music` read-only and is published tailnet-only via `tailscale serve`. The laptop automounts the share at `~/music`.

**Tech Stack:** Proxmox VE 9 (`qm`), Debian 13 VM, LVM-thin, ext4, Samba, Tailscale, Docker Compose (Navidrome), CIFS (`cifs-utils`).

**Spec:** `docs/specs/2026-09-28-navidrome-music-share-design.md`

## Global Constraints

- **Never `tailscale funnel`** — `serve` only (tailnet-only).
- **No ports opened on the router.**
- **Images pinned** — Navidrome `deluan/navidrome:0.64.2`. Never `:latest`.
- **`.env` never committed** — only `.env.example`.
- **No backup tooling** (policy unchanged).
- **Data disk:** 50 GB, thin, on `local-lvm`; **ext4 on the whole device** (no partition table).
- **The new disk is `/dev/sdb`.** `/dev/sda` is the OS. Verify the device before `mkfs`; the wrong target destroys the VM.
- **Values** (from the 2026-09-27 spec): host `pve` `192.168.1.50`; VM `docker-host` `192.168.1.60`; tailnet `tail91459b.ts.net`; Vaultwarden `pve.tail91459b.ts.net`; Navidrome `docker-host.tail91459b.ts.net`.

## Review Focus

- **Mount over a network share at `~/music`** with Tailscale off / server down: must be empty, must not hang. Pinned by Task 7's offline test.
- **`mkfs` target:** must be `/dev/sdb`, never `/dev/sda`. Pinned by Task 1 Steps 2–3.
- **Samba exposure:** share must authenticate and must not be reachable off the LAN/tailnet. Pinned by Task 2's `hosts allow` + `smbclient` checks.
- **Read-only for Navidrome:** the app must not write into `/srv/music`. Pinned by Task 4's mount-flag check.
- **Ownership:** library files owned by `rahul` so Navidrome can read them. Pinned by Task 6.

---

## Task 1: Data disk + `/srv/music`

**Files:** `pve` VM config (via `qm`); VM `/etc/fstab`.
**Interfaces:** produces `/srv/music` (ext4, 50 GB) on the VM, mounted persistently by UUID.

- [ ] **Step 1 — Create the disk on the host**

```sh
ssh root@192.168.1.50 'qm set 100 --scsi1 local-lvm:50,discard=on,ssd=1,iothread=1 && qm config 100 | grep scsi1'
```
Expected: a line like `scsi1: local-lvm:vm-100-disk-1,discard=on,iothread=1,size=50G,ssd=1`

- [ ] **Step 2 — Confirm the guest sees it**

```sh
ssh rahul@192.168.1.60 'lsblk -o NAME,SIZE,TYPE,MOUNTPOINT'
```
Expected: `sdb  50G  disk` with no mountpoint. If absent: `ssh root@192.168.1.50 'qm reboot 100'`, wait ~30 s, retry.

- [ ] **Step 3 — Safety check: target is `/dev/sdb` and blank**

```sh
ssh rahul@192.168.1.60 'lsblk -no NAME,SIZE,TYPE /dev/sdb && (sudo blkid /dev/sdb || echo "no filesystem (correct)")'
```
Expected: `sdb 50G disk` and `no filesystem (correct)`. **If it shows `sda` or an existing filesystem, STOP.**

- [ ] **Step 4 — Format ext4 on the whole device**

```sh
ssh rahul@192.168.1.60 'sudo mkfs.ext4 -L music /dev/sdb'
```

- [ ] **Step 5 — Mount by UUID (persistent)**

```sh
ssh rahul@192.168.1.60 '
  sudo mkdir -p /srv/music
  uuid=$(sudo blkid -s UUID -o value /dev/sdb)
  echo "UUID=$uuid /srv/music ext4 defaults,nofail 0 2" | sudo tee -a /etc/fstab
  sudo systemctl daemon-reload
  sudo mount -a
  sudo chown rahul:rahul /srv/music
'
```

- [ ] **Step 6 — Verify**

```sh
ssh rahul@192.168.1.60 'findmnt -no SOURCE,TARGET,FSTYPE /srv/music; df -h /srv/music | tail -1; ls -ld /srv/music'
```
Expected: mounted, ~49 G available, owner `rahul`.

*No repo change; the runbook is updated in Task 8.*

---

## Task 2: Samba share

**Files:** create `stacks/music-share/smb.conf`, `stacks/music-share/README.md`; deploy to VM `/etc/samba/smb.conf`.
**Interfaces:** produces the `music` SMB share authenticated by user `rahul`; the SMB password is generated here and needed by Task 7.

- [ ] **Step 1 — Write the share config in the repo**

Create `stacks/music-share/smb.conf`:

```ini
[global]
   workgroup = WORKGROUP
   server string = docker-host music
   server min protocol = SMB2
   disable netbios = yes
   map to guest = bad user
   log file = /var/log/samba/log.%m

[music]
   path = /srv/music
   browseable = yes
   read only = no
   valid users = rahul
   force user = rahul
   force group = rahul
   create mask = 0644
   directory mask = 0755
   hosts allow = 192.168.1.0/24 100.64.0.0/10
   hosts deny = 0.0.0.0/0
```

Create `stacks/music-share/README.md` describing the share, the `smbpasswd` user, and that only the LAN + tailnet CGNAT range may connect.

- [ ] **Step 2 — Commit**

```sh
git add stacks/music-share && git commit -m "feat: add Samba config for the music share"
```

- [ ] **Step 3 — Install Samba and deploy the config**

```sh
ssh rahul@192.168.1.60 'sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq samba'
scp -q stacks/music-share/smb.conf rahul@192.168.1.60:/tmp/smb.conf
ssh rahul@192.168.1.60 'sudo cp /etc/samba/smb.conf /etc/samba/smb.conf.orig 2>/dev/null; sudo cp /tmp/smb.conf /etc/samba/smb.conf && sudo testparm -s >/dev/null && echo "config OK"'
```

- [ ] **Step 4 — Create the SMB user with a generated password**

```sh
ssh rahul@192.168.1.60 '
  s=$(head -c 24 /dev/urandom | base64 | tr -dc "A-Za-z0-9" | cut -c1-20)
  printf "%s\n%s\n" "$s" "$s" | sudo smbpasswd -s -a rahul >/dev/null
  echo "SMB_PASSWORD=$s"
'
```
Expected: prints `SMB_PASSWORD=<20 chars>`. **Save it — Task 7 needs it.**

- [ ] **Step 5 — Start the service**

```sh
ssh rahul@192.168.1.60 'sudo systemctl restart smbd && sudo systemctl enable smbd >/dev/null && systemctl is-active smbd'
```
Expected: `active`.

- [ ] **Step 6 — Verify the share authenticates and is empty**

```sh
ssh rahul@192.168.1.60 'smbclient -L localhost -U "rahul%<SMB_PASSWORD>" | grep -i music'
ssh rahul@192.168.1.60 'smbclient "//localhost/music" -U "rahul%<SMB_PASSWORD>" -c "ls"'
```
Expected: the `music` share is listed; `ls` returns an empty listing.

---

## Task 3: Put the VM on the tailnet

**Files:** none (system install on the VM).
**Interfaces:** produces tailnet node `docker-host` (`--ssh`), reachable from anywhere.

- [ ] **Step 1 — Install Tailscale on the VM**

```sh
ssh rahul@192.168.1.60 'curl -fsSL https://tailscale.com/install.sh | sh'
```

- [ ] **Step 2 — Start login and capture the URL** *(the owner must approve it)*

```sh
ssh rahul@192.168.1.60 '
  rm -f /tmp/ts-up.log
  setsid nohup tailscale up --ssh --hostname=docker-host >/tmp/ts-up.log 2>&1 </dev/null &
  sleep 8; cat /tmp/ts-up.log
'
```
Expected: prints `https://login.tailscale.com/a/…`. **Give this URL to the owner.**

- [ ] **Step 3 — Verify (after the owner approves)**

```sh
ssh rahul@192.168.1.60 'tailscale status | grep docker-host; tailscale ip -4'
```
Expected: `docker-host` listed, `100.x.y.z` shown.

- [ ] **Step 4 — Owner: disable key expiry for `docker-host`** in <https://login.tailscale.com/admin/machines>.

- [ ] **Step 5 — Verify remote SSH from the laptop**

```sh
ssh -o BatchMode=yes rahul@docker-host 'hostname'
```
Expected: `docker-host`.

---

## Task 4: Navidrome stack

**Files:** create `stacks/navidrome/compose.yaml`, `stacks/navidrome/.env.example`, `stacks/navidrome/README.md`; deploy to VM `/opt/navidrome/`.
**Interfaces:** consumes `/srv/music` (Task 1); produces Navidrome on `localhost:4533` (VM) reading `/music` read-only.

- [ ] **Step 1 — Write `stacks/navidrome/compose.yaml`**

```yaml
name: navidrome

services:
  navidrome:
    image: deluan/navidrome:0.64.2
    container_name: navidrome
    restart: unless-stopped
    env_file: .env
    environment:
      ND_MUSICFOLDER: /music
      ND_DATAFOLDER: /data
    volumes:
      - ./data:/data
      - /srv/music:/music:ro
    ports:
      - "4533:4533"
```

- [ ] **Step 2 — Write `stacks/navidrome/.env.example`**

```dotenv
# Navidrome — copy to .env
ND_SCANSCHEDULE=@every 1h
ND_LOGLEVEL=info
# ND_BASEURL=
# ND_LASTFM_APIKEY=
# ND_LASTFM_SECRET=
```

- [ ] **Step 3 — Write `stacks/navidrome/README.md`** (what it is, the ro music mount, `docker compose up -d`, update via pin bump).

- [ ] **Step 4 — Commit**

```sh
git add stacks/navidrome && git commit -m "feat: add Navidrome stack"
```

- [ ] **Step 5 — Deploy**

```sh
ssh rahul@192.168.1.60 'mkdir -p /opt/navidrome'
scp -q stacks/navidrome/compose.yaml stacks/navidrome/.env.example rahul@192.168.1.60:/opt/navidrome/
ssh rahul@192.168.1.60 'cd /opt/navidrome && cp -n .env.example .env && docker compose up -d'
```

- [ ] **Step 6 — Verify the container and the read-only mount**

```sh
ssh rahul@192.168.1.60 'cd /opt/navidrome && docker compose ps'
ssh rahul@192.168.1.60 'docker inspect navidrome --format "{{range .Mounts}}{{.Source}} -> {{.Destination}} rw={{.RW}}{{println}}{{end}}"'
ssh rahul@192.168.1.60 'curl -s -o /dev/null -w "ping: %{http_code}\n" http://localhost:4533/ping'
```
Expected: container `Up`; `/srv/music -> /music rw=false`; `ping: 200`.

---

## Task 5: Expose Navidrome over Tailscale

**Files:** none.
**Interfaces:** consumes `localhost:4533` (Task 4); produces `https://docker-host.tail91459b.ts.net`.

- [ ] **Step 1 — Configure serve on the VM**

```sh
ssh rahul@192.168.1.60 'tailscale serve --bg http://localhost:4533 && tailscale serve status'
```
Expected: `https://docker-host.tail91459b.ts.net (tailnet only)` → `proxy http://localhost:4533`.

- [ ] **Step 2 — Verify from the VM and the laptop**

```sh
ssh rahul@192.168.1.60 'curl -sk -o /dev/null -w "%{http_code}\n" https://docker-host.tail91459b.ts.net/'
curl -sk -o /dev/null -w "%{http_code}\n" https://docker-host.tail91459b.ts.net/
```
Expected: `200` both times.

---

## Task 6: Migrate the music

**Files:** none (data).
**Interfaces:** consumes `~/music` (laptop) and `/srv/music` (Task 1); produces the library on the server and a Navidrome scan.

- [ ] **Step 1 — Copy the library to the server**

```sh
rsync -a --info=progress2 ~/music/ rahul@docker-host:/srv/music/
```

- [ ] **Step 2 — Verify counts and size match**

```sh
echo -n "local files:  "; find ~/music -type f | wc -l
ssh rahul@docker-host 'printf "remote files: "; find /srv/music -type f | wc -l; du -sh /srv/music'
```
Expected: both `47`; remote ≈ 202 M.

- [ ] **Step 3 — Ensure ownership is correct**

```sh
ssh rahul@docker-host 'sudo chown -R rahul:rahul /srv/music && ls -l /srv/music | head -3'
```

- [ ] **Step 4 — Trigger a scan and confirm Navidrome sees the tracks**

```sh
ssh rahul@docker-host 'cd /opt/navidrome && docker compose restart && sleep 8 && docker compose logs --tail=30 navidrome | grep -iE "scan|track|found"'
```
Expected: log lines reporting the scan and the 47 tracks.

---

## Task 7: Mount `~/music` on the laptop *(owner's column — needs sudo)*

**Files:** create `~/.smbcredentials`; modify `/etc/fstab` on the laptop.
**Interfaces:** consumes the `music` share (Task 2) and the SMB password; produces `~/music` as a CIFS automount.

- [ ] **Step 1 — Install the CIFS client**

```sh
sudo pacman -S --needed cifs-utils
```

- [ ] **Step 2 — Store the credentials**

```sh
umask 077
printf 'username=rahul\npassword=<SMB_PASSWORD>\n' > ~/.smbcredentials
```

- [ ] **Step 3 — Add the fstab entry**

Append to `/etc/fstab`:

```
//docker-host/music  /home/rahul/music  cifs  credentials=/home/rahul/.smbcredentials,uid=1000,gid=1000,file_mode=0644,dir_mode=0755,nofail,_netdev,x-systemd.automount,x-systemd.idle-timeout=60  0 0
```

- [ ] **Step 4 — Activate and verify**

```sh
sudo systemctl daemon-reload
sudo systemctl restart home-rahul-music.automount
ls ~/music | head
findmnt -no SOURCE,TARGET,FSTYPE ~/music
```
Expected: the 47 files are listed; `//docker-host/music … cifs` mounted.

- [ ] **Step 5 — Offline behaviour test (must not hang)**

```sh
sudo tailscale down
timeout 5 ls ~/music; echo "exit=$?"
sudo tailscale up
```
Expected: empty listing, `exit=0` quickly (no hang). Restore Tailscale afterwards.

- [ ] **Step 6 — Note the local originals**

The pre-existing `~/music` files are now hidden beneath the mount. To reclaim the ~202 MB, `sudo umount ~/music && rm -f ~/music/*` (only after Steps 2–4 confirm the server copy).

---

## Task 8: Update docs and the diagram

**Files:** modify `docs/setup.md`, `docs/schemas/homelab.dot`, `docs/specs/2026-09-28-navidrome-music-share-design.md`, `AGENTS.md`; create `stacks/music-share/README.md` if not already.

- [ ] **Step 1 — Runbook:** add a "Phase: Navidrome + music share" section covering Tasks 1–7 and the disk-growth procedure (`qm resize 100 scsi1 <size>` + `resize2fs /dev/sdb`).

- [ ] **Step 2 — Diagram:** in `docs/schemas/homelab.dot`, add the Navidrome container beside Vaultwarden, an annotation for `/srv/music` + the Samba share, and a tailnet node for `docker-host`. Keep the established style.

- [ ] **Step 3 — Render and inspect**

```sh
make schemas
```
Expected: `tmp/homelab.png` regenerates without warnings; open it and confirm the new elements are legible.

- [ ] **Step 4 — Spec status:** set the 2026-09-28 spec `Status` to *Implemented* and note any deviations.

- [ ] **Step 5 — AGENTS.md:** add `stacks/navidrome/` and `stacks/music-share/` to the layout, and note the VM is now a tailnet node.

- [ ] **Step 6 — Commit**

```sh
git add docs AGENTS.md && git commit -m "docs: document Navidrome + music share; update diagram"
```

---

## Self-review

- **Spec coverage:** storage (T1), Samba (T2), tailnet (T3), Navidrome (T4), exposure (T5), migration (T6), laptop mount (T7), docs/diagram (T8) — all spec sections mapped.
- **Placeholders:** none; every step has exact commands.
- **Consistency:** `/srv/music`, `docker-host`, port `4533`, `docker-host.tail91459b.ts.net`, image `deluan/navidrome:0.64.2` used identically throughout.
- **Review Focus:** each line has an owning task and a test (T1-2/3, T2-6, T4-6, T6-2, T7-5).
