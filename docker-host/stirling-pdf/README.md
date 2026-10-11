# Stirling PDF

Stateless PDF toolbox — merge, split, compress, OCR, convert, sign.

- **Served at:** `https://docker-host.tail91459b.ts.net:10000/` — tailnet-only.
- **Deploy:** `docker compose up -d`.

## Notes

- Its UI hardcodes `<base href="/">`, so it gets its own tailnet port instead of
  a Caddy subpath.
- Stateless: files are processed in temp and deleted; only settings persist.
