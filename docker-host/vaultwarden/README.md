# Vaultwarden

Bitwarden-compatible password manager; its own tailnet name, because it cannot
run under a subpath.

- **Served at:** `https://pve.tail91459b.ts.net` — tailnet-only (`pve`
  reverse-proxies to it over the LAN).
- **Deploy:** copy `.env.example` to `.env`, generate the admin token (`docker
run --rm -it vaultwarden/server:1.37.3 /vaultwarden hash`; escape `$` as `$$`),
  then `docker compose up -d`.

## Notes

- Set `SIGNUPS_ALLOWED=false` once your account exists.
