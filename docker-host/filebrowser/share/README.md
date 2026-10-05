# Filebrowser shares

Public read-only links to folders in `/srv/backup`, served by the **existing**
Filebrowser through a share-only Caddy gate on its own funneled node
(`fileshare.tail91459b.ts.net`). Only `/files/public/*` is exposed; login and the
admin API stay private.

Deploy: fill `.env` (`TS_AUTHKEY`), `docker compose up -d`, then publish:

```sh
docker exec fileshare-ts tailscale funnel --bg --https=443 http://127.0.0.1:8080
```
