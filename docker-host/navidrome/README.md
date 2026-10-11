# Navidrome

Music streaming (Subsonic API) over `/srv/music`.

- **Served at:** `https://docker-host.tail91459b.ts.net/navidrome` —
  tailnet-only.
- **Deploy:** `docker compose up -d`.

## Notes

- Reads `/srv/music` read-only; the base URL is set in `compose.yaml`.
