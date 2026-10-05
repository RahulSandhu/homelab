# Caddy

Reverse proxy for every `docker-host` web service — routes by path. `tailscale
serve :443` forwards here, and Caddy binds `127.0.0.1` only, so there is no LAN
door. Routes live in `Caddyfile`.

Deploy: `docker compose up -d` (the external `proxy` network must exist first).
