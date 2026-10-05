# Filebrowser

Read-only web browser over the laptop backup mirror (`/srv/backup`), served at
`/files/`. Tailnet-only. `config/config.yaml` sets the `/files` base URL and
read-only defaults.

Deploy: `docker compose up -d`; set the admin password with the CLI on first run
(stop the service first — only one process may touch the database).

The `share/` subdirectory is the public share gate (its own Tailscale sidecar +
Caddy) that exposes only `/files/public/*` on the `fileshare` node.
