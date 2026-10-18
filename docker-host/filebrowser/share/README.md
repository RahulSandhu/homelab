# Filebrowser shares

Public read-only links to folders in `/srv/backup`, through a share-only Caddy
gate in front of the existing Filebrowser.

- **Served at:** `https://fileshare.tail91459b.ts.net/` — public.
- **Deploy:** fill `.env` (`TS_AUTHKEY`), then:

  ```sh
  docker compose up -d
  docker exec fileshare-ts tailscale funnel --bg --https=443 http://127.0.0.1:8080
  ```

## Notes

- Only `/files/public/*` is exposed; login and the admin API stay private.
