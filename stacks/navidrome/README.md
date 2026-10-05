# Navidrome stack

[Navidrome](https://www.navidrome.org/) — a Subsonic-API music server — running
on the `docker-host` VM.

The music library is the Samba share's directory (`/srv/music`, a dedicated
50 GB virtual disk) mounted **read-only** into the container. Adding music is
done through the share, not here.

## Files

| File | Purpose |
| --- | --- |
| `compose.yaml` | The service (image pinned to `0.64.2`). |
| `.env.example` | Template — copy to `.env`. |
| `data/` | Navidrome's database/cache (git-ignored, created on first run). |

## Deploy

```sh
mkdir -p /opt/navidrome
scp compose.yaml .env.example rahul@docker-host:/opt/navidrome/
ssh rahul@docker-host 'cd /opt/navidrome && cp -n .env.example .env && docker compose up -d'
```

## Expose

Served tailnet-only at **`/navidrome`** through **Caddy**, which is what
`tailscale serve` points at (`http://localhost:8090`). Do **not** re-point
`tailscale serve` at Navidrome itself.

→ `https://docker-host.tail91459b.ts.net/navidrome` — `ND_BASEURL=/navidrome`

## Operate

```sh
docker compose ps
docker compose logs -f
docker compose restart          # triggers a rescan on start
```

## Users (CLI)

Navidrome ships a user-management CLI. Inside a one-off container (stop the
service first so the DB isn't locked), **always pass `--datafolder /data`** — the
default is `.`, which would silently create a *new, empty* database:

```sh
cd /opt/navidrome
sudo docker compose stop
sudo docker compose run --rm navidrome user list --datafolder /data
sudo docker compose run --rm navidrome user delete -u OLDNAME --datafolder /data
sudo docker compose start
```

**Passwords are TTY-only.** `user create` and `user edit --set-password` prompt on
the terminal, so a plain pipe fails with *"inappropriate ioctl for device"*. Feed
them through a pseudo-TTY instead:

```sh
printf 'THEPASSWORD\nTHEPASSWORD\n' | sudo script -qec \
  "docker compose run --rm navidrome user create -u admin -a --name admin --datafolder /data" /dev/null
```

Notes: the **first** user must be an admin, and the CLI refuses to delete the
*last* remaining user — create the replacement before removing the old one. There
is no rename; create the new user and delete the old (its playlists/play counts go
with it).
