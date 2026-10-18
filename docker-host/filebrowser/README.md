# Filebrowser

Read-only web browser over the laptop backup mirror.

- **Served at:** `https://docker-host.tail91459b.ts.net/files/` — tailnet-only.
- **Deploy:** `docker compose up -d`, then set the admin password with the CLI
  (stop the service first — only one process may touch the database).

## Notes

- Sources `/srv/backup` read-only; the `/files` base URL and read-only defaults
  are set in `config/config.yaml`.
- `share/` is the public share gate (own Tailscale sidecar + Caddy) that
  exposes only `/files/public/*` on the `fileshare` node.
