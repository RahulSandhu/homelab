# Vaultwarden

Bitwarden-compatible password manager at `https://pve.tail91459b.ts.net` — its own
name, because it cannot run under a subpath. `pve` reverse-proxies to it over the
LAN.

Deploy: copy `compose.yaml` + `.env.example` to `.env`, generate the admin token
(`docker run --rm -it vaultwarden/server:1.37.3 /vaultwarden hash`; escape `$` as
`$$` in `.env`), then `docker compose up -d`.
