# Zipline

Public file sharing (upload → short link) on its own funneled node,
`zipline.tail91459b.ts.net`. Signups are off, so only the owner can upload.

Deploy: fill `.env` (`CORE_SECRET`, `POSTGRESQL_PASSWORD`, `TS_AUTHKEY`),
`docker compose up -d`, then publish:

```sh
docker exec zipline-ts tailscale funnel --bg --https=443 http://127.0.0.1:3000
```
