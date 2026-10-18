# Zipline

Public file sharing — upload, get a short link. Signups are off, so only the
owner can upload.

- **Served at:** `https://zipline.tail91459b.ts.net/` — public.
- **Deploy:** fill `.env` (`CORE_SECRET`, `POSTGRESQL_PASSWORD`, `TS_AUTHKEY`),
  then:

  ```sh
  docker compose up -d
  docker exec zipline-ts tailscale funnel --bg --https=443 http://127.0.0.1:3000
  ```
