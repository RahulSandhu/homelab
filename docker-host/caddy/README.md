# Caddy

Reverse proxy for every `docker-host` web service — routes by path.

- **Served at:** the front door for all web services (`tailscale serve :443` →
  Caddy `127.0.0.1:8090`); loopback-bound, so there is no LAN door.
- **Deploy:** `docker compose up -d` (the external `proxy` network must exist
  first).

## Notes

- Routes live in `Caddyfile`.
