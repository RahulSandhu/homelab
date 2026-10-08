# Overleaf (Community Edition)

Self-hosted [Overleaf CE](https://github.com/overleaf/overleaf) — a collaborative
LaTeX editor — for the owner and a small set of **invited** collaborators. It is
the homelab's **third deliberate public exception**: reachable from the internet
via Tailscale Funnel, but only accounts the owner creates can log in.

## What runs where

- **VM `overleaf`** (Proxmox VMID 102) on `pve` — Debian 13, 2 vCPU, 4 GB RAM,
  40 GB disk, `onboot 1`, LAN `192.168.1.61`.
- Inside the VM: the **Overleaf Toolkit** (`/opt/overleaf-toolkit`) runs
  `sharelatex` + `mongo` + `redis` via Docker Compose, on `127.0.0.1:80`.
- **TeX Live**: a locally built image `overleaf-texlive:6.3.0`
  (`FROM sharelatex/sharelatex:6.3.0` + `tlmgr install scheme-full`) so
  collaborators can compile any package. The stock image ships only a minimal
  TeX Live.
- **State**: `/srv/overleaf/{sharelatex,mongo,redis}`, backups in
  `/srv/overleaf/backups`.
- **Tailscale**: the VM is its own tailnet node (`100.81.65.53`,
  `overleaf.tail91459b.ts.net`); `tailscale serve`/`funnel` publish `:443`.
- **Toolkit revision**: commit `5221893829154a0c87d6b945a6952dd3f27e01fb`.
- **Overleaf image**: `6.3.0` (pinned in `config/version`).

## Why a dedicated VM

Overleaf CE has **no sandboxed compiles**: any account holder can run code in the
`sharelatex` container during a compile. A separate VM keeps a compromised or
malicious compile away from `docker-host` — **Vaultwarden** and the laptop's
**only backup mirror** (`/srv/backup`). This is the whole reason it is not just
another stack under `docker-host/`.

## Deploy (from scratch)

On `pve`:

```sh
bash pve/overleaf/create.sh          # creates VM 102 from the Debian cloud image
qm start 102
```

Inside the VM (`ssh rahul@192.168.1.61`):

```sh
TS_AUTHKEY=tskey-... sudo -E bash setup-host.sh    # Docker CE + Tailscale + dirs
sudo bash bootstrap.sh                             # toolkit + image build + stack
```

Then, **before** enabling Funnel, create the admin account at
`https://overleaf.tail91459b.ts.net/launchpad` (or `http://192.168.1.61/`).

## Accounts (no email)

There is no SMTP, so the owner creates every account and hands out the printed
password-set URL.

```sh
cd /opt/overleaf-toolkit
# first admin (or use /launchpad)
sudo bin/docker-compose exec sharelatex /bin/bash -ce \
  "cd /overleaf/services/web && node modules/server-ce-scripts/scripts/create-user --admin --email=you@example.com"
# normal collaborator (omit --admin)
sudo bin/docker-compose exec sharelatex /bin/bash -ce \
  "cd /overleaf/services/web && node modules/server-ce-scripts/scripts/create-user --email=person@example.com"
```

Registration cannot self-create accounts on CE, and `/launchpad` refuses once an
admin exists.

## Sharing a project

Access is by **named account** (invite-only). Anonymous link editing is
**disabled** deliberately: Overleaf CE 6.3.0 has a bug where anonymous edits
stamp `lastUpdatedBy="anonymous-user"`, which the web doc schema rejects, so the
document never flushes and every compile fails with "files out of sync".

To share: create an account for the person (owner runs the `create-user`
command above), send them the printed password-set URL, then add their email as
a collaborator in the project **Share** dialog.

## Public exposure (Tailscale Funnel)

```sh
# after the admin account exists
sudo tailscale funnel --bg --https=443 http://127.0.0.1:80
tailscale funnel status
```

Funnel is the deliberate public exception **for this node only**. Never funnel
`docker-host`. Funnel requires the `funnel` node attribute, and **this tailnet's
policy names the allowed nodes explicitly** — `overleaf` had to be added to it
(Tailscale offers a one-click link when you run the command, or edit the policy's
`nodeAttrs` → `funnel` list). A node not in that list stays tailnet-only even
with Funnel "on".

## Backups

A systemd timer (`overleaf-backup.timer`, daily) runs `overleaf-backup.sh`, which
dumps Mongo and tars the project data into `/srv/overleaf/backups`, pruning to 7
days.

Restore:

```sh
DUMP=$(ls -t /srv/overleaf/backups/mongo-*.archive.gz | head -1)
cd /opt/overleaf-toolkit
sudo bin/docker-compose exec -T mongo mongorestore --archive --gzip --drop < "$DUMP"
# project blobs:
sudo tar -C /srv/overleaf -xzf /srv/overleaf/backups/data-<stamp>.tgz
```

## Upgrades

1. **Snapshot VM 102** in Proxmox first.
2. `cd /opt/overleaf-toolkit && sudo bin/upgrade`.
3. Update the `FROM` tag in `Dockerfile.texlive`, rebuild with the matching tag,
   set `config/version` to that tag, then `sudo bin/up -d`.

TeX Live is tied to the Overleaf image release; rebuilding the derived image
refreshes the package set.
