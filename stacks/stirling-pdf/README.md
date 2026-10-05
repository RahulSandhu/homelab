# Stirling PDF

A self-hosted **PDF toolbox** — upload a PDF, get an operation done:

- **Organise:** merge, split, rotate, reorder/delete pages, extract
- **Shrink / convert:** compress, images ↔ PDF, PDF → text
- **Scan:** **OCR** (adds a searchable text layer)
- **Edit:** stamps, page numbers, watermarks, signatures, redaction, annotations
- **Protect:** password, permissions, strip metadata; compare, repair, flatten

Served at **`https://docker-host.tail91459b.ts.net:10000/`** — its own tailnet
port, **not** a Caddy subpath (tailnet-only).

## Stateless — nothing to back up

Files are processed in the container's temp space and **deleted**. There is no
database, no document library, no state. The only thing that persists is its own
`settings.yml` (the `./data` volume). So it can't lose your documents — it never
keeps them.

## Variants

The image ships three flavours; we pin the **standard** one:

| Tag | Notes |
| --- | --- |
| `3.0.0` ⭐ | full PDF toolbox **incl. OCR** (what we run) |
| `3.0.0-fat` | adds LibreOffice/Calibre → **Office → PDF** conversions |
| `3.0.0-ultra-lite` | stripped down, no OCR |

Switching to `-fat` is a one-word change if you ever want Word/Excel → PDF.

## Deploy

```sh
sudo mkdir -p /opt/stirling-pdf/data
scp -r . rahul@docker-host:/tmp/stirling-pdf
ssh rahul@docker-host 'sudo cp /tmp/stirling-pdf/compose.yaml /opt/stirling-pdf/ && sudo chown -R 1000:1000 /opt/stirling-pdf && cd /opt/stirling-pdf && sudo docker compose up -d'
ssh rahul@docker-host 'sudo tailscale serve --bg --https=10000 http://127.0.0.1:8081'
```

It is **not** behind Caddy. Its UI hardcodes `<base href="/" />`, so every asset
resolves against the URL **root** — under a Caddy path (`/pdf`) requests would hit
the dashboard instead of the app. `tailscale serve` only permits ports
**443 / 8443 / 10000** (443 is Caddy, 8443 is AdGuard), so Stirling takes **10000**.
It publishes `127.0.0.1:8081` (localhost only — no LAN door), which `tailscale
serve` forwards. See `docs/specs/2026-09-28-stirling-pdf-design.md`.

## Operate

```sh
docker compose ps
docker compose logs -f
docker compose restart
```
