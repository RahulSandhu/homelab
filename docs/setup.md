# Homelab setup runbook

> **Status: BUILT AND RUNNING (2026-09-27, extended through 2026-10-05).** This
> runbook reflects what was actually executed, including the gotchas we hit. The
> values below are this environment's real values, not placeholders.

End state: a Proxmox host on the LAN running one Debian VM that hosts the
service stack (dashboard, Navidrome, PairDrop, Filebrowser, AdGuard DNS, Stirling
PDF, MeTube) plus Vaultwarden, all on the VM — reachable from anywhere over
Tailscale and from nowhere else, with Zipline and read-only Filebrowser share
links as the two deliberate public exceptions.

## This environment (as built)

| Piece | Value |
| --- | --- |
| Proxmox host | `pve` · LAN `192.168.1.50` · FQDN `pve.homelab.lan` |
| Proxmox version | VE **9.2** (Debian 13 "trixie" base), kernel `7.0.14-pve` |
| VM | `docker-host` (VMID 100) · LAN `192.168.1.60` · **Debian 13** |
| VM spec | 2 vCPU · **6 GB** RAM · 32 GB disk (raised from 4 GB with MeTube) |
| Gateway / DNS | `192.168.1.1` |
| Tailnet | `tail91459b.ts.net` |
| Tailscale nodes | `pve` (`100.117.51.55`) · `docker-host` (`100.74.164.49`) · `zipline` (`100.78.80.41`) · `fileshare` (`100.123.26.36`) · `archlinux` · `s24-de-rahul` |
| URLs | dashboard `https://docker-host.tail91459b.ts.net/` (+ `/navidrome`, `/pairdrop/`, `/files/`, `/metube/`) · AdGuard `:8443` · Stirling `:10000` · Vaultwarden `https://pve.tail91459b.ts.net` · Zipline `https://zipline.tail91459b.ts.net` (**public**) · Filebrowser shares `https://fileshare.tail91459b.ts.net` (**public**) |
| Vaultwarden | `vaultwarden/server:1.37.3` · port `8080` → `80` · data in `/opt/vaultwarden/data` |
| Navidrome | `deluan/navidrome:0.64.2` · `ND_BASEURL=/navidrome` · `https://docker-host.tail91459b.ts.net/navidrome` |
| Homepage | `ghcr.io/gethomepage/homepage:v2.4.0` · dashboard at `/` |
| PairDrop | `ghcr.io/schlagmichdoch/pairdrop:v1.11.2` · `/pairdrop/` |
| Filebrowser | `gtstef/filebrowser:1.5.6-stable` · `/files/` — read-only browse of the backup |
| Backup mirror | laptop `$HOME` → `/srv/backup` (350 GB disk) via rclone `sftp`; `sync-homelab.timer` (00/08/16) |
| AdGuard Home | `adguard/adguardhome:v0.107.79` · DNS `100.74.164.49:53` (tailnet only) · UI `:8443` |
| Stirling PDF | `stirlingtools/stirling-pdf:3.0.0` · `…:10000/` · stateless PDF toolbox |
| Zipline | `ghcr.io/diced/zipline:4.8.0` + `postgres:16` + a Tailscale sidecar · **public** at `zipline.tail91459b.ts.net` |
| MeTube | `ghcr.io/alexta69/metube:2026.09.28` · `/metube/` · yt-dlp downloads on a 25 GB staging disk |
| Caddy | `caddy:2.11.4-alpine` · reverse proxy, `127.0.0.1:8090` |
| Music share | Samba `//docker-host/music` ← `/srv/music` (50 GB disk); mounted **manually** from the laptop |

## The rules (do not break)

- **Never funnel `docker-host`.** `serve` is the door for everything — the two
  deliberate exceptions are the **`zipline`** and **`fileshare`** nodes (see their
  sections), each funneled on purpose, IP-scoped, and reversibly.
- **Keep images pinned.** No `:latest`.
- **`.env` never gets committed.** Only `.env.example` is tracked.
- **The homelab *is* the laptop's backup** (a one-way rclone mirror at
  `/srv/backup`). The homelab itself isn't backed up: VM snapshots before updates
  plus a periodic Vaultwarden vault export are its safety net.

---

## Phase 0 — Prerequisites

- The mini PC, a keyboard + monitor (only for the install, then never again).
- One USB stick, 2 GB or larger.
- A free Tailscale account: <https://login.tailscale.com>.
- The mini PC wired to a router LAN port.

## Phase 1 — Install Proxmox VE 9

1. Download `proxmox-ve_9.2-1.iso` from <https://www.proxmox.com/en/downloads>.
   (Proxmox serves ISOs over plain HTTP; verify the SHA256 afterwards.)
2. Write it to the USB stick:

   ```sh
   lsblk                                          # identify the USB, e.g. /dev/sda
   sudo dd if=proxmox-ve_9.2-1.iso of=/dev/sda bs=4M status=progress conv=fsync
   ```

3. Boot the mini PC from the USB. On the BOSGAME E5, the `Delete` key is flaky:
   if it won't enter the BIOS, let Windows boot and use **Troubleshoot →
   Advanced options → UEFI Firmware Settings**, or run `shutdown /r /fw /t 0`
   from a `Shift+F10` command prompt.
4. In the BIOS, while you're there: **disable Fast Boot**, set **Auto Power On →
   On**, and confirm **SVM Mode** is Enabled (needed for VMs).
5. In the installer choose **Install Proxmox VE (Graphical)** and set:
   - **Filesystem:** `ext4` (LVM-thin) · **Disk:** the 1 TB NVMe
   - **Hostname:** `pve`, domain `homelab.lan`
   - **IP:** `192.168.1.50` / `24` · gateway `192.168.1.1` · DNS `192.168.1.1`
   - A strong root password + your admin email.
6. Reboot and **remove the USB**.

## Phase 2 — Host baseline (free repo + updates)

The host is Debian 13, so apt sources are deb822 `.sources` files:

```sh
cat > /etc/apt/sources.list.d/pve-no-subscription.sources <<'EOF'
Types: deb
URIs: http://download.proxmox.com/debian/pve
Suites: trixie
Components: pve-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF

# Disable the paid repos (we have no subscription):
mv /etc/apt/sources.list.d/pve-enterprise.sources /etc/apt/sources.list.d/pve-enterprise.sources.disabled
mv /etc/apt/sources.list.d/ceph.sources           /etc/apt/sources.list.d/ceph.sources.disabled

apt update && apt full-upgrade -y
reboot                                   # a new kernel lands here
```

Optional: reserve `192.168.1.50` on the router so it never moves.

## Phase 3 — Tailscale on the host

The host is the network's single edge: it carries Tailscale and reverse-proxies
into the VM.

```sh
curl -fsSL https://tailscale.com/install.sh | sh
tailscale up --ssh --hostname=pve
tailscale status
```

Then in the admin console:

1. <https://login.tailscale.com/admin/dns> → enable **MagicDNS** and
   **HTTPS Certificates**.
2. <https://login.tailscale.com/admin/machines> → `pve` → **⋯** → **Disable key
   expiry** (so the headless server never silently drops off the tailnet).

## Phase 4 — Create the Debian 13 VM (cloud image + cloud-init)

No interactive install: boot Debian's official cloud image and let cloud-init
configure the user, SSH key, and network. (We ran this from the host over SSH.)

```sh
cd /var/lib/vz/template/iso
curl -fLO https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.qcow2

qm create 100 --name docker-host --ostype l26 --memory 4096 --cores 2 --cpu host \
  --net0 virtio,bridge=vmbr0 --scsihw virtio-scsi-single --agent enabled=1 \
  --serial0 socket --vga serial0 --onboot 1

qm importdisk 100 debian-13-genericcloud-amd64.qcow2 local-lvm
qm set 100 --scsi0 local-lvm:vm-100-disk-0,discard=on,ssd=1,iothread=1
qm set 100 --ide2 local-lvm:cloudinit
qm set 100 --boot order=scsi0

# Inject your SSH key so you never need a console again:
#   (from the desktop) ssh root@192.168.1.50 'cat > /root/vm-key.pub' < ~/.ssh/id_ed25519.pub
qm set 100 --ciuser rahul --sshkeys /root/vm-key.pub
qm set 100 --ipconfig0 ip=192.168.1.60/24,gw=192.168.1.1
qm set 100 --nameserver 192.168.1.1 --ciupgrade 0

qm resize 100 scsi0 32G
qm start 100
```

> **Later change:** the VM was raised from **4 GB to 6 GB** when MeTube was added
> (`qm set 100 --memory 6144`, then a reboot), and `qemu-guest-agent` was installed
> so reboots are graceful rather than hard resets.

> **Gotcha — cloud-init can wipe the SSH host keys on boot.** The VM boots from a
> cloud-init seed (`sr0`, NoCloud). If cloud-init ever treats a boot as a **new
> instance** (its `ssh` module defaults to `ssh_deletekeys: true`), it **deletes
> and regenerates the host keys**. Every `known_hosts` entry for `docker-host`
> then goes stale, and SSH / `rsync` / the **rclone backup** fail with
> *"REMOTE HOST IDENTIFICATION HAS CHANGED"*. This happened on the 2026-10-03
> cold boot after a power cut. Prevented on the VM with:
>
> ```sh
> echo 'ssh_deletekeys: false' | sudo tee /etc/cloud/cloud.cfg.d/99-preserve-ssh-hostkeys.cfg
> ```
>
> After a genuine key change, refresh the laptop's entries:
> `ssh-keygen -R docker-host && ssh-keyscan -H docker-host >> ~/.ssh/known_hosts`.

## Phase 5 — Docker on the VM

```sh
ssh rahul@192.168.1.60
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | sudo tee /etc/apt/keyrings/docker.asc >/dev/null
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/debian $(. /etc/os-release && echo $VERSION_CODENAME) stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker "$USER"
```

## Phase 6 — Deploy Vaultwarden

```sh
sudo mkdir -p /opt/vaultwarden && sudo chown "$USER" /opt/vaultwarden
# from the desktop:
#   scp stacks/vaultwarden/compose.yaml stacks/vaultwarden/.env.example rahul@192.168.1.60:/opt/vaultwarden/
cd /opt/vaultwarden
cp .env.example .env
```

Generate the admin token. **This needs a real terminal** — `docker run` without
a TTY panics with `No such device or address`. Run it interactively:

```sh
docker run --rm -it vaultwarden/server:1.37.3 /vaultwarden hash
```

Then edit `.env`: set `DOMAIN=https://pve.tail91459b.ts.net`, `TZ`, and paste the
`ADMIN_TOKEN`.

> **Gotcha #1 — escape `$` as `$$`.** Docker Compose interpolates `$` inside
> `.env`, so an unescaped `$argon2id$v=19$...` gets mangled and Vaultwarden falls
> back to a plain-text token. Write it as `$$argon2id$$v=19$$...`. If the logs
> say *"You are using a plain text ADMIN_TOKEN"*, you forgot.

```sh
docker compose up -d
docker compose logs -f
```

## Phase 7 — Expose it over Tailscale (on the host)

```sh
tailscale serve --bg http://192.168.1.60:8080
tailscale serve status
```

Result:

```
https://pve.tail91459b.ts.net (tailnet only)
|-- / proxy http://192.168.1.60:8080
```

`serve` is tailnet-only. **Never `funnel`.**

## Phase 8 — First account, then lock down

1. From a device on the tailnet, open `https://pve.tail91459b.ts.net`.
2. **Immediately** create your account, then enable 2FA (Settings → Security).
3. Close signups:

   ```sh
   sed -i 's/^SIGNUPS_ALLOWED=.*/SIGNUPS_ALLOWED=false/' .env
   docker compose up -d
   ```

4. In the Bitwarden clients (desktop, phone, browser extension): choose
   **Self-hosted**, set the server URL to `https://pve.tail91459b.ts.net`.
   The device must be signed in to Tailscale.
5. To migrate an existing Bitwarden vault: **Export** it (`.json`) from Bitwarden,
   **Import** it in the Vaultwarden web vault (Tools → Import), then **securely
   delete** the export — it holds every password in plain text.

## Phase 9 — Verify

```sh
# host
pveversion
tailscale status
tailscale serve status
curl -sk -o /dev/null -w '%{http_code}\n' https://pve.tail91459b.ts.net/

# VM
cd /opt/vaultwarden && docker compose ps
docker compose logs --tail=50 vaultwarden
```

- The web vault loads and you can log in.
- The Bitwarden apps sync.
- With Tailscale **off**, the URL is unreachable — this is the point.

## Phase 10 — Maintenance & recovery

```sh
# on the host, before an update
qm snapshot 100 pre-update-$(date +%F)
# on the VM
cd /opt/vaultwarden && docker compose pull && docker compose up -d
```

If it breaks: `qm rollback 100 pre-update-<date>`. If the VM is lost entirely,
rebuild it from Phases 4–7 — this repo is the source of truth.

Keep a periodic **vault export** on your laptop as the last line of defence.

---

## Adding a service — worked example: Navidrome + music share (2026-09-28)

The pattern to repeat for future services. Full detail in
`docs/specs/2026-09-28-navidrome-music-share-design.md`.

### Storage

A dedicated **50 GB thin disk** on the VM holds the library:

```sh
# on the host
qm set 100 --scsi1 local-lvm:50,discard=on,ssd=1,iothread=1
# in the VM — confirm it appears as /dev/sdb BEFORE mkfs (sda is the OS!)
sudo mkfs.ext4 -L music /dev/sdb
sudo mkdir -p /srv/music
echo "UUID=$(sudo blkid -s UUID -o value /dev/sdb) /srv/music ext4 defaults,nofail 0 2" | sudo tee -a /etc/fstab
sudo systemctl daemon-reload && sudo mount -a
```

Grow it later: `qm resize 100 scsi1 100G` then `sudo resize2fs /dev/sdb`.

### Tailscale on the VM

```sh
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up --hostname=docker-host          # NOTE: deliberately no --ssh
```

Disable key expiry for `docker-host` in the admin console. The share and SSH are
now reachable from anywhere.

> **Do not enable Tailscale SSH here (`--ssh`).** Its `check` action demands a
> browser re-authentication every 12 h, which silently breaks the backup timer.
> Tailnet SSH uses the VM's own sshd and your key instead. To turn it back off:
> `sudo tailscale set --ssh=false`.

### Samba share

`stacks/music-share/smb.conf` → `/etc/samba/smb.conf`; create the user with
`sudo smbpasswd -a rahul` (see that stack's README).

### Navidrome

`stacks/navidrome/` → `/opt/navidrome/`; `docker compose up -d`. It reads
`/srv/music` **read-only**, and is reached at **`/navidrome`** through Caddy.

> **`tailscale serve` points at Caddy, not at a service.** Never re-point it at an
> individual container — add a route to `stacks/caddy/Caddyfile` instead (see
> [Reverse proxy + dashboard + file sharing](#reverse-proxy--dashboard--file-sharing-2026-09-28)).

### Mounting the library on the laptop (manual, on demand)

Samba is kept, but the laptop does **not** automount it — mounting is done
**manually, when you want it**. The fstab/automount approach was removed because
systemd's mount **start-limit** trips after repeated failures while offline,
leaving `~/music` permanently empty until a manual reset (see the spec's "As
built" notes). Manual commands carry no such state.

`~/.smbcredentials` (chmod 600) holds the SMB password:

```
username=rahul
password=<SMB password>
```

```sh
# MOUNT  (over the tailnet; swap `docker-host` for `192.168.1.60` to use the LAN)
sudo mount -t cifs //docker-host/music /home/rahul/music \
  -o credentials=/home/rahul/.smbcredentials,uid=1000,gid=1000,file_mode=0644,dir_mode=0755,soft,echo_interval=5

# UNMOUNT
sudo umount /home/rahul/music
```

> **CIFS gotchas:** `timeo`/`retrans` are **NFS** options — cifs rejects them with
> `mount error(22): Invalid argument`. The cifs timeout knob is **`echo_interval`**
> (an unresponsive server is detected at ~3× its value). With Tailscale off a
> mount attempt fails fast, because the name won't resolve.

### Adding music

Copy files into `/srv/music` over SSH, then have Navidrome scan:

```sh
# single file
scp ~/Downloads/song.m4a rahul@docker-host:/srv/music/
# a folder
rsync -av ~/Downloads/album/ rahul@docker-host:/srv/music/
# scan now (otherwise Navidrome scans hourly)
ssh rahul@docker-host 'cd /opt/navidrome && docker compose restart'
```

---

## Adding a VM — Windows 10 (on-demand)

A **cold** Windows VM for occasional use: off by default, started when needed
(0 GB RAM while stopped). See `vms/windows/` for the create script and notes.

```sh
# 1) put the ISO on the host
scp ~/downloads/Win10_22H2_EnglishInternational_x64v1.iso \
    root@192.168.1.50:/var/lib/vz/template/iso/
# 2) create the VM
ssh root@192.168.1.50 \
  'ISO=local:iso/Win10_22H2_EnglishInternational_x64v1.iso bash -s' < vms/windows/create.sh
# 3) start it and install from the Proxmox Console (choose Windows 10 Pro)
ssh root@192.168.1.50 'qm start 101'
```

> **After installing, set the boot order to the disk** — otherwise the next
> reboot boots the installer again (the CD was first):
> ```sh
> ssh root@192.168.1.50 'qm set 101 --boot order=sata0'
> ```

Run it on demand:

```sh
ssh root@pve 'qm start 101'       # turn on
ssh root@pve 'qm shutdown 101'    # turn off (frees ~4 GB)
```

**Access:** the **Proxmox Console** (`https://pve.tail91459b.ts.net:8006` → VM
`windows` → Console) works from anywhere with **no setup inside Windows**. **RDP
is optional** (needs Windows Pro + Tailscale inside Windows) for a smoother
session. Documented in `vms/windows/README.md`.

**Why SATA + e1000:** Windows Setup needs **no drivers**. (virtio is faster but
requires a mid-install "Load driver" step.)

---

## Reverse proxy + dashboard + file sharing (2026-09-28)

`docker-host`'s web services sit behind **Caddy** (path routing), with a
**Homepage** dashboard at the root. `tailscale serve` on the VM now points at
Caddy instead of a single service.

```sh
# on the VM — 443 → Caddy
sudo tailscale serve --bg http://localhost:8090
```

| URL | Service |
| --- | --- |
| `https://docker-host.tail91459b.ts.net/` | Homepage dashboard |
| `https://docker-host.tail91459b.ts.net/navidrome` | Navidrome (`ND_BASEURL=/navidrome`) |
| `https://docker-host.tail91459b.ts.net/pairdrop/` | PairDrop |
| `https://docker-host.tail91459b.ts.net/files/` | Filebrowser (read-only backup view) |
| `https://docker-host.tail91459b.ts.net/metube/` | MeTube (`yt-dlp` downloads) |
| `https://pve.tail91459b.ts.net` | Vaultwarden — **unchanged** (it can't do subpaths) |

**Adding a service:** append a route to `stacks/caddy/Caddyfile`, e.g.

```caddyfile
handle_path /jellyfin* { reverse_proxy jellyfin:8096 }
```

then join the service to the external **`proxy`** Docker network and
`docker compose restart caddy`.

> **Trailing-slash gotcha:** apps with *relative* asset paths (PairDrop) must be
> reached with a trailing slash (`/pairdrop/`), or their CSS/JS resolve at the
> root. Caddy redirects `/pairdrop` → `/pairdrop/` for this reason.

**LAN doors are closed:** Caddy binds `127.0.0.1:8090` and the services publish
no host ports — the tailnet is the only way in. *(Vaultwarden is the exception:
`pve` proxies to it over the LAN.)*

---

## Laptop backup destination (2026-09-28)

The laptop's `$HOME` is mirrored **one-way** onto the VM — the homelab is now the
laptop's backup destination, and **Google Drive is retired**. It is a **mirror,
not a history**: `--delete-during --delete-excluded` means deletions and renames
propagate.

```sh
# on the host — add a 350 GB disk to the VM
qm set 100 --scsi2 local-lvm:350,discard=on,ssd=1,iothread=1

# in the VM — confirm it is /dev/sdc BEFORE mkfs (sda = OS, sdb = music)
lsblk
sudo mkfs.ext4 -L backup /dev/sdc
sudo mkdir -p /srv/backup
echo "UUID=$(sudo blkid -s UUID -o value /dev/sdc) /srv/backup ext4 defaults,nofail 0 2" | sudo tee -a /etc/fstab
sudo systemctl daemon-reload && sudo mount -a
sudo chown rahul:rahul /srv/backup && sudo chmod 750 /srv/backup
```

**Transport — SFTP on the tailnet** (no new service, no new port). The laptop's
remote in `~/.config/rclone/rclone.conf`:

```ini
[homelab]
type = sftp
host = docker-host.tail91459b.ts.net
user = rahul
key_file = /home/rahul/.ssh/id_ed25519
known_hosts_file = /home/rahul/.ssh/known_hosts
```

**Schedule:** the user units `sync-homelab.timer` → `sync-homelab.service` run
`sync-homelab.sh` at **00:00, 08:00 and 16:00**, using `filters.txt`.

> **Tailscale SSH must stay OFF on `docker-host`.** Tailscale SSH's `check` action
> asks a human to re-authenticate in a browser every 12 h — an unattended backup
> can't. `sudo tailscale set --ssh=false` on the VM makes tailnet SSH use the
> VM's own sshd with your key (reversible with `--ssh=true`).

> **Filter changes purge the destination** (`--delete-excluded`). Decide filters
> before trusting the mirror. `.rustup` (65k files) and `/music` are excluded.

**Restore:**

```sh
# browse/download via Filebrowser → https://docker-host.tail91459b.ts.net/files/
rclone copy homelab:/srv/backup/desktop/projects/foo ~/desktop/projects/foo   # pull a folder back
rclone size homelab:/srv/backup --human-readable                              # sanity-check the mirror
```

**GUI:** `stacks/filebrowser/` (FileBrowser Quantum) serves `/srv/backup`
**read-only** at `/files/`, behind Caddy, tailnet-only. (The original
`filebrowser/filebrowser` was archived 2026-09-01 — Quantum is the maintained
fork.)

---

## AdGuard Home — tailnet-only DNS (2026-09-28)

Ad/tracker blocking for the **owner's tailnet devices**. **No router and no DHCP
changes** — the LAN, and the family's internet, are untouched.

Whole-home blocking is *impossible* here: the Livebox's DNS page is operator-locked
(*"no se pueden modificar en el router"*), so filtering every LAN device would mean
taking over DHCP — explicitly rejected.

```sh
# on the VM
sudo mkdir -p /opt/adguard/work /opt/adguard/conf
# (scp the stack across, then:)
cd /opt/adguard && sudo docker compose up -d

# publish the admin UI on the tailnet
sudo tailscale serve --bg --https=8443 http://127.0.0.1:3000
```

| | |
| --- | --- |
| DNS | `100.74.164.49:53` (tcp + udp) — **tailnet IP only**, so there is no LAN door |
| Admin UI | `https://docker-host.tail91459b.ts.net:8443` |
| Tailnet wiring | admin console → **DNS → Nameservers** → global nameserver `100.74.164.49` + *Override local DNS* |

`tailscale serve` only permits ports 443 / 8443 / 10000 (443 is Caddy's), and
AdGuard's UI has no subpath support — hence a port of its own rather than a Caddy
route.

> **Cold-boot race.** DNS is published on the VM's *tailnet* IP, so if Docker
> (`restart: unless-stopped`) starts AdGuard **before** Tailscale assigns
> `100.74.164.49` — which it can, by ~90 s on a cold boot after a power cut — the
> port is never programmed and the **whole tailnet loses DNS** (`tailscale
> status` says *"can't reach the configured DNS servers"*). The repo ships
> `stacks/adguard/adguard-ensure.{service,timer}` to repair this automatically.
> Manual fix: `cd /opt/adguard && sudo docker compose up -d --force-recreate
> adguard`, then confirm `docker port adguard` shows `100.74.164.49:53`.

> In the UI, set **Upstream DNS servers** to a DoH provider (e.g.
> `https://dns.quad9.net/dns-query`, `https://dns.cloudflare.com/dns-query`).
> Otherwise it inherits the container's resolver — your ISP, in plaintext.

**Verifying:** the **Query log** in the UI shows live requests and blocked hits.
`doubleclick.net` should resolve to `0.0.0.0` while `example.com` resolves normally.

---

## Stirling PDF — PDF toolbox (2026-09-28)

A self-hosted PDF toolbox: merge, split, compress, rotate, **OCR**, convert,
sign, redact, protect. **Stateless** — files are processed in temp and deleted;
only its settings persist, so there is nothing to back up or leak.

```sh
sudo mkdir -p /opt/stirling-pdf/data
# (scp the stack across, then:)
cd /opt/stirling-pdf && sudo docker compose up -d
sudo tailscale serve --bg --https=10000 http://127.0.0.1:8081
```

| | |
| --- | --- |
| URL | `https://docker-host.tail91459b.ts.net:10000/` |
| Port | `127.0.0.1:8081` published (localhost only — **no LAN door**) |

> **It must be served at a URL root.** Its UI hardcodes `<base href="/" />`, so a
> Caddy subpath (`/pdf`) breaks every asset — the same constraint as Vaultwarden
> and AdGuard. `serve` permits only 443 / 8443 / 10000, so Stirling takes **10000**.

---

## Zipline — public file sharing (2026-09-28)

One of **two public services**. Upload a file, get a short link anyone can open;
recipients need no account. Uploading requires the owner's login (registration is
OFF); links can expire, be password-protected, or be limited to N downloads.

It runs on its **own tailnet node** (a Tailscale sidecar) so the public funnel is
scoped to that node alone — nothing else is ever exposed.

```sh
sudo mkdir -p /opt/zipline && cd /opt/zipline
cp .env.example .env      # fill CORE_SECRET + POSTGRESQL_PASSWORD + TS_AUTHKEY
sudo docker compose up -d
```

| | |
| --- | --- |
| URL | `https://zipline.tail91459b.ts.net` — **public** |
| Storage | `/srv/zipline` — dedicated 50 GB disk (uploads + Postgres) |
| Node | `zipline` (`100.78.80.41`) — one of the two nodes allowed to be funneled |

**Going public / private:**

```sh
docker exec zipline-ts tailscale funnel --bg --https=443 http://127.0.0.1:3000   # on
docker exec zipline-ts tailscale funnel --https=443 off                          # off
```

> **Never funnel `docker-host`.** And verifying from a tailnet device proves
> nothing (both URLs resolve) — test from a phone with Tailscale **off**.

---

## Public Filebrowser share links (2026-10-05)

Give an **off-tailnet** recipient a read-only link to a folder in `/srv/backup`,
served by the existing Filebrowser through a **share-only Caddy gate** on its own
funneled node. No data is copied — the folder is served in place. The login page
and the rest of the backup stay private (only `/files/public/*` is public).

```sh
# stack lives at /opt/filebrowser-share (Tailscale sidecar + Caddy gate)
sudo mkdir -p /opt/filebrowser-share && cd /opt/filebrowser-share
cp .env.example .env      # fill TS_AUTHKEY (reusable ON, ephemeral OFF, no tags)
sudo mkdir -p ts-state
sudo docker compose up -d

# tailnet-only, then public — scoped to the `fileshare` node only
docker exec fileshare-ts tailscale serve  --bg --https=443 http://127.0.0.1:8080   # tailnet
docker exec fileshare-ts tailscale funnel --bg --https=443 http://127.0.0.1:8080   # public
docker exec fileshare-ts tailscale funnel --https=443 off                          # revert
```

| | |
| --- | --- |
| Share URL | `https://fileshare.tail91459b.ts.net/files/public/share/<hash>` |
| Internal path | unchanged: `https://docker-host.tail91459b.ts.net/files/` |
| Node | `fileshare` (`100.123.26.36`) — the **second** funneled node |
| Gate | Caddy `share-gate` — allows only `/files/public/*`, `404` otherwise |
| Source | a live subfolder of `/srv/backup`, read-only (`ro` mount + permissions) |

The tailnet policy's `nodeAttrs` grants `funnel` to this node's IP **and** Zipline's.

To hand out a link: in Filebrowser (over the tailnet), share the folder (the
account needs the **Share** permission), then give the URL with the host swapped
to `fileshare.tail91459b.ts.net`. Verified from off-tailnet: the public share
paths return `200` while `/files/login` and `/files/api/*` return `404`.

> **Never funnel `docker-host`.** Test from a device with Tailscale **off** — a
> tailnet device proves nothing (both URLs resolve).

---

## MeTube — video downloads (2026-09-28)

A web UI for `yt-dlp`: paste a link and the **server** downloads it (playlists,
channels and subscriptions included). Tailnet-only at
`https://docker-host.tail91459b.ts.net/metube/`.

The intended workflow: download on the server → click **download** in the UI (with
your browser's *"always ask where to save"* you get a normal save dialog). MeTube
then tidies itself: a job leaves the Completed list 24 h after it finishes and, with
`DELETE_FILE_ON_TRASHCAN=true`, its **file is deleted from the disk** too. Clearing a
job by hand does the same immediately — the staging disk stays near-empty.

| | |
| --- | --- |
| URL | `https://docker-host.tail91459b.ts.net/metube/` |
| Storage | `/srv/metube` — a 25 GB staging disk (deliberately small) |

> `CLEAR_COMPLETED_AFTER` is in **seconds** (`86400` = 24 h). Combined with
> `DELETE_FILE_ON_TRASHCAN=true` it also deletes the file, so a job you never
> collected inside the window is removed with its row — keep the window generous.

> ⚠️ **The one service that needs regular updates.** `yt-dlp` must keep up with the
> sites, and MeTube publishes a new image per `yt-dlp` release. Bump the tag every
> few weeks (`docker compose pull && docker compose up -d`), or set
> `YTDL_NIGHTLY_UPDATE_TIME` to self-update daily instead.

> 🧹 **Cleanup is built into MeTube.** Completed jobs (and their files) auto-expire
> after 24 h; there is no separate script or timer. Details in
> [`stacks/metube/README.md`](../../stacks/metube/README.md).

> 🍪 **Cookies for age checks.** MeTube reads `/srv/metube/downloads/.metube/cookies.txt`
> — a **filtered, secret** media-site cookie jar (not a full Firefox export; mode 600,
> never committed). Refresh it with `stacks/metube/refresh-cookies.sh` when a download
> starts asking for a login. Same README.

---

## Appendix — SSH quick reference

```sh
# On the LAN
ssh root@192.168.1.50        # Proxmox host
ssh rahul@192.168.1.60       # Debian VM

# From anywhere, over the tailnet (MagicDNS names)
ssh root@pve                 # Proxmox host (Tailscale SSH)
ssh rahul@docker-host        # the VM — key auth (Tailscale SSH is off here)
```

The desktop's key was installed on the host once with:

```sh
ssh-copy-id root@192.168.1.50
```

Tailscale SSH (enabled with `tailscale up --ssh`) means the tailnet path to `pve`
needs no key management — Tailscale authenticates you, with a browser `check`
every 12 h. It is **deliberately disabled on `docker-host`**, so SSH there uses
your key like the LAN does (see the backup section above).
